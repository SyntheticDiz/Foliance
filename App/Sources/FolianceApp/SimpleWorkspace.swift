import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers
import FolianceCore

struct OpenPDF: Sendable {
    let name: String
    let data: Data
    let pages: [String]
    let findings: [Finding]
    var readings: [PageReading] = []
    var extractedTables: [DocumentTable] = []
    var pageExtractionCache: PageExtractionCache? = nil

    static func read(_ url: URL, progress: (@Sendable (Int, Int) -> Void)? = nil) throws -> OpenPDF {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100_000_000 else { throw AppError(message: "Deze pdf is groter dan 100 MB. Gebruik een kleiner bestand.") }
        let data = try Data(contentsOf: url)
        guard let pdf = PDFDocument(data: data), !pdf.isLocked else {
            throw AppError(message: "Deze pdf is niet leesbaar of is vergrendeld.")
        }
        let sourceFingerprint = LayoutStore.fingerprint(data)
        let overrides = try LayoutStore.read(fingerprint: sourceFingerprint)
        let extracted = try PageLayout.extract(pdf: pdf, overrides: overrides, includeTables: true,
                                               progress: progress, sourceFingerprint: sourceFingerprint)
        guard extracted.hasTextLayer || !extracted.tables.isEmpty else {
            throw AppError(message: "Deze PDF heeft geen leesbare tekstlaag. Maak eerst een doorzoekbare PDF met OCR (tekstherkenning) en importeer die opnieuw.")
        }
        return OpenPDF(name: url.lastPathComponent, data: data, pages: extracted.pages, findings: [],
                       readings: extracted.readings, extractedTables: extracted.tables,
                       pageExtractionCache: extracted.extractionCache)
    }
}

private actor ChatGPTProgramProgressPhase {
    private var reviewingSources = false
    func advance(_ completed: Int) -> Bool {
        if completed < 0 { reviewingSources = true }
        return reviewingSources
    }
}

@MainActor
final class SimpleWorkspace: ObservableObject {
    typealias PointsUpdate = @Sendable ([Insight]) async -> Void
    typealias WarningUpdate = @Sendable (Int) async -> Void
    typealias ProgressUpdate = @Sendable (Int, Int) async -> Void
    typealias CommitteeProgressUpdate = @Sendable (CommitteeAssessmentService.Review, Int, Int) async -> Void
    var summarizeDocument = SummaryService.generate
    var collectHighlights = KeyPointService.generate
    var generateCommitteeReview = CommitteeAssessmentService.generate
    var resumeCommitteeReview = CommitteeAssessmentService.resume
    @Published var progress = AnalysisProgress()
    @Published var keyPoints: [SourceHighlights.Item] = []
    @Published var keyPointIssues = ""
    @Published var keyPointsReady = false
    @Published var tables: [DocumentTable] = [] { didSet { analysisRecordsCache = nil } }
    @Published var tableAnalysisID: String?
    @Published var tableAnalysisError: String?
    private var tableAnalysisTask: Task<Void, Never>?
    var analyzeTableCells = OCRTableAnalysis.generate
    @Published var passageQuestions: [String: [PassageQuestion]] = [:]
    @Published var chosenPassages: [ChosenPassage] = [] { didSet { analysisRecordsCache = nil } }
    private var organizedInsightsCache: [Insight]?
    private let committeePresentationCache = CommitteePresentationCache()
    private var committeePointsRevision = UUID()
    private var committeeReviewRevision = UUID()
    private var insightGroupsCache: [InsightGroup]?
    private var featuredInsightGroupsCache: [InsightGroup]?
    private var selectedInsightGroupsCache: [InsightGroup]?
    private var analysisRecordsCache: [SearchRecord]?
    private var summaryPageSectionsCache: [DocumentSummary.Section]?
    var organizedInsights: [Insight] {
        if let organizedInsightsCache { return organizedInsightsCache }
        let result = InsightOrganization.merged(insights)
        organizedInsightsCache = result
        return result
    }
    func committeePresentationSnapshot(for purpose: MeetingPurpose) -> CommitteePresentationSnapshot? {
        guard let review = committeeReviews[purpose.rawValue] else { return nil }
        return committeePresentationCache.value(documentID: documentID, purpose: purpose,
                                                pointsRevision: committeePointsRevision,
                                                reviewRevision: committeeReviewRevision,
                                                review: review, points: organizedInsights)
    }
    var insightGroups: [InsightGroup] {
        if let insightGroupsCache { return insightGroupsCache }
        let result = InsightOrganization.groups(organizedInsights, readings: document?.readings ?? [])
        insightGroupsCache = result
        return result
    }
    var featuredInsightGroups: [InsightGroup] {
        if let featuredInsightGroupsCache { return featuredInsightGroupsCache }
        let result = InsightOrganization.featured(insightGroups)
        featuredInsightGroupsCache = result
        return result
    }
    var selectedInsightGroups: [InsightGroup] {
        if let selectedInsightGroupsCache { return selectedInsightGroupsCache }
        let selected = organizedInsights.filter(isStarred)
        let result = InsightOrganization.sortedForSelection(InsightOrganization.groups(selected, readings: document?.readings ?? []))
        selectedInsightGroupsCache = result
        return result
    }
    var analysisSearchRecords: [SearchRecord] {
        if let analysisRecordsCache { return analysisRecordsCache }
        let result = UnifiedSearch.analysisRecords(summary: documentSummary, points: organizedInsights, tables: tables,
                                                   chosenPassages: chosenPassages, annotations: annotations)
        analysisRecordsCache = result
        return result
    }
    var summaryPageSections: [DocumentSummary.Section] {
        if let summaryPageSectionsCache { return summaryPageSectionsCache }
        let result = documentSummary?.pageSections ?? []
        summaryPageSectionsCache = result
        return result
    }
    var exportInsights: [Insight] {
        organizedInsights.map { point in
            var seen = Set<String>()
            let questions = ([point.question] + Self.selectionKeys(point).flatMap { passageQuestions[$0] ?? [] }.map(\.question)).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted
            }
            return Insight(title: point.title, summary: point.summary, relevance: point.relevance,
                           question: questions.count > 1 ? questions.map { "• " + $0 }.joined(separator: "\n\n") : questions.first ?? "",
                           quote: point.quote, page: point.page, programSource: point.programSource, otherSources: point.otherSources,
                           passageID: point.passageID, relevanceClass: point.relevanceClass, relevanceReason: point.relevanceReason,
                           contextSources: point.contextSources, passagePartIndex: point.passagePartIndex,
                           passagePartCount: point.passagePartCount, passageSources: point.passageSources)
        }
    }
    @Published var starred: Set<String> = [] { didSet { selectedInsightGroupsCache = nil } }
    @Published var selectionMetadata = SavedSelectionMetadata()
    @Published private(set) var restoredViewState: WorkspaceViewState?
    @Published var meetingPurpose: MeetingPurpose = .raad
    @Published private(set) var committeeReviews: [String: CommitteeAssessmentService.Review] = [:] {
        didSet { committeeReviewRevision = UUID() }
    }
    @Published private(set) var committeeReviewBusy = false
    @Published private(set) var committeeReviewStatus = ""
    @Published private(set) var committeeReviewError: String?
    @Published private(set) var committeeReviewCompleted = 0
    @Published private(set) var committeeReviewTotal = 0
    @Published private(set) var importCommitteeReviewActive = false
    @Published private(set) var importCommitteeReviewPurpose: MeetingPurpose?
    private var committeeReviewHistory: [String: CommitteeAssessmentService.Review] = [:]
    private var committeeReviewTask: Task<Void, Never>?
    private var importCommitteeReviewTask: Task<CommitteeAssessmentService.Review, Error>?
    private var committeeReviewTaskID: UUID?
    private var committeeReviewGeneration = UUID()
    private var committeeReviewRunningPurpose: MeetingPurpose?
    private var committeeReviewRunningModel: String?
    private var automaticLegacyCategorizationAttempts: Set<String> = []
    private var queuedCommitteeReview: (purpose: MeetingPurpose, model: String, documentID: UUID)?
    private var autoCommitteePurposeAfterBase: MeetingPurpose?
    private var importTaskActive = false
    private(set) var revisionToken = UUID()
    @Published private(set) var hasUnsavedChanges = true
    private var savedRevisionToken: UUID?
    private(set) var openedWorkdocumentURL: URL?
    private var openedWorkdocumentAccessURL: URL?
    private var holdsOpenedWorkdocumentAccess = false
    private var terminationReadingPage: Int?
    private var terminationViewState: WorkspaceViewState?
    private var terminationAutosaveInProgress = false
    var workspaceArchiveWriter: @Sendable (WorkspaceArchive, URL) throws -> Void = { archive, url in
        try archive.write(url)
    }
    func markDirty() { revisionToken = UUID(); hasUnsavedChanges = true }
    func markSaved(_ capturedRevision: UUID) {
        if revisionToken == capturedRevision { savedRevisionToken = capturedRevision; hasUnsavedChanges = false }
    }
    func markRestoredClean() { revisionToken = UUID(); savedRevisionToken = revisionToken; hasUnsavedChanges = false }
    func updateTerminationSnapshot(readingPage: Int, viewState: WorkspaceViewState) {
        terminationReadingPage = readingPage
        terminationViewState = viewState
    }
    var isOpenedWorkdocument: Bool { openedWorkdocumentURL != nil }

    func autosaveOpenedWorkdocument() async throws {
        guard let url = openedWorkdocumentURL, document != nil, hasUnsavedChanges else { return }
        guard canStartAnalysis, tableAnalysisID == nil, !exporting else {
            throw AppError(message: "De wijzigingen in \(url.lastPathComponent) kunnen niet automatisch worden bewaard omdat verwerking nog bezig is.")
        }
        terminationAutosaveInProgress = true
        exporting = true
        status = "Werkdocument automatisch bewaren…"
        defer { terminationAutosaveInProgress = false; exporting = false }
        while hasUnsavedChanges {
            try Task.checkCancellation()
            let capturedDocumentID = documentID
            let capturedRevision = revisionToken
            let readingPage = terminationReadingPage ?? page
            let viewState = terminationViewState
            let snapshot = try archive(readingPage: readingPage, viewState: viewState, allowingTerminationAutosave: true)
            let writer = workspaceArchiveWriter
            try await Task.detached(priority: .utility) { try writer(snapshot, url) }.value
            guard documentID == capturedDocumentID, openedWorkdocumentURL == url else {
                throw AppError(message: "Het actieve werkdocument is tijdens automatisch bewaren vervangen. De eerdere momentopname is veilig weggeschreven; sluit de app opnieuw om het nieuwe document te bewaren.")
            }
            markSaved(capturedRevision)
            if hasUnsavedChanges {
                guard !busy, !committeeReviewBusy, !isSwitchingChatGPTModel, tableAnalysisID == nil else {
                    throw AppError(message: "Het werkdocument \(url.lastPathComponent) is gewijzigd tijdens automatisch bewaren. Sluit de app opnieuw zodra de verwerking klaar is.")
                }
            }
        }
        status = "Werkdocument automatisch bewaard: " + url.lastPathComponent
        recordRecentWorkspace(url)
    }

    private func adoptAccess(to url: URL, alreadyStarted access: Bool) {
        releaseOpenedWorkdocumentAccess()
        openedWorkdocumentURL = url
        openedWorkdocumentAccessURL = url
        holdsOpenedWorkdocumentAccess = access
    }

    private func releaseOpenedWorkdocumentAccess() {
        if holdsOpenedWorkdocumentAccess, let url = openedWorkdocumentAccessURL {
            url.stopAccessingSecurityScopedResource()
        }
        openedWorkdocumentURL = nil
        openedWorkdocumentAccessURL = nil
        holdsOpenedWorkdocumentAccess = false
    }

    func closeOpenedWorkdocumentAccess() { releaseOpenedWorkdocumentAccess() }
    func consumeRestoredViewState() -> WorkspaceViewState? { defer { restoredViewState = nil }; return restoredViewState }
    private static func committeeReviewKey(_ review: CommitteeAssessmentService.Review) -> String {
        "\(review.purpose.rawValue)\u{1f}\(review.model)\u{1f}\(review.inputKey)"
    }
    private func publishCommitteeReviewHistory(_ reviews: [CommitteeAssessmentService.Review]) {
        committeeReviewHistory = Dictionary(reviews.map { (Self.committeeReviewKey($0), $0) }, uniquingKeysWith: { _, latest in latest })
        var latestByPurpose: [String: CommitteeAssessmentService.Review] = [:]
        for review in reviews { latestByPurpose[review.purpose.rawValue] = review }
        committeeReviews = latestByPurpose
    }
    private func runImportCommitteeReview(pages: [String], purpose: MeetingPurpose, model: String, expectedDocumentID: UUID) async -> Bool {
        guard purpose != .raad else { return true }
        let generator = generateCommitteeReview
        let runID = UUID()
        let generation = UUID()
        committeeReviewGeneration = generation
        committeeReviewTaskID = runID
        committeeReviewRunningPurpose = purpose
        committeeReviewRunningModel = model
        importCommitteeReviewActive = true
        importCommitteeReviewPurpose = purpose
        committeeReviewBusy = true
        committeeReviewError = nil
        committeeReviewCompleted = 0
        committeeReviewTotal = 0
        committeeReviewStatus = "Voorbereiding voor \(purpose.title)…"
        defer {
            if committeeReviewTaskID == runID {
                committeeReviewTaskID = nil
                committeeReviewBusy = false
                committeeReviewRunningPurpose = nil
                committeeReviewRunningModel = nil
                importCommitteeReviewActive = false
                importCommitteeReviewPurpose = nil
                importCommitteeReviewTask = nil
            }
        }
        do {
            let inputKey = await Task.detached(priority: .userInitiated) {
                CommitteeAssessmentService.inputKey(pages: pages, purpose: purpose, model: model)
            }.value
            guard !Task.isCancelled, documentID == expectedDocumentID else { return false }
            guard committeeReviewGeneration == generation else {
                committeeReviewStatus = "Profielbeoordeling gestopt; basisanalyse start."
                return true
            }
            if let existing = committeeReviewHistory.values.first(where: {
                $0.purpose == purpose && $0.model == model && $0.inputKey == inputKey && $0.complete
            }) {
                let cachedIsValid = await Task.detached(priority: .userInitiated) {
                    CommitteeAssessmentService.validateCurrent(existing, pages: pages, purpose: purpose, model: model)
                }.value
                guard !Task.isCancelled, documentID == expectedDocumentID else { return false }
                guard committeeReviewGeneration == generation else {
                    committeeReviewStatus = "Profielbeoordeling gestopt; basisanalyse start."
                    return true
                }
                if cachedIsValid {
                    committeeReviews[purpose.rawValue] = existing
                    committeeReviewCompleted = existing.entries.count
                    committeeReviewTotal = existing.entries.count
                    progress.update(completed: existing.entries.count, total: existing.entries.count)
                    committeeReviewStatus = "Bewaarde profielbeoordeling hergebruikt."
                    return true
                }
            }
            let review = try await AnalysisMetrics.withPhase("committee", recorder: analysisMeasurement) {
                let reviewTask = Task {
                    try await generator(pages, purpose, model) { snapshot, completed, total in
                        await MainActor.run {
                            guard self.committeeReviewGeneration == generation,
                                  self.documentID == expectedDocumentID,
                                  snapshot.purpose == purpose, snapshot.model == model,
                                  snapshot.inputKey == inputKey else { return }
                            self.committeeReviewHistory[Self.committeeReviewKey(snapshot)] = snapshot
                            self.committeeReviews[purpose.rawValue] = snapshot
                            self.committeeReviewCompleted = completed
                            self.committeeReviewTotal = total
                            self.progress.update(completed: completed, total: total)
                            self.committeeReviewStatus = snapshot.complete ? "Profielbeoordeling afgerond." : "Voorbereiding voor \(purpose.title)…"
                            self.markDirty()
                        }
                    }
                }
                importCommitteeReviewTask = reviewTask
                return try await withTaskCancellationHandler {
                    try await reviewTask.value
                } onCancel: {
                    reviewTask.cancel()
                }
            }
            try Task.checkCancellation()
            let reviewIsValid = await Task.detached(priority: .userInitiated) {
                CommitteeAssessmentService.validateCurrent(review, pages: pages, purpose: purpose, model: model)
            }.value
            try Task.checkCancellation()
            guard committeeReviewGeneration == generation, documentID == expectedDocumentID,
                  review.purpose == purpose, review.model == model, review.inputKey == inputKey,
                  reviewIsValid else {
                guard !Task.isCancelled, documentID == expectedDocumentID else { return false }
                if committeeReviewGeneration != generation {
                    committeeReviewStatus = "Profielbeoordeling gestopt; basisanalyse start."
                    return true
                }
                committeeReviewError = "De profielbeoordeling kon niet veilig aan de bronpassages worden gekoppeld."
                committeeReviewStatus = "Profielbeoordeling niet bevestigd; basisanalyse start."
                return true
            }
            committeeReviewHistory[Self.committeeReviewKey(review)] = review
            committeeReviews[purpose.rawValue] = review
            committeeReviewCompleted = review.entries.filter { $0.rating != .unassessed }.count
            committeeReviewTotal = review.entries.count
            committeeReviewStatus = review.complete ? "Profielbeoordeling gereed; basisanalyse start." : "Profielbeoordeling gedeeltelijk gereed; basisanalyse start."
            markDirty()
            return true
        } catch {
            guard committeeReviewTaskID == runID else { return false }
            if committeeReviewGeneration == generation && !Task.isCancelled {
                committeeReviewError = error.localizedDescription
                committeeReviewStatus = "Profielbeoordeling mislukt; basisanalyse start."
                if let providerError = error as? ChatGPTError {
                    switch providerError {
                    case .quotaExceeded, .planUsageLimit, .usageLimit:
                        chatGPTFailed = true
                        self.error = error.localizedDescription
                        committeeReviewStatus = "Profielbeoordeling gestopt door de AI-gebruiksgrens."
                        return true
                    default: break
                    }
                }
            } else {
                committeeReviewStatus = "Profielbeoordeling gestopt; basisanalyse start."
            }
            return !Task.isCancelled
        }
    }
    var canChangeMeetingPurpose: Bool { !importTaskActive }
    func setMeetingPurpose(_ purpose: MeetingPurpose) {
        guard !importTaskActive else { return }
        guard meetingPurpose != purpose else { return }
        let wasReviewing = committeeReviewBusy
        meetingPurpose = purpose
        committeeReviewError = nil
        committeeReviewStatus = ""
        committeeReviewCompleted = committeeReviews[purpose.rawValue]?.entries.count ?? 0
        committeeReviewTotal = committeeReviews[purpose.rawValue]?.entries.count ?? 0
        markDirty()
        if busy && !importTaskActive { autoCommitteePurposeAfterBase = purpose == .raad ? nil : purpose }
        if purpose != .raad, baseAnalysisSucceeded || wasReviewing {
            if !wasReviewing, baseAnalysisSucceeded,
               let legacyReview = committeeReviews[purpose.rawValue],
               hasAutomaticLegacyCategorizationWork(in: legacyReview) {
                automaticallyCategorizeLegacyReview(legacyReview)
            } else {
                startCommitteeReview()
            }
        } else if wasReviewing {
            stopCommitteeReview()
        }
    }
    var canStartCommitteeReview: Bool {
        guard canStartBaseAnalysis, !committeeReviewBusy, tableAnalysisID == nil,
              let document else { return false }
        return document.pages.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var baseAnalysisSucceeded: Bool {
        guard analyzed, analysisInputKey != nil, documentSummary != nil, summaryInputKey != nil,
              keyPointsReady, highlightsInputKey != nil, error == nil, summaryError == nil,
              analysisIssues.isEmpty, keyPointIssues.isEmpty, !chatGPTFailed else { return false }
        return [.complete, .noMatches, .unconfirmed, .noSummaryPoints].contains(analysisState)
    }
    private var canAutoStartCommitteeReview: Bool {
        canStartCommitteeReview && meetingPurpose != .raad && baseAnalysisSucceeded
    }
    func startCommitteeReview(model requestedModel: String? = nil) {
        guard !importTaskActive else { return }
        guard meetingPurpose != .raad else {
            committeeReviewStatus = "Overzicht gebruikt de algemene documentanalyse."
            committeeReviewError = nil
            return
        }
        let model = requestedModel ?? AIConfiguration.selectedModel
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            committeeReviewError = "Kies eerst een AI-model voor de profielbeoordeling."
            committeeReviewStatus = "Profielbeoordeling niet gestart."
            return
        }
        if committeeReviewBusy {
            guard committeeReviewRunningPurpose != meetingPurpose || committeeReviewRunningModel != model else { return }
            let queued = (meetingPurpose, model, documentID)
            stopCommitteeReview()
            queuedCommitteeReview = queued
            return
        }
        guard canStartCommitteeReview, let document else { return }
        let purpose = meetingPurpose
        let pages = document.pages
        let previousReview = committeeReviews[purpose.rawValue]
        let shouldResume = previousReview?.model == model && previousReview?.complete == false
        var automaticCategorizationAfterResume: (purpose: MeetingPurpose, documentID: UUID, reviewKey: String, model: String)?
        let ownsMeasurement = analysisMeasurement == nil
        let measurement = analysisMeasurement ?? AnalysisMetrics.Recorder(
            model: model, operation: shouldResume ? "committee-resume" : "committee-review")
        let expectedDocumentID = documentID
        let runID = UUID()
        let generation = UUID()
        committeeReviewTaskID = runID
        committeeReviewGeneration = generation
        committeeReviewRunningPurpose = purpose
        committeeReviewRunningModel = model
        committeeReviewBusy = true
        committeeReviewStatus = shouldResume ? "Ontbrekende profielbeoordelingen herstellen…" : "Leesprofiel beoordelen…"
        committeeReviewError = nil
        committeeReviewCompleted = shouldResume ? previousReview?.entries.filter { $0.rating != .unassessed }.count ?? 0 : 0
        committeeReviewTotal = shouldResume ? previousReview?.entries.count ?? 0 : 0
        markDirty()
        let generator = generateCommitteeReview
        let resumer = resumeCommitteeReview
        committeeReviewTask = Task { [weak self] in
            guard let self else { return }
            var measurementOutcome = "completed"
            defer {
                if ownsMeasurement { self.saveDiagnosticMeasurement(measurement, outcome: Task.isCancelled ? "cancelled" : measurementOutcome) }
                if self.committeeReviewTaskID == runID {
                    self.committeeReviewTaskID = nil
                    self.committeeReviewTask = nil
                    self.committeeReviewBusy = false
                    self.committeeReviewRunningPurpose = nil
                    self.committeeReviewRunningModel = nil
                    if self.committeeReviewGeneration == generation && Task.isCancelled {
                        self.committeeReviewStatus = "Profielbeoordeling gestopt."
                    }
                    if self.queuedCommitteeReview == nil,
                       self.committeeReviewGeneration == generation, !Task.isCancelled,
                       let followup = automaticCategorizationAfterResume,
                       self.documentID == followup.documentID,
                       self.meetingPurpose == followup.purpose,
                       let review = self.committeeReviews[followup.purpose.rawValue],
                       Self.committeeReviewKey(review) == followup.reviewKey,
                       self.hasAutomaticLegacyCategorizationWork(in: review) {
                        self.automaticallyCategorizeLegacyReview(review, model: followup.model)
                    }
                    if let queued = self.queuedCommitteeReview {
                        self.queuedCommitteeReview = nil
                        if queued.documentID == self.documentID, queued.purpose == self.meetingPurpose {
                            Task { @MainActor [weak self] in self?.startCommitteeReview(model: queued.model) }
                        }
                    }
                }
            }
            do {
                let expectedInputKey = await Task.detached(priority: .userInitiated) {
                    CommitteeAssessmentService.inputKey(pages: pages, purpose: purpose, model: model)
                }.value
                guard self.committeeReviewGeneration == generation, self.documentID == expectedDocumentID else { return }
                if let existing = self.committeeReviewHistory.values.first(where: {
                    $0.purpose == purpose && $0.model == model && $0.inputKey == expectedInputKey && $0.complete
                }) {
                    self.committeeReviews[purpose.rawValue] = existing
                    self.committeeReviewError = nil
                    self.committeeReviewCompleted = existing.entries.count
                    self.committeeReviewTotal = existing.entries.count
                    self.committeeReviewStatus = "Profielbeoordeling al beschikbaar."
                    return
                }
                let update: CommitteeProgressUpdate = { snapshot, completed, total in
                    await MainActor.run {
                        guard self.committeeReviewGeneration == generation,
                              self.documentID == expectedDocumentID,
                              snapshot.purpose == purpose, snapshot.model == model,
                              snapshot.inputKey == expectedInputKey else { return }
                        self.committeeReviewHistory[Self.committeeReviewKey(snapshot)] = snapshot
                        self.committeeReviews[purpose.rawValue] = snapshot
                        self.committeeReviewCompleted = completed
                        self.committeeReviewTotal = total
                        self.committeeReviewStatus = snapshot.complete ? "Profielbeoordeling afgerond." :
                            shouldResume ? "Ontbrekende profielbeoordelingen herstellen…" : "Profielbeoordeling bezig…"
                        self.markDirty()
                    }
                }
                let review: CommitteeAssessmentService.Review
                if shouldResume, let previousReview {
                    review = try await AnalysisMetrics.withPhase("committee", recorder: measurement) {
                        try await resumer(pages, purpose, model, previousReview, update)
                    }
                } else {
                    review = try await AnalysisMetrics.withPhase("committee", recorder: measurement) {
                        try await generator(pages, purpose, model, update)
                    }
                }
                try Task.checkCancellation()
                let resultIsValid = await Task.detached(priority: .userInitiated) {
                    CommitteeAssessmentService.validate(review, pages: pages, purpose: purpose, model: model)
                }.value
                guard self.committeeReviewGeneration == generation,
                      self.documentID == expectedDocumentID,
                      review.purpose == purpose, review.model == model, review.inputKey == expectedInputKey,
                      resultIsValid else { measurementOutcome = "incomplete"; return }
                self.committeeReviewHistory[Self.committeeReviewKey(review)] = review
                self.committeeReviews[purpose.rawValue] = review
                self.committeeReviewCompleted = review.entries.filter { $0.rating != .unassessed }.count
                self.committeeReviewTotal = review.entries.count
                self.committeeReviewStatus = review.complete ? "Profielbeoordeling afgerond." : "Profielbeoordeling gedeeltelijk afgerond."
                measurementOutcome = review.complete ? "completed" : "incomplete"
                self.markDirty()
                if shouldResume, review.complete {
                    automaticCategorizationAfterResume = (purpose, expectedDocumentID, Self.committeeReviewKey(review), model)
                }
            } catch {
                measurementOutcome = Task.isCancelled ? "cancelled" : "incomplete"
                guard self.committeeReviewTaskID == runID else { return }
                if self.committeeReviewGeneration == generation && !Task.isCancelled {
                    self.committeeReviewError = error.localizedDescription
                    self.committeeReviewStatus = "Profielbeoordeling mislukt."
                } else if self.committeeReviewGeneration != generation {
                    self.committeeReviewStatus = "Profielbeoordeling gestopt."
                }
            }
        }
    }
    var generateCommitteeCategories: (CommitteeAssessmentService.Review, [String], String, @escaping CommitteeCategorizationService.Progress) async throws -> CommitteeAssessmentService.Review = {
        try await CommitteeCategorizationService.categorize(review: $0, pages: $1, model: $2, progress: $3)
    }
    var generateMissingCommitteeCategories: (CommitteeAssessmentService.Review, [String], String, @escaping CommitteeCategorizationService.Progress) async throws -> CommitteeAssessmentService.Review = {
        try await CommitteeCategorizationService.categorize(review: $0, pages: $1, model: $2, missingOnly: true, progress: $3)
    }
    private func hasAutomaticLegacyCategorizationWork(in review: CommitteeAssessmentService.Review) -> Bool {
        guard review.purpose != .raad, review.complete else { return false }
        return review.entries.contains { entry in
            entry.categoryModel == nil && entry.rating != .uncertain && entry.rating != .unassessed &&
                !entry.reason.localizedCaseInsensitiveContains("gesplitste alinea")
        }
    }
    private func automaticallyCategorizeLegacyReview(_ review: CommitteeAssessmentService.Review, model requestedModel: String? = nil) {
        guard canCategorizeCommitteeReview,
              hasAutomaticLegacyCategorizationWork(in: review) else { return }
        let model = requestedModel ?? AIConfiguration.selectedModel
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let attemptKey = "\(documentID.uuidString)\u{1f}\(Self.committeeReviewKey(review))\u{1f}\(model)"
        guard automaticLegacyCategorizationAttempts.insert(attemptKey).inserted else { return }
        categorizeCommitteeReview(model: model, missingOnly: true)
    }
    var canCategorizeCommitteeReview: Bool {
        canStartCommitteeReview && meetingPurpose != .raad && committeeReviews[meetingPurpose.rawValue] != nil
    }
    func categorizeCommitteeReview(model: String = AIConfiguration.selectedModel, missingOnly: Bool = false) {
        guard canCategorizeCommitteeReview, let document,
              let original = committeeReviews[meetingPurpose.rawValue] else { return }
        let pages = document.pages, expectedDocumentID = documentID, purpose = meetingPurpose
        let generation = UUID(), runID = UUID()
        committeeReviewGeneration = generation; committeeReviewTaskID = runID
        committeeReviewRunningPurpose = purpose; committeeReviewRunningModel = model
        committeeReviewBusy = true; committeeReviewError = nil
        committeeReviewCompleted = 0; committeeReviewTotal = original.entries.count
        committeeReviewStatus = "Onderwerpen indelen…"
        let ownsMeasurement = analysisMeasurement == nil
        let measurement = analysisMeasurement ?? AnalysisMetrics.Recorder(model: model, operation: "committee-categorization")
        let generator = missingOnly ? generateMissingCommitteeCategories : generateCommitteeCategories
        committeeReviewTask = Task { [weak self] in
            guard let self else { return }
            var measurementOutcome = "completed"
            defer {
                if ownsMeasurement { self.saveDiagnosticMeasurement(measurement, outcome: measurementOutcome) }
                if self.committeeReviewTaskID == runID {
                    self.committeeReviewTaskID = nil; self.committeeReviewTask = nil
                    self.committeeReviewBusy = false
                    self.committeeReviewRunningPurpose = nil; self.committeeReviewRunningModel = nil
                    if let queued = self.queuedCommitteeReview {
                        self.queuedCommitteeReview = nil
                        if queued.documentID == self.documentID, queued.purpose == self.meetingPurpose {
                            Task { @MainActor [weak self] in self?.startCommitteeReview(model: queued.model) }
                        }
                    }
                }
            }
            do {
                let result = try await AnalysisMetrics.withPhase("categorization", recorder: measurement) {
                    try await generator(original, pages, model) { snapshot, done, total in
                        let merged = await Task.detached(priority: .userInitiated) { CommitteeMetadataMerge.applying(snapshot, to: original) }.value
                        await MainActor.run {
                            guard self.documentID == expectedDocumentID, self.committeeReviewGeneration == generation,
                                  let merged else { return }
                            self.committeeReviews[purpose.rawValue] = merged
                            self.committeeReviewHistory[Self.committeeReviewKey(merged)] = merged
                            self.committeeReviewCompleted = done; self.committeeReviewTotal = total
                            self.markDirty()
                        }
                    }
                }
                try Task.checkCancellation()
                let merged = await Task.detached(priority: .userInitiated) { CommitteeMetadataMerge.applying(result, to: original) }.value
                guard self.documentID == expectedDocumentID, self.committeeReviewGeneration == generation else { return }
                guard let merged else { throw AppError(message: "De onderwerpindeling past niet bij de bewaarde bronpassages.") }
                self.committeeReviews[purpose.rawValue] = merged
                self.committeeReviewHistory[Self.committeeReviewKey(merged)] = merged
                self.committeeReviewStatus = "Onderwerpen ingedeeld; onzekere passages blijven onder Nog in te delen."
                self.markDirty()
            } catch {
                measurementOutcome = Task.isCancelled ? "cancelled" : "incomplete"
                guard self.documentID == expectedDocumentID, self.committeeReviewTaskID == runID else { return }
                if !Task.isCancelled && self.committeeReviewGeneration == generation { self.committeeReviewError = error.localizedDescription }
                self.committeeReviewStatus = "Onderwerpindeling gestopt; bestaande beoordelingen behouden."
            }
        }
    }
    func stopCommitteeReview() {
        guard committeeReviewBusy else { return }
        queuedCommitteeReview = nil
        committeeReviewGeneration = UUID()
        committeeReviewStatus = "Profielbeoordeling annuleren…"
        committeeReviewError = nil
        if importCommitteeReviewActive {
            importCommitteeReviewTask?.cancel()
            return
        }
        guard let task = committeeReviewTask else { return }
        task.cancel()
    }
    private var selectionDocumentKey = ""
    var workStorageKey: String { selectionDocumentKey }
    private func persistChosenPassages() {
        SavedWork.schedule(chosenPassages, key: "chosen-passages-" + selectionDocumentKey)
    }
    private func loadChosenPassages(pageCount: Int) -> [ChosenPassage] {
        let values = SavedWork.read([ChosenPassage].self, key: "chosen-passages-" + selectionDocumentKey) ?? []
        return WorkspaceArchive.validChosenPassages(values, pageCount: pageCount) ? values : []
    }
    private var chosenPassageMutationBlocked: Bool {
        exporting || (busy && processingPresented && !processingDocumentReady)
    }
    @discardableResult func addChosenPassage(_ selection: SelectedPDFText) -> UUID? {
        guard let document, !chosenPassageMutationBlocked,
              !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var seenPages = Set<Int>()
        let pages = selection.pages.filter { seenPages.insert($0).inserted }
        guard !pages.isEmpty, pages.allSatisfy({ $0 > 0 && $0 <= document.pages.count }) else { return nil }
        if let existing = chosenPassages.first(where: { $0.text == selection.text && $0.pages == pages }) { return existing.id }
        var seenSourcePages = Set<Int>()
        let sources = selection.sources.filter {
            pages.contains($0.page) && !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                seenSourcePages.insert($0.page).inserted
        }
        let passage = ChosenPassage(text: selection.text, pages: pages, sources: sources)
        guard WorkspaceArchive.validChosenPassages([passage], pageCount: document.pages.count) else { return nil }
        chosenPassages.append(passage)
        persistChosenPassages()
        markDirty()
        return passage.id
    }
    func updateChosenPassage(id: UUID, title: String, note: String) {
        guard !chosenPassageMutationBlocked, let index = chosenPassages.firstIndex(where: { $0.id == id }) else { return }
        chosenPassages[index].title = title
        chosenPassages[index].note = note
        persistChosenPassages()
        markDirty()
    }
    func removeChosenPassage(id: UUID) {
        guard !chosenPassageMutationBlocked, chosenPassages.contains(where: { $0.id == id }) else { return }
        chosenPassages.removeAll { $0.id == id }
        persistChosenPassages()
        markDirty()
    }
    func moveChosenPassage(id: UUID, by offset: Int) {
        guard !chosenPassageMutationBlocked, let index = chosenPassages.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard chosenPassages.indices.contains(target) else { return }
        chosenPassages.swapAt(index, target)
        persistChosenPassages()
        markDirty()
    }
    nonisolated static func selectionKey(_ point: Insight) -> String {
        if point.passageID != nil { return LocalCache.key(["passage-selection-v1", point.id]) }
        return LocalCache.key([String(point.page), point.quote, point.programSource ?? ""])
    }
    nonisolated static func selectionKeys(_ point: Insight) -> [String] {
        if point.passageID != nil { return [selectionKey(point)] }
        return [selectionKey(point)] + (point.otherSources ?? []).map { LocalCache.key([String($0.page), $0.quote, point.programSource ?? ""]) }
    }
    func isStarred(_ point: Insight) -> Bool { Self.selectionKeys(point).contains(where: starred.contains) }
    func toggleStar(_ point: Insight) {
        let keys = Self.selectionKeys(point)
        if isStarred(point) {
            starred.subtract(keys)
            selectionMetadata.order.removeAll { keys.contains($0) }
            for key in keys { selectionMetadata.statuses.removeValue(forKey: key) }
        } else {
            starred.formUnion(keys)
            for key in keys where !selectionMetadata.order.contains(key) { selectionMetadata.order.append(key) }
            for key in keys where selectionMetadata.statuses[key] == nil { selectionMetadata.statuses[key] = .discuss }
        }
        do { try SavedSelection.write(starred, documentKey: selectionDocumentKey) }
        catch { self.error = "Selectie kon niet worden bewaard: " + error.localizedDescription }
        persistSelectionMetadata()
        markDirty()
    }
    var selectedInsightsInOrder: [Insight] {
        let selected = exportInsights.filter(isStarred)
        let byKey = Dictionary(selected.map { (Self.selectionKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let validOrder = selectionMetadata.order.filter { byKey[$0] != nil && seen.insert($0).inserted }
        let placed = seen
        return validOrder.compactMap { byKey[$0] } + selected.filter { !placed.contains(Self.selectionKey($0)) }
    }
    func meetingStatus(for point: Insight) -> SelectionMeetingStatus {
        selectionMetadata.statuses[Self.selectionKey(point)] ?? .discuss
    }
    func setMeetingStatus(_ status: SelectionMeetingStatus, for point: Insight) {
        let keys = Self.selectionKeys(point)
        guard isStarred(point) else { return }
        for key in keys { selectionMetadata.statuses[key] = status }
        persistSelectionMetadata()
        markDirty()
    }
    func moveSelected(_ point: Insight, by offset: Int) {
        var ordered = selectedInsightsInOrder.map(Self.selectionKey)
        guard let index = ordered.firstIndex(of: Self.selectionKey(point)) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        selectionMetadata.order = ordered
        persistSelectionMetadata()
        markDirty()
    }
    private func persistSelectionMetadata() {
        SavedWork.schedule(selectionMetadata, key: "selection-metadata-" + selectionDocumentKey)
    }
    var baseAnalysisIncomplete: Bool {
        busy || !analyzed || [.notStarted, .running, .needsProgram, .incomplete, .failed, .cancelled].contains(analysisState) ||
        summaryError != nil || !analysisIssues.isEmpty || !keyPointIssues.isEmpty || !citationWarning.isEmpty ||
        documentSummary == nil || !keyPointsReady
    }
    var committeeNeedsAttention: Bool {
        meetingPurpose != .raad && !committeeReviewBusy && committeeReviews[meetingPurpose.rawValue]?.complete != true
    }
    var completionDetails: String {
        let committeeDetail: String? = {
            guard meetingPurpose != .raad, !committeeReviewBusy else { return nil }
            if let committeeReviewError { return "Profielbeoordeling: " + committeeReviewError }
            guard committeeReviews[meetingPurpose.rawValue]?.complete == true else {
                return "Profielbeoordeling niet afgerond; bekijk de beschikbare passages bij Punten."
            }
            return nil
        }()
        return [layoutNotice.isEmpty ? nil : layoutNotice, analysisState == .needsProgram ? analysisState.rawValue : nil, summaryError, analysisIssues.isEmpty ? nil : analysisIssues, citationWarning.isEmpty ? nil : citationWarning,
         committeeDetail,
         keyPointIssues.isEmpty ? nil : keyPointIssues].compactMap { $0 }.joined(separator: "\n\n")
    }
    var completionTitle: String {
        if exporting { return status }
        if busy { return status }
        if baseAnalysisIncomplete { return "Analyse nog niet afgerond" }
        if committeeNeedsAttention { return "Profielbeoordeling nog niet afgerond" }
        if !completionDetails.isEmpty { return "Analyse afgerond · broncontrole nodig" }
        if analyzed || keyPointsReady { return "Verwerking afgerond" }
        return status
    }
    private var chatGPTFailed = false
    @Published var requestedSelection = ""
    @Published var activeModel = ""
    @Published var activeScope = "Hele document"
    @Published var highlightScope = "Hele document"
    @Published var summaryPages: [Int] = []
    @Published var annotations: [String: PointAnnotation] = [:] { didSet { analysisRecordsCache = nil } }
    private var summaryInputKey: String?
    private var highlightsInputKey: String?
    private var analysisInputKey: String?
    private(set) var analysisCompletedPages: [Int]?
    private var highlightsRetry: (pages: [String], model: String, scope: String)?
    var highlightRetryModel: String? { highlightsRetry?.model }
    @Published private(set) var highlightModel: String?
    private var chatGPTRepairCount = 0
    private var lastJob: WorkspaceJob?
    private var chatGPTModelSwitchToken = UUID()
    private var currentAnalysisRunToken = UUID()
    private var preservingResultsDuringModelSwitch = false
    private var canSwitchCurrentAnalysisWorkflow = false
    @Published private(set) var analysisPhase: ChatGPTAnalysisPhase?
    @Published private(set) var isSwitchingChatGPTModel = false
    @Published private(set) var analysisModel: String?
    var canStartAnalysis: Bool {
        canStartBaseAnalysis && !committeeReviewBusy
    }
    private var canStartBaseAnalysis: Bool {
        WorkspaceAnalysisAdmission.canStart(busy: busy, exporting: exporting, switchingModel: isSwitchingChatGPTModel)
    }
    var canSwitchChatGPTModel: Bool {
        busy && !exporting && !isSwitchingChatGPTModel && document != nil &&
            canSwitchCurrentAnalysisWorkflow && analysisPhase != nil && AIConfiguration.isChatGPT(activeModel) && lastJob != nil
    }
    func presentChatGPTModelSwitch() {
        guard canSwitchChatGPTModel else { return }
        showsChatGPTModelSwitch = true
    }
    @Published var showsChatGPTModelSwitch = false

    func applyChatGPTModelSwitch(_ choice: ChatGPTModelChoice, catalog: [ChatGPTModel]) {
        guard canSwitchChatGPTModel, let encodedModel = choice.encoded(using: catalog),
              let phase = analysisPhase, let oldJob = lastJob, let document else { return }
        let nextModel = AIConfiguration.usesChatGPTPlan(activeModel) ? encodedModel + ":plan" : encodedModel
        let expectedDocumentID = documentID
        let expectedRunToken = UUID()
        let selectedPages: [Int]
        do { selectedPages = try PageScope.parse(oldJob.selection, count: document.pages.count) }
        catch { return }
        let pages = PageScope.mask(document.pages, selected: selectedPages)
        let scope = PageScope.label(selectedPages, count: document.pages.count)
        let wasPresented = processingPresented
        let previous = task
        guard let previous else { return }
        chatGPTModelSwitchToken = expectedRunToken

        showsChatGPTModelSwitch = false
        isSwitchingChatGPTModel = true
        status = "Wisselen van ChatGPT-model…"
        let switchTask = Task { [weak self] in
            guard let self else { return }
            await ChatGPTModelSwitchDrain.cancelDrainAndRestart(previous, isCurrent: {
                !Task.isCancelled && self.documentID == expectedDocumentID &&
                    self.chatGPTModelSwitchToken == expectedRunToken && self.document != nil && !self.showsWelcome
            }, restart: {
                guard self.documentID == expectedDocumentID,
                      self.chatGPTModelSwitchToken == expectedRunToken,
                      self.document?.pages == document.pages else { return }
                self.preservingResultsDuringModelSwitch = true
                if phase == .points {
                    self.lastJob = WorkspaceJob(model: nextModel, context: oldJob.context, selection: oldJob.selection,
                                                compare: oldJob.compare, targeted: oldJob.targeted)
                    self.retryParameters = (nextModel, oldJob.context, oldJob.selection, oldJob.compare, oldJob.targeted)
                }
                self.markDirty()
                self.activeModel = nextModel
                self.activeScope = scope
                self.error = nil; self.chatGPTFailed = false
                self.busy = true
                self.processingPresented = wasPresented
                self.processingMessage = nil
                self.canSwitchCurrentAnalysisWorkflow = true
                let later = phase.remainingPhases
                if later.contains(.summary) {
                    self.summaryRetry = (pages, nextModel)
                    self.summaryPages = selectedPages
                    self.summaryScope = scope
                }
                if later.contains(.highlights) {
                    self.highlightsRetry = (pages, nextModel, scope)
                    self.highlightScope = scope
                }
                self.progress.begin(phases: later.count, chatGPT: true)
                self.beginMeasurement(model: nextModel, operation: "model-switch-\(phase.rawValue)")
                let newJob = self.lastJob!
                let replacementTask = Task { [weak self] in
                    guard let self else { return }
                    defer {
                        self.preservingResultsDuringModelSwitch = false
                        self.analysisPhase = nil
                        self.canSwitchCurrentAnalysisWorkflow = false
                        self.finishProcessing()
                    }
                    for currentPhase in later {
                        guard !Task.isCancelled, !self.chatGPTFailed,
                              self.documentID == expectedDocumentID,
                              self.chatGPTModelSwitchToken == expectedRunToken,
                              let activeDocument = self.document else { return }
                        self.analysisPhase = currentPhase
                        switch currentPhase {
                        case .points:
                            self.activeModel = nextModel
                            await self.runAnalysis(document: activeDocument, model: nextModel, context: newJob.context,
                                                   selection: newJob.selection, compareProgram: newJob.compare,
                                                   targeted: newJob.targeted)
                        case .summary:
                            self.summaryPages = selectedPages
                            self.summaryScope = scope
                            await self.makeSummary(pages: pages, model: nextModel)
                        case .highlights:
                            await self.makeHighlights(pages: pages, model: nextModel, scope: scope)
                        }
                    }
                }
                self.task = replacementTask
                self.isSwitchingChatGPTModel = false
            })
            if self.chatGPTModelSwitchToken == expectedRunToken {
                self.isSwitchingChatGPTModel = false
                if self.documentID != expectedDocumentID || Task.isCancelled {
                    self.status = "Modelwissel gestopt; de actieve resultaten zijn behouden."
                }
            }
        }
        task = switchTask
    }
    var canResume: Bool {
        guard let job = lastJob, let document, canStartAnalysis,
              let selected = try? PageScope.parse(job.selection, count: document.pages.count) else { return false }
        let selectedPages = PageScope.mask(document.pages, selected: selected)
        if !AIConfiguration.isChatGPT(job.model) {
            let inputKey = LocalCache.key(selectedPages + [job.model])
            return summaryInputKey != inputKey || highlightsInputKey != inputKey ||
                analysisInputKey != job.key(pages: document.pages, program: programIdentity)
        }
        let summaryModelForRetry = summaryRetry?.model ?? summaryModel ?? job.model
        let summaryPagesForRetry = summaryRetry?.pages ?? selectedPages
        let highlightsModelForRetry = highlightsRetry?.model ?? highlightModel ?? job.model
        let highlightsPagesForRetry = highlightsRetry?.pages ?? selectedPages
        let summaryKey = LocalCache.key(summaryPagesForRetry + [summaryModelForRetry])
        let highlightsKey = LocalCache.key(highlightsPagesForRetry + [highlightsModelForRetry])
        return analysisInputKey != job.key(pages: document.pages, program: programIdentity) ||
            summaryError != nil || summaryInputKey != summaryKey || !keyPointIssues.isEmpty || highlightsInputKey != highlightsKey
    }
    func resumeMissing() {
        guard let job = lastJob, canResume, let document,
              let selected = try? PageScope.parse(job.selection, count: document.pages.count) else { return }
        if !AIConfiguration.isChatGPT(job.model) {
            analyze(model: job.model, context: job.context, targeted: job.targeted, selection: job.selection,
                    compareProgram: job.compare, resumeOnly: true)
            return
        }
        let selectedPages = PageScope.mask(document.pages, selected: selected)
        let summaryModelForRetry = summaryRetry?.model ?? summaryModel ?? job.model
        let summaryPagesForRetry = summaryRetry?.pages ?? selectedPages
        let summaryPageNumbersForRetry = summaryPages.isEmpty ? selected : summaryPages
        let highlightsModelForRetry = highlightsRetry?.model ?? highlightModel ?? job.model
        let highlightsPagesForRetry = highlightsRetry?.pages ?? selectedPages
        let analysisKey = job.key(pages: document.pages, program: programIdentity)
        let summaryKey = LocalCache.key(summaryPagesForRetry + [summaryModelForRetry])
        let highlightsKey = LocalCache.key(highlightsPagesForRetry + [highlightsModelForRetry])
        let needsAnalysis = analysisInputKey != analysisKey
        let needsSummary = summaryError != nil || summaryInputKey != summaryKey
        let needsHighlights = !keyPointIssues.isEmpty || highlightsInputKey != highlightsKey
        let phaseModels = [needsAnalysis ? job.model : nil, needsSummary ? summaryModelForRetry : nil,
                           needsHighlights ? highlightsModelForRetry : nil].compactMap { $0 }
        guard !phaseModels.isEmpty else { return }
        markDirty()
        error = nil; chatGPTFailed = false
        canSwitchCurrentAnalysisWorkflow = false
        busy = true; processingMessage = nil
        progress.begin(phases: phaseModels.count, chatGPT: phaseModels.contains(where: AIConfiguration.isChatGPT))
        beginMeasurement(model: phaseModels[0], operation: "resume")
        preservingResultsDuringModelSwitch = true
        task = Task {
            defer { preservingResultsDuringModelSwitch = false; analysisPhase = nil; finishProcessing() }
            if needsAnalysis && !Task.isCancelled && !chatGPTFailed {
                analysisPhase = .points
                await runAnalysis(document: document, model: job.model, context: job.context,
                                  selection: job.selection, compareProgram: job.compare, targeted: job.targeted)
            }
            if needsSummary && !Task.isCancelled && !chatGPTFailed {
                analysisPhase = .summary; summaryPages = summaryPageNumbersForRetry
                summaryScope = PageScope.label(summaryPages, count: document.pages.count)
                await makeSummary(pages: PageScope.mask(document.pages, selected: summaryPageNumbersForRetry), model: summaryModelForRetry)
            }
            if needsHighlights && !Task.isCancelled && !chatGPTFailed {
                analysisPhase = .highlights
                let pages = highlightsRetry?.pages ?? highlightsPagesForRetry
                let scope = highlightsRetry?.scope ?? highlightScope
                await makeHighlights(pages: pages, model: highlightsModelForRetry, scope: scope)
            }
        }
    }
    var exportAnnotations: [String: PointAnnotation] {
        Dictionary(organizedInsights.compactMap { point in
            let value = annotation(for: point)
            return value.note.isEmpty && value.checkedSignature == nil ? nil : (Self.selectionKey(point), value)
        }, uniquingKeysWith: { first, _ in first })
    }
    func annotation(for point: Insight) -> PointAnnotation { annotations[Self.selectionKey(point)] ?? PointAnnotation() }
    func setAnnotation(_ value: PointAnnotation, for point: Insight) {
        annotations[Self.selectionKey(point)] = value
        SavedWork.schedule(annotations, key: "annotations-" + selectionDocumentKey)
        markDirty()
    }

    func setPassageQuestions(_ questions: [PassageQuestion], for key: String) {
        passageQuestions[key] = questions
        SavedWork.schedule(passageQuestions, key: "questions-" + selectionDocumentKey)
        markDirty()
    }

    private func makeHighlights(pages: [String], model: String, scope: String) async {
        await AnalysisMetrics.withPhase("highlights", recorder: analysisMeasurement) {
            await makeHighlightsMeasured(pages: pages, model: model, scope: scope)
        }
    }

    private func makeHighlightsMeasured(pages: [String], model: String, scope: String) async {
        guard !Task.isCancelled else { return }
        analysisPhase = .highlights
        let phaseDocumentID = documentID
        let phaseSwitchToken = chatGPTModelSwitchToken
        let previousHighlightScope = highlightScope
        highlightsRetry = (pages, model, scope); highlightScope = scope
        activeModel = model; activeScope = scope
        highlightsInputKey = nil
        let keepPublishedHighlights = preservingResultsDuringModelSwitch ||
            (canSwitchCurrentAnalysisWorkflow && AIConfiguration.isChatGPT(model) && previousHighlightScope == scope)
        if !keepPublishedHighlights { keyPoints = []; keyPointsReady = false; highlightModel = nil }
        keyPointIssues = ""; progress.next()
        do {
            let result = try await collectHighlights(pages, model) { points, current, total in
                await MainActor.run {
                    if AIConfiguration.isChatGPT(model) &&
                        (Task.isCancelled || self.documentID != phaseDocumentID || self.chatGPTModelSwitchToken != phaseSwitchToken) { return }
                    self.progress.update(completed: current, total: total)
                    if !keepPublishedHighlights {
                        self.keyPoints = points
                        self.highlightModel = model
                    }
                    self.status = "Kernpunten beoordelen: \(current) van \(total)…\(AIConfiguration.phaseModelLabel(model, role: .worker))"
                }
            }
            try Task.checkCancellation()
            if AIConfiguration.isChatGPT(model),
               (documentID != phaseDocumentID || chatGPTModelSwitchToken != phaseSwitchToken) { return }
            if result.issues.isEmpty { highlightsInputKey = LocalCache.key(pages + [model]) }
            keyPoints = result.points; keyPointIssues = result.issues.joined(separator: "\n"); keyPointsReady = true
            highlightModel = model
        } catch {
            if AIConfiguration.isChatGPT(model),
               (documentID != phaseDocumentID || chatGPTModelSwitchToken != phaseSwitchToken) { return }
            if error is ChatGPTError { chatGPTFailed = true }
            if !Task.isCancelled { self.error = error.localizedDescription }
            keyPointIssues = Task.isCancelled ? "Kernselectie gestopt; de selectie is onvolledig." : error.localizedDescription }
    }
    func retryHighlights(model: String = AIConfiguration.selectedModel) {
        guard canStartAnalysis, let document else { return }
        let saved = highlightsRetry ?? (document.pages, model, "Hele document")
        error = nil; chatGPTFailed = false
        canSwitchCurrentAnalysisWorkflow = false
        busy = true; progress.begin(phases: 1, chatGPT: AIConfiguration.isChatGPT(saved.1))
        beginMeasurement(model: saved.1, operation: "retry-highlights")
        task = Task { defer { analysisPhase = nil; finishProcessing() }; await makeHighlights(pages: saved.0, model: saved.1, scope: saved.2) }
    }
    var loadProgram: () throws -> PartyProgram? = { try PartyProgram.load() }
    private var archivedReference: PartyProgram?
    private var observedReferenceSettings: String?
    private func currentReference() throws -> PartyProgram? { try archivedReference ?? loadProgram() }
    func useConfiguredReference() {
        let configured = try? loadProgram()
        let key = configured.map { LocalCache.key([$0.name, $0.criteria ?? ""] + $0.pages) } ?? "none"
        if observedReferenceSettings != key {
            archivedReference = nil
            if document != nil { markDirty() }
        }
        observedReferenceSettings = key
        refreshProgram()
    }
    var compareDocument: ([String], String, String, PartyProgram, @escaping PointsUpdate, @escaping WarningUpdate, @escaping ProgressUpdate) async throws -> [Insight] = { pages, model, context, program, update, warning, progress in
        try await AIService.analyzeLocal(pages: pages, model: model, context: context, program: program, update: update, warning: warning, progress: progress)
    }
    @Published var documentID = UUID() {
        didSet { committeePresentationCache.clear() }
    }
    @Published var summaryScope = "Hele document"
    @Published var focus = UserDefaults.standard.string(forKey: "savedProgramFocus") ?? UserDefaults.standard.string(forKey: "committeeContext") ?? ""
    @Published var programName = ""
    @Published var programIdentity = ""
    private var analysisProgramName = ""
    @Published var programChanged = false
    private var analyzedProgramKey: String?
    let documentChat = DocumentChatSession()
    let pageChat = DocumentChatSession()
    @Published var document: OpenPDF? { didSet { insightGroupsCache = nil; featuredInsightGroupsCache = nil; selectedInsightGroupsCache = nil } }
    @Published var documentSummary: DocumentSummary? {
        didSet {
            analysisRecordsCache = nil
            summaryPageSectionsCache = nil
            if documentSummary != nil { analysisMeasurement?.summaryReady() }
        }
    }
    @Published var summaryError: String?
    private var summaryRetry: (pages: [String], model: String)?
    var summaryRetryModel: String? { summaryRetry?.model }
    func retrySummary() {
        guard canStartAnalysis, let saved = summaryRetry else { return }
        error = nil; chatGPTFailed = false
        canSwitchCurrentAnalysisWorkflow = false
        busy = true; progress.begin(phases: 1, chatGPT: AIConfiguration.isChatGPT(saved.model))
        beginMeasurement(model: saved.model, operation: "retry-summary")
        task = Task {
            defer { analysisPhase = nil; finishProcessing() }
            await makeSummary(pages: saved.pages, model: saved.model)
        }
    }
    @Published var insights: [Insight] = [] {
        didSet {
            if !insights.isEmpty { analysisMeasurement?.result(main: insights.contains { $0.relevanceClass == "main" }) }
            organizedInsightsCache = nil; insightGroupsCache = nil; featuredInsightGroupsCache = nil; selectedInsightGroupsCache = nil; analysisRecordsCache = nil
            committeePointsRevision = UUID()
        }
    }
    @Published var showsWelcome = true
    @Published var processingPresented = false
    @Published private(set) var processingDocumentReady = false
    @Published var processingName = ""
    @Published var processingMessage: String?
    @Published var busy = false
    @Published var status = "Kies een pdf om te beginnen."
    @Published var error: String?
    @Published var analysisState = AnalysisState.notStarted
    @Published var neutralAnalysis = false
    @Published var analyzed = false
    @Published var citationWarning = ""
    @Published var analysisIssues = ""
    private var retryParameters: (model: String, context: String, selection: String, compare: Bool, targeted: Bool)?
    func retryIncompleteAnalysis() {
        guard canStartAnalysis, canResume else { return }
        if let job = lastJob, !AIConfiguration.isChatGPT(job.model), let retry = retryParameters {
            analyze(model: retry.model, context: retry.context, targeted: retry.targeted, selection: retry.selection,
                    compareProgram: retry.compare, resumeOnly: true)
            return
        }
        resumeMissing()
    }
    @Published var analysisContext = ""
    @Published var analysisScope = "Hele document"
    private var localFocus = ""
    @Published var page = 1
    @Published var navigationID = UUID()
    private var task: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var importProgressID: UUID?
    private var analysisMeasurement: AnalysisMetrics.Recorder?
    private var cloudInsightPresentationID: UUID?
    private func beginMeasurement(model: String, operation: String) {
        analysisMeasurement = AnalysisMetrics.Recorder(model: model, operation: operation)
    }
    private func saveDiagnosticMeasurement(_ recorder: AnalysisMetrics.Recorder, outcome: String) {
        let report = recorder.report(outcome: outcome)
        let directory = AnalysisMetrics.directory
        Task.detached(priority: .utility) { AnalysisMetrics.save(report, to: directory) }
    }
    private func publishCloudInsightPresentation(_ points: [Insight], scope: String, model: String,
                                                 documentID expectedDocumentID: UUID,
                                                 presentationID: UUID) async throws -> Bool {
        guard documentID == expectedDocumentID, cloudInsightPresentationID == presentationID,
              let readings = document?.readings else { return false }
        let snapshot = try await CloudInsightPresentation.makeOffMain(insights: points, readings: readings)
        try Task.checkCancellation()
        guard documentID == expectedDocumentID, cloudInsightPresentationID == presentationID else { return false }
        insights = snapshot.insights
        organizedInsightsCache = snapshot.organizedInsights
        insightGroupsCache = snapshot.insightGroups
        featuredInsightGroupsCache = snapshot.featuredInsightGroups
        selectedInsightGroupsCache = nil
        analysisRecordsCache = nil
        analyzed = true
        neutralAnalysis = true
        analysisScope = scope
        analysisContext = ""
        programChanged = false
        analysisModel = model
        return true
    }
    @Published private(set) var exporting = false
    @Published private(set) var exportWriting = false
    var canCancelExport: Bool { exporting && !exportWriting && exportTask != nil }

    func cancelExport() {
        guard canCancelExport else { return }
        status = "PDF-export annuleren…"
        exportTask?.cancel()
    }

    private func beginProcessing(name: String) {
        processingName = name
        processingMessage = nil
        processingPresented = true
    }

    private func finishProcessing() {
        if let measurement = analysisMeasurement {
            let incomplete = error != nil || summaryError != nil || committeeReviewError != nil ||
                !analysisIssues.isEmpty || !keyPointIssues.isEmpty || analysisState == .needsProgram
            let report = measurement.report(outcome: Task.isCancelled ? "cancelled" : incomplete ? "incomplete" : "completed")
            let directory = AnalysisMetrics.directory
            analysisMeasurement = nil
            Task.detached(priority: .utility) { AnalysisMetrics.save(report, to: directory) }
        }
        busy = false
        if Task.isCancelled { autoCommitteePurposeAfterBase = nil }
        if Task.isCancelled, showsWelcome, document == nil { returnToImport(); return }
        if let purpose = autoCommitteePurposeAfterBase {
            autoCommitteePurposeAfterBase = nil
            if meetingPurpose == purpose, canAutoStartCommitteeReview { startCommitteeReview(model: activeModel) }
        }
        guard processingPresented, !Task.isCancelled else { return }
        processingMessage = error ?? (completionDetails.isEmpty ? nil : completionDetails)
        guard processingMessage == nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, self.processingPresented, !self.busy, self.processingMessage == nil else { return }
            self.processingPresented = false
        }
    }

    func showInterimResults() {
        guard busy, processingDocumentReady, !showsWelcome, document != nil else { return }
        processingPresented = false
    }

    func showProcessedResults() {
        guard canStartAnalysis, document != nil else { return }
        error = nil
        processingPresented = false
        showsWelcome = false
    }

    func returnToImport() {
        if committeeReviewBusy { stopCommitteeReview() }
        chatGPTModelSwitchToken = UUID()
        analysisPhase = nil
        isSwitchingChatGPTModel = false
        canSwitchCurrentAnalysisWorkflow = false
        if busy, !processingDocumentReady, document != nil {
            // A replacement PDF has not become the active document yet. Stop
            // that import and return to the existing workspace intact.
            task?.cancel(); progress.resetChatGPTEstimateForCancellation()
            importProgressID = nil
            processingDocumentReady = false
            processingPresented = false
            processingMessage = nil
            showsWelcome = false
            status = "Pdf inladen geannuleerd; huidig document behouden."
            return
        }
        task?.cancel(); progress.resetChatGPTEstimateForCancellation(); tableAnalysisTask?.cancel(); tableAnalysisID = nil; tableAnalysisError = nil
        importProgressID = nil
        processingDocumentReady = false
        processingPresented = false
        processingMessage = nil
        showsWelcome = true
        terminationReadingPage = nil
        terminationViewState = nil
        releaseOpenedWorkdocumentAccess()
        document = nil
        documentSummary = nil
        insights = []; tables = []; keyPoints = []; passageQuestions = [:]; chosenPassages = []
        savedChatThreads = []; savedChartAnalyses = []; savedSelectionSummaries = []
        meetingPurpose = .raad
        committeeReviewHistory = [:]; committeeReviews = [:]
        committeeReviewError = nil; committeeReviewStatus = ""
        committeeReviewCompleted = 0; committeeReviewTotal = 0
        analyzed = false; keyPointsReady = false
        summaryError = nil; error = nil; analysisIssues = ""; citationWarning = ""; keyPointIssues = ""
        summaryRetry = nil; summaryModel = nil; retryParameters = nil; highlightsRetry = nil; highlightModel = nil; lastJob = nil
        summaryInputKey = nil; highlightsInputKey = nil; analysisInputKey = nil; analysisCompletedPages = nil; annotations = [:]
        analysisState = .cancelled
        analysisModel = nil
        status = "Kies een pdf om te beginnen."
        documentID = UUID()
        documentChat.reset(); pageChat.reset()
    }

    func newDocument() {
        guard canStartAnalysis else { return }
        // Keep the current result available until a replacement PDF is successfully imported.
        showsWelcome = true
        status = "Kies een pdf om te beginnen."
    }

    @discardableResult func load(_ urls: [URL], themes: [Theme] = [], focus: String = "", model: String? = nil, compareProgram: Bool = true,
                                 meetingPurpose importPurpose: MeetingPurpose = .raad) -> Task<Void, Never>? {
        guard canStartBaseAnalysis else { return nil }
        guard urls.count == 1, let url = urls.first, url.isFileURL, url.pathExtension.lowercased() == "pdf" else {
            error = "Kies of sleep één pdf-bestand tegelijk."; return nil
        }
        if committeeReviewBusy { stopCommitteeReview() }
        let previousCommitteeReview = committeeReviewTask
        autoCommitteePurposeAfterBase = nil
        chatGPTModelSwitchToken = UUID()
        analysisPhase = nil
        isSwitchingChatGPTModel = false
        canSwitchCurrentAnalysisWorkflow = model.map(AIConfiguration.isChatGPT) ?? false
        chatGPTFailed = false
        let hasImportCommitteePhase = model != nil && importPurpose != .raad
        busy = true; progress.begin(phases: model == nil ? 1 : (hasImportCommitteePhase ? 5 : 4), chatGPT: model.map(AIConfiguration.isChatGPT) ?? false); progress.next(); status = "Pdf inladen…"; error = nil
        processingDocumentReady = false
        let progressID = UUID()
        importProgressID = progressID
        beginProcessing(name: url.lastPathComponent)
        beginMeasurement(model: model ?? "none", operation: "import")
        importTaskActive = true
        task = Task {
            defer {
                importProgressID = nil
                importTaskActive = false
                analysisPhase = nil
                canSwitchCurrentAnalysisWorkflow = false
                finishProcessing()
            }
            do {
                if let previousCommitteeReview { await previousCommitteeReview.value }
                try Task.checkCancellation()
                let extraction = Task.detached(priority: .userInitiated) {
                    try OpenPDF.read(url) { completed, total in
                        Task { @MainActor in
                            guard self.importProgressID == progressID else { return }
                            self.progress.update(completed: completed, total: total)
                            self.status = "Pdf lezen: pagina \(completed) van \(total)…"
                        }
                    }
                }
                let loaded = try await AnalysisMetrics.withPhase("import", recorder: analysisMeasurement) {
                    try await withTaskCancellationHandler {
                        try await extraction.value
                    } onCancel: {
                        extraction.cancel()
                    }
                }
                try Task.checkCancellation()
                importProgressID = nil
                tables = loaded.extractedTables
                try Task.checkCancellation()
                passageQuestions = [:]
                savedChatThreads = []; savedChartAnalyses = []; savedSelectionSummaries = []
                keyPoints = []; keyPointIssues = ""; keyPointsReady = false
                meetingPurpose = importPurpose
                committeeReviewHistory = [:]; committeeReviews = [:]
                committeeReviewError = nil; committeeReviewStatus = ""
                committeeReviewCompleted = 0; committeeReviewTotal = 0
                archivedReference = nil
                selectionDocumentKey = LocalCache.key(loaded.pages)
                chosenPassages = loadChosenPassages(pageCount: loaded.pages.count)
                passageQuestions = SavedWork.read([String: [PassageQuestion]].self, key: "questions-" + selectionDocumentKey) ?? [:]
                starred = SavedSelection.read(documentKey: selectionDocumentKey)
                selectionMetadata = SavedWork.read(SavedSelectionMetadata.self, key: "selection-metadata-" + selectionDocumentKey) ?? .init()
                normalizeSelectionMetadata()
                releaseOpenedWorkdocumentAccess()
                markDirty()
                annotations = SavedWork.read([String: PointAnnotation].self, key: "annotations-" + selectionDocumentKey) ?? [:]
                summaryInputKey = nil; highlightsInputKey = nil; analysisInputKey = nil; analysisCompletedPages = nil; highlightsRetry = nil; highlightModel = nil; lastJob = nil
                summaryPages = Array(1...loaded.pages.count); highlightScope = "Hele document"
                requestedSelection = ""
                activeModel = model ?? ""; activeScope = "Hele document"
                analysisIssues = ""; retryParameters = nil
                analysisState = .notStarted; neutralAnalysis = false
                analysisModel = nil
                documentSummary = nil; summaryError = nil; summaryRetry = nil; summaryModel = nil; summaryScope = "Hele document"
                tableAnalysisTask?.cancel(); tableAnalysisID = nil; tableAnalysisError = nil
                documentID = UUID(); documentChat.reset(); pageChat.reset()
                self.focus = UserDefaults.standard.string(forKey: "savedProgramFocus") ?? UserDefaults.standard.string(forKey: "committeeContext") ?? ""
                refreshProgram()
                document = loaded; citationWarning = ""; insights = []; analyzed = false; page = 1; navigationID = UUID()
                terminationReadingPage = 1; terminationViewState = nil
                let empty = loaded.pages.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                status = "\(loaded.pages.count) pagina’s" + (empty > 0 ? " · \(empty) pagina’s zonder leesbare tekst" : "")
                showsWelcome = false; localFocus = self.focus
                processingDocumentReady = true
                if let model, importPurpose != .raad {
                    progress.next()
                    status = "Voorbereiding voor \(importPurpose.title)…"
                    let importedDocumentID = documentID
                    let reviewCanContinue = await runImportCommitteeReview(pages: loaded.pages, purpose: importPurpose, model: model, expectedDocumentID: importedDocumentID)
                    guard reviewCanContinue, !Task.isCancelled, documentID == importedDocumentID else { return }
                }
                if let model {
                    activeModel = model; activeScope = "Hele document"
                    lastJob = WorkspaceJob(model: model, context: self.focus, selection: "", compare: compareProgram, targeted: false)
                    if !Task.isCancelled && !chatGPTFailed {
                        analysisPhase = .points
                        await runAnalysis(document: loaded, model: model, context: self.focus, selection: "", compareProgram: compareProgram)
                        if !Task.isCancelled && !chatGPTFailed { analysisPhase = .summary; await makeSummary(pages: loaded.pages, model: model) }
                        if !Task.isCancelled && !chatGPTFailed { await makeHighlights(pages: loaded.pages, model: model, scope: "Hele document") }
                    }
                }

            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription; status = "Pdf inladen mislukt." }
            }
            analysisPhase = nil
            canSwitchCurrentAnalysisWorkflow = false
        }
        return task
    }

    func analyze(model: String, context: String, targeted: Bool = false, selection: String = "", compareProgram: Bool = true, resumeOnly: Bool = false) {
        guard canStartAnalysis, let document else { return }
        let selected: [Int]
        let selectedPages: [String]
        let scope: String
        do {
            selected = try PageScope.parse(selection, count: document.pages.count)
            selectedPages = PageScope.mask(document.pages, selected: selected)
            guard selectedPages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw AppError(message: "De gekozen pagina’s bevatten geen leesbare tekst.")
            }
            scope = PageScope.label(selected, count: document.pages.count)
        } catch {
            self.error = error.localizedDescription
            return
        }
        markDirty()
        refreshProgram()
        let job = WorkspaceJob(model: model, context: context, selection: selection, compare: compareProgram, targeted: targeted)
        let inputKey = LocalCache.key(selectedPages + [model])
        let analysisKey = job.key(pages: document.pages, program: programIdentity)
        let needsSummary = documentSummary == nil || summaryInputKey != inputKey || summaryError != nil
        let needsAnalysis = !resumeOnly || analysisInputKey != analysisKey
        let needsHighlights = !resumeOnly || highlightsInputKey != inputKey
        let phases = [needsSummary, needsAnalysis, needsHighlights].filter { $0 }.count
        guard phases > 0 else { status = "Alle onderdelen zijn al gereed."; return }
        requestedSelection = selection
        lastJob = job; activeModel = model; activeScope = scope; error = nil
        canSwitchCurrentAnalysisWorkflow = AIConfiguration.isChatGPT(model)
        chatGPTFailed = false
        busy = true; progress.begin(phases: phases, chatGPT: AIConfiguration.isChatGPT(model))
        beginMeasurement(model: model, operation: resumeOnly ? "resume" : "analyze")
        task = Task {
            defer { analysisPhase = nil; canSwitchCurrentAnalysisWorkflow = false; finishProcessing() }
            if needsAnalysis { analysisPhase = .points }
            if needsAnalysis && !Task.isCancelled && !chatGPTFailed { await runAnalysis(document: document, model: model, context: context, selection: selection, compareProgram: compareProgram, targeted: targeted) }
            if needsSummary && !Task.isCancelled && !chatGPTFailed {
                analysisPhase = .summary
                if !AIConfiguration.isChatGPT(model) || summaryPages != selected {
                    documentSummary = nil
                    summaryModel = nil
                }
                summaryScope = scope; summaryPages = selected
                await makeSummary(pages: selectedPages, model: model)
            }
            if needsHighlights && !Task.isCancelled && !chatGPTFailed { analysisPhase = .highlights; await makeHighlights(pages: selectedPages, model: model, scope: scope) }
        }
    }

    private func runAnalysis(document: OpenPDF, model: String, context: String, selection: String, compareProgram: Bool, targeted: Bool = false) async {
        await AnalysisMetrics.withPhase("analysis", recorder: analysisMeasurement) {
            await runAnalysisMeasured(document: document, model: model, context: context, selection: selection, compareProgram: compareProgram, targeted: targeted)
        }
    }

    private func runAnalysisMeasured(document: OpenPDF, model: String, context: String, selection: String, compareProgram: Bool, targeted: Bool) async {
        let presentationDocumentID = documentID
        analysisPhase = .points
        let analysisRunToken = UUID()
        currentAnalysisRunToken = analysisRunToken
        let cloudPresentationID: UUID? = !compareProgram && AIConfiguration.isChatGPT(model) ? UUID() : nil
        cloudInsightPresentationID = cloudPresentationID
        chatGPTRepairCount = 0
        progress.next()
        retryParameters = (model, context, selection, compareProgram, targeted)
        let jobKey = WorkspaceJob(model: model, context: context, selection: selection, compare: compareProgram, targeted: targeted).key(pages: document.pages, program: programIdentity)
        analysisInputKey = nil
        analysisCompletedPages = nil
        analysisIssues = ""
        citationWarning = ""; analysisState = .running
        status = compareProgram ? "Vergelijken met referentiedocument…" : "Neutrale samenvattingspunten maken…"; error = nil
            do {
                let warn: @Sendable (Int) async -> Void = { count in
                    await MainActor.run {
                        if AIConfiguration.isChatGPT(model) &&
                            (Task.isCancelled || self.documentID != presentationDocumentID || self.currentAnalysisRunToken != analysisRunToken) { return }
                        self.citationWarning = "Broncontrole: ongeldige citaten weggelaten. Alleen bevestigde punten worden getoond; de selectie kan onvolledig zijn."
                    }
                }
                let selected = try PageScope.parse(selection, count: document.pages.count)
                let selectedPages = PageScope.mask(document.pages, selected: selected)
                guard selectedPages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AppError(message: "De gekozen pagina’s bevatten geen leesbare tekst.") }
                let scope = PageScope.label(selected, count: document.pages.count)
                if analysisScope != scope { insights = []; analyzed = false; analysisModel = nil; analysisScope = scope }
                if !compareProgram {
                    let result = try await NeutralOutline.analyze(pages: selectedPages, model: model, focus: context, repairUpdate: { count in
                        await MainActor.run {
                            guard AIConfiguration.isChatGPT(model) else { return }
                            self.chatGPTRepairCount = count
                            self.status = "Alineapunten: \(self.progress.phaseCompleted) van \(self.progress.phaseTotal) gereed…\(AIConfiguration.phaseModelLabel(model, role: .worker))\(self.chatGPTRepairSuffix)"
                        }
                    }, update: { points in
                        if let cloudPresentationID {
                            _ = try? await self.publishCloudInsightPresentation(points, scope: scope, model: model,
                                                                                documentID: presentationDocumentID,
                                                                                presentationID: cloudPresentationID)
                        } else {
                            await MainActor.run { self.insights = points; self.analyzed = true; self.neutralAnalysis = true; self.analysisScope = scope; self.analysisContext = context; self.programChanged = false; self.analysisModel = model }
                        }
                    }, warning: warn, progress: { current, total in
                        await MainActor.run {
                            if AIConfiguration.isChatGPT(model) &&
                                (Task.isCancelled || self.documentID != presentationDocumentID || self.currentAnalysisRunToken != analysisRunToken) { return }
                            self.progress.update(completed: AIConfiguration.isChatGPT(model) ? current : max(0, current - 1), total: total)
                            self.status = AIConfiguration.isChatGPT(model)
                                ? "Alineapunten: \(current) van \(total) gereed…\(AIConfiguration.phaseModelLabel(model, role: .worker))\(self.chatGPTRepairSuffix)"
                                : "Alinea \(current) van \(total) samenvatten…"
                        }
                    })
                    try Task.checkCancellation()
                    if let cloudPresentationID {
                        guard documentID == presentationDocumentID,
                              cloudInsightPresentationID == cloudPresentationID else { return }
                        guard try await publishCloudInsightPresentation(result, scope: scope, model: model,
                                                                        documentID: presentationDocumentID,
                                                                        presentationID: cloudPresentationID) else { return }
                        analysisModel = model
                    } else {
                        insights = result; analyzed = true; neutralAnalysis = true; analysisScope = scope; analysisContext = context; programChanged = false
                        analysisModel = model
                    }
                    analysisState = result.isEmpty ? .noSummaryPoints : .complete
                    analysisInputKey = jobKey
                    analysisCompletedPages = selectedPages.enumerated().compactMap { $0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.offset + 1 }
                    status = "Neutrale samenvatting gereed."
                    return
                }
                guard let program = try currentReference() else {
                    analysisState = .needsProgram
                    status = "Voeg eerst je referentiedocument toe via Instellingen. Samenvatten en documentchat blijven beschikbaar."
                    return
                }
                let programKey = LocalCache.key([program.name, program.criteria ?? ""] + program.pages)
                let result: [Insight]
                    let chatGPTProgressPhase = ChatGPTProgramProgressPhase()
                    result = try await compareDocument(selectedPages, model, context, program, { points in
                        await MainActor.run {
                            if AIConfiguration.isChatGPT(model) &&
                                (Task.isCancelled || self.documentID != presentationDocumentID || self.currentAnalysisRunToken != analysisRunToken) { return }
                            self.insights = points; self.analyzed = true; self.neutralAnalysis = false; self.analysisContext = context; self.analysisScope = scope; self.analyzedProgramKey = programKey; self.analysisProgramName = program.name; self.programChanged = self.programIdentity != programKey
                            self.analysisModel = model
                        }
                    }, warn) { current, total in
                        let isChatGPT = AIConfiguration.isChatGPT(model)
                        let isReviewing = isChatGPT ? await chatGPTProgressPhase.advance(current) : false
                        await MainActor.run {
                            if isChatGPT &&
                                (Task.isCancelled || self.documentID != presentationDocumentID || self.currentAnalysisRunToken != analysisRunToken) { return }
                            self.progress.update(completed: isChatGPT ? current : (current == 0 ? total : max(0, current - 1)), total: total)
                            if isChatGPT {
                                let role: AIConfiguration.ChatGPTRole = isReviewing ? .orchestrator : .worker
                                let phase = isReviewing ? "Bronnen controleren aan oorspronkelijke passages…" : "Programmapassages vergelijken…"
                                self.status = phase + AIConfiguration.phaseModelLabel(model, role: role)
                            } else { self.status = current == 0 ? "Samenhang controleren aan oorspronkelijke bronnen…" : "AI-analyse: \(current) van \(total)…" }
                        }
                    }
                try Task.checkCancellation()
                insights = result; analyzed = true; neutralAnalysis = false; analysisContext = context; analysisScope = scope; analyzedProgramKey = programKey; analysisProgramName = program.name; refreshProgram()
                analysisModel = model
                analysisState = result.isEmpty ? (citationWarning.isEmpty ? .noMatches : .unconfirmed) : .complete
                analysisInputKey = WorkspaceJob(model: model, context: context, selection: selection, compare: true, targeted: targeted).key(pages: document.pages, program: programKey)
                analysisCompletedPages = selectedPages.enumerated().compactMap { $0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.offset + 1 }
                status = "\(result.count) verbanden met \(program.name) · \(scope) · Beide broncitaten gecontroleerd."

            } catch let partial as ParagraphAnalysisIncomplete {
                if AIConfiguration.isChatGPT(model) &&
                    (Task.isCancelled || documentID != presentationDocumentID || currentAnalysisRunToken != analysisRunToken) { return }
                if let cloudPresentationID {
                    guard documentID == presentationDocumentID,
                          cloudInsightPresentationID == cloudPresentationID else { return }
                    do {
                        guard try await publishCloudInsightPresentation(partial.points, scope: analysisScope, model: model,
                                                                        documentID: presentationDocumentID,
                                                                        presentationID: cloudPresentationID) else { return }
                    } catch {
                        return
                    }
                    analysisModel = model
                    if partial.providerFailure { chatGPTFailed = true; self.error = partial.localizedDescription }
                } else {
                    if partial.providerFailure { chatGPTFailed = true; self.error = partial.localizedDescription }
                    insights = partial.points; analyzed = true; neutralAnalysis = true
                }
                analysisState = .incomplete; analysisIssues = partial.localizedDescription
                status = "Alineasamenvatting onvolledig."
                analysisScope = (try? PageScope.parse(selection, count: document.pages.count)).map { PageScope.label($0, count: document.pages.count) } ?? selection
            } catch let partial as AppleAnalysisIncomplete {
                insights = partial.points; analyzed = true; neutralAnalysis = !compareProgram
                analysisModel = model
                analysisContext = compareProgram ? context : ""
                analysisScope = (try? PageScope.parse(selection, count: document.pages.count)).map { PageScope.label($0, count: document.pages.count) } ?? selection
                if compareProgram, let program = try? currentReference() {
                    analyzedProgramKey = LocalCache.key([program.name, program.criteria ?? ""] + program.pages); analysisProgramName = program.name
                }
                analysisState = .incomplete
                analysisIssues = partial.localizedDescription
                status = "Analyse onvolledig: \(partial.completed) van \(partial.total) stappen verwerkt."
            } catch {
                if let cloudPresentationID,
                   (documentID != presentationDocumentID || cloudInsightPresentationID != cloudPresentationID) { return }
                if AIConfiguration.isChatGPT(model) &&
                    (documentID != presentationDocumentID || currentAnalysisRunToken != analysisRunToken) { return }
                if error is ChatGPTError { chatGPTFailed = true }
                analysisIssues = "Analyse niet afgerond. Resultaten kunnen onvolledig zijn."
                analysisState = Task.isCancelled ? .cancelled : .failed
                status = Task.isCancelled ? "Analyse gestopt." : "Analyse mislukt; eerdere resultaten blijven beschikbaar."
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
    }

    var usesSourceBoundHighlights: Bool { AIConfiguration.isChatGPT(highlightsRetry?.model ?? activeModel) }
    var summaryIsChatGPT: Bool { AIConfiguration.isChatGPT(summaryModel ?? summaryRetry?.model ?? activeModel) }

    @Published private(set) var summaryModel: String?

    private var chatGPTRepairSuffix: String {
        chatGPTRepairCount > 0 ? " · \(chatGPTRepairCount) passages opnieuw aangeboden" : ""
    }

    private func makeSummary(pages: [String], model: String) async {
        await AnalysisMetrics.withPhase("summary", recorder: analysisMeasurement) {
            await makeSummaryMeasured(pages: pages, model: model)
        }
    }

    private func makeSummaryMeasured(pages: [String], model: String) async {
        analysisPhase = .summary
        let phaseDocumentID = documentID
        let phaseSwitchToken = chatGPTModelSwitchToken
        progress.next()
        summaryRetry = (pages, model)
        summaryInputKey = nil; activeModel = model; activeScope = summaryScope
        summaryError = nil
        do {
            let result = try await summarizeDocument(pages, model) { current, total in
                await MainActor.run {
                    if AIConfiguration.isChatGPT(model) &&
                        (Task.isCancelled || self.documentID != phaseDocumentID || self.chatGPTModelSwitchToken != phaseSwitchToken) { return }
                    if AIConfiguration.isChatGPT(model), current < 0 {
                        self.progress.updateSummaryMerge(completed: -current - 1, total: total)
                    } else {
                        self.progress.update(completed: AIConfiguration.isChatGPT(model) ? current : (current == 0 ? total : max(0, current - 1)), total: total)
                    }
                    if AIConfiguration.isChatGPT(model) {
                        let merging = self.progress.isMergingSummary
                        let role: AIConfiguration.ChatGPTRole = merging ? .orchestrator : .worker
                        let phase = merging ? "Documentsamenvatting samenvoegen: \(self.progress.mergeCompleted) van \(self.progress.phaseTotal)…" : "Document samenvatten: \(current) van \(total)…"
                        self.status = phase + AIConfiguration.phaseModelLabel(model, role: role)
                    } else { self.status = current == 0 ? "Hoofdpunten samenvoegen tot documentsamenvatting…" : "Document samenvatten: \(current) van \(total)…" }
                }
            }
            try Task.checkCancellation()
            if AIConfiguration.isChatGPT(model),
               (documentID != phaseDocumentID || chatGPTModelSwitchToken != phaseSwitchToken) { return }
            documentSummary = result
            summaryModel = model
            if result.incompleteNotice == nil { summaryInputKey = LocalCache.key(pages + [model]) }
            summaryError = documentSummary?.incompleteNotice
            status = summaryError == nil ? "Documentsamenvatting gereed." : "Documentsamenvatting onvolledig."
        } catch {
            if AIConfiguration.isChatGPT(model),
               (documentID != phaseDocumentID || chatGPTModelSwitchToken != phaseSwitchToken) { return }
            if error is ChatGPTError { chatGPTFailed = true }
            if !Task.isCancelled { self.error = error.localizedDescription }
            summaryError = Task.isCancelled ? "Samenvatting gestopt. Je kunt later hervatten." : error.localizedDescription
            status = "PDF ingeladen; samenvatting niet afgerond."
        }
    }
    func summarize(model: String, selection: String = "") {
        guard canStartAnalysis, let document else { return }
        do {
            let selected = try PageScope.parse(selection, count: document.pages.count)
            let pages = PageScope.mask(document.pages, selected: selected)
            guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AppError(message: "De gekozen pagina’s bevatten geen leesbare tekst.") }
            let previousSummaryPages = summaryPages
            if !AIConfiguration.isChatGPT(model) || previousSummaryPages != selected {
                documentSummary = nil
                summaryModel = nil
            }
            summaryPages = selected
            summaryScope = PageScope.label(selected, count: document.pages.count)
            markDirty()
            canSwitchCurrentAnalysisWorkflow = false
            busy = true; progress.begin(phases: 1, chatGPT: AIConfiguration.isChatGPT(model))
            beginMeasurement(model: model, operation: "summary")
            task = Task {
                defer { analysisPhase = nil; finishProcessing() }
                await makeSummary(pages: pages, model: model)
            }
        } catch { self.error = error.localizedDescription }
    }

    func applyFocus(_ focus: AnalysisFocus) {
        guard canStartAnalysis, let current = document else { return }
        guard self.focus != focus.prompt else { return }
        markDirty()
        self.focus = focus.prompt
        localFocus = focus.prompt
        document = OpenPDF(name: current.name, data: current.data, pages: current.pages, findings: [],
                           readings: current.readings, extractedTables: current.extractedTables,
                           pageExtractionCache: current.pageExtractionCache)
        if !analyzed { status = "Leesdoel toegepast. Start een nieuwe analyse om het te gebruiken." }
    }

    func refreshProgram() {
        do {
            let program = try currentReference()
            programName = program?.name ?? "Geen referentiedocument — voeg dit toe via Instellingen"
            let key = program.map { LocalCache.key([$0.name, $0.criteria ?? ""] + $0.pages) }
            programIdentity = key ?? "none"
            if archivedReference == nil { observedReferenceSettings = programIdentity }
            programChanged = analyzed && !neutralAnalysis && key != analyzedProgramKey
        } catch { self.error = error.localizedDescription }
    }

    func cancelAnalysis() { task?.cancel(); progress.resetChatGPTEstimateForCancellation(); if !analyzed { analysisState = .cancelled } }
    func showPage(_ number: Int) { page = number; navigationID = UUID() }

    var exportContext: String {
        (analysisIssues.isEmpty ? "" : analysisIssues + "\n") + (neutralAnalysis ? "Neutrale samenvatting · \(analysisScope)" : analyzed ? "\(analysisScope)\nReferentiedocument: \(analysisProgramName)\nAanvullende focus: \(analysisContext)" : localFocus)
    }

    var layoutNotice: String {
        guard let document else { return "" }
        let skipped = document.readings.enumerated().filter { !$0.element.notice.isEmpty && $0.element.text.isEmpty }.map { String($0.offset + 1) }
        let regionNotice = "Alleen het handmatig aangewezen tekstgebied is meegenomen."
        let limited = document.readings.enumerated().filter { !$0.element.text.isEmpty && $0.element.notice.contains(regionNotice) }.map { String($0.offset + 1) }
        let ocrNotice = "Afbeeldingstabel met OCR gelezen."
        let ocrPages = document.readings.enumerated().filter { $0.element.notice.contains(ocrNotice) }.map { String($0.offset + 1) }
        return [
            skipped.isEmpty ? "" : "Niet betrouwbaar gelezen; pagina’s overgeslagen: " + skipped.joined(separator: ", "),
            limited.isEmpty ? "" : "Alleen geselecteerd tekstgebied verwerkt op pagina: " + limited.joined(separator: ", "),
            ocrPages.isEmpty ? "" : "Afbeeldingstabellen met OCR gelezen; deze zijn niet in de AI-analyse opgenomen op pagina: " + ocrPages.joined(separator: ", ")
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    func correctLayout(page: Int, override: LayoutOverride) async throws {
        guard canStartAnalysis, tableAnalysisID == nil, let old = document else { throw AppError(message: "Wacht tot de analyse klaar of gestopt is.") }
        let expectedDocumentID = documentID
        busy = true; defer { busy = false }
        let data = old.data
        let sourceFingerprint = LayoutStore.fingerprint(data)
        var overrides = try LayoutStore.read(fingerprint: sourceFingerprint)
        overrides[page] = override.columns == 0 && override.region == nil ? nil : override
        let oldPageCache = old.pageExtractionCache
        let extraction = Task.detached {
            try Task.checkCancellation()
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw AppError(message: "PDF niet leesbaar.") }
            return try PageLayout.extract(pdf: pdf, overrides: overrides, includeTables: true,
                                          sourceFingerprint: sourceFingerprint, reusing: oldPageCache)
        }
        let layout = try await withTaskCancellationHandler {
            try await extraction.value
        } onCancel: {
            extraction.cancel()
        }
        try Task.checkCancellation()
        guard documentID == expectedDocumentID else { throw CancellationError() }
        try LayoutStore.save(overrides, fingerprint: sourceFingerprint)
        document = OpenPDF(name: old.name, data: data, pages: layout.pages, findings: [], readings: layout.readings,
                           extractedTables: layout.tables, pageExtractionCache: layout.extractionCache)
        tables = layout.tables
        // No obsolete result may remain visible or exportable after a reading-order change.
        insights = []; keyPoints = []; documentSummary = nil
        committeePresentationCache.clear()
        committeeReviews = [:]
        committeeReviewStatus = ""; committeeReviewError = nil
        committeeReviewCompleted = 0; committeeReviewTotal = 0
        keyPointsReady = false; analyzed = false; analysisState = .notStarted
        analysisIssues = "Tekstindeling gewijzigd. Eerdere resultaten zijn verwijderd; start de analyse opnieuw."
        documentChat.reset(); pageChat.reset(); summaryRetry = nil; retryParameters = nil
        summaryError = nil; summaryScope = "Hele document"; analysisScope = "Hele document"
        analysisContext = ""; neutralAnalysis = false; analysisProgramName = ""; analyzedProgramKey = nil; programChanged = false
        citationWarning = ""; keyPointIssues = ""
        let isSnapshot = selectionDocumentKey.hasPrefix("snapshot-")
        selectionDocumentKey = isSnapshot ? selectionDocumentKey : LocalCache.key(layout.pages)
        if !isSnapshot {
            persistChosenPassages()
            passageQuestions = SavedWork.read([String: [PassageQuestion]].self, key: "questions-" + selectionDocumentKey) ?? [:]
            starred = SavedSelection.read(documentKey: selectionDocumentKey)
            selectionMetadata = SavedWork.read(SavedSelectionMetadata.self, key: "selection-metadata-" + selectionDocumentKey) ?? .init()
            normalizeSelectionMetadata()
        }
        markDirty()
        summaryInputKey = nil; highlightsInputKey = nil; analysisInputKey = nil; analysisCompletedPages = nil; highlightsRetry = nil; highlightModel = nil; lastJob = nil
        summaryPages = Array(1...layout.pages.count)
        if !isSnapshot {
            annotations = SavedWork.read([String: PointAnnotation].self, key: "annotations-" + selectionDocumentKey) ?? [:]
        }
        documentID = UUID(); chatGPTModelSwitchToken = UUID(); analysisPhase = nil; analysisModel = nil; isSwitchingChatGPTModel = false
        status = "Indeling opgeslagen. Start de analyse opnieuw."
    }

    var exportNotice: String {
        let cancelled = analysisState == .cancelled ? "De analyse is gestopt voordat alle onderdelen waren verwerkt." : ""
        return [cancelled, completionDetails].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var documentCoverage: DocumentCoverage {
        DocumentCoverage.make(pages: document?.pages ?? [], completedAnalysisPages: analysisCompletedPages,
                              analysisState: analysisState, tables: tables)
    }

    nonisolated static func exportDirectory(configuredPath: String, fileManager: FileManager = .default) -> URL? {
        guard !configuredPath.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: configuredPath, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: configuredPath, isDirectory: true)
    }

    private var exportContentCache: [String: ScopedExportContent] = [:]
    private var exportContentRevision = ""
    func exportContent(for configuration: ExportConfiguration, glossary: [ExportGlossaryItem] = []) -> ScopedExportContent {
        let revision = documentID.uuidString + revisionToken.uuidString
        if exportContentRevision != revision { exportContentCache = [:]; exportContentRevision = revision }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let key = LocalCache.key([(try? encoder.encode(configuration)).map { String(decoding: $0, as: UTF8.self) } ?? ""] + glossary.flatMap { [$0.term, $0.meaning, $0.origin] })
        if let cached = exportContentCache[key] { return cached }
        let content = ScopedExportContent.make(configuration: configuration, pages: document?.pages ?? [], insights: exportInsights,
            review: configuration.committeePurpose.flatMap { committeeReviews[$0.rawValue] },
            summary: documentSummary, summaryScope: summaryScope, tables: tables, chosenPassages: chosenPassages,
            glossary: glossary, notice: exportNotice, context: exportContext, neutralAnalysis: neutralAnalysis)
        if exportContentCache.count >= 8 { exportContentCache = [:] }
        exportContentCache[key] = content
        return content
    }

    func export(configuration: ExportConfiguration, title: String, fileName: String, glossary: [ExportGlossaryItem]) {
        guard canStartAnalysis, let document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName
        let folder = UserDefaults.standard.string(forKey: "exportFolder") ?? ""
        let directory = Self.exportDirectory(configuredPath: folder)
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Capture a consistent workspace snapshot before starting asynchronous file I/O.
        let material = exportContent(for: configuration, glossary: glossary)
        let snapshotDocument = document
        let snapshotInsights = material.insights
        let snapshotAnalyzed = analyzed
        let snapshotFocus = material.context
        let snapshotNeutral = material.neutralAnalysis
        let snapshotSummary = material.summary
        let snapshotSummaryScope = material.summaryScope
        let snapshotNotice = material.notice
        let snapshotSelection = Set(snapshotInsights.filter { isStarred($0) }.map(Self.selectionKey))
        let snapshotSelectionOrder = selectedInsightsInOrder.map(Self.selectionKey)
        let snapshotSelectionStatuses = selectionMetadata.statuses
        let snapshotTables = material.tables
        let snapshotReadings = document.readings
        let snapshotAnnotations = exportAnnotations
        let snapshotChosenPassages = material.chosenPassages
        let snapshotID = documentID
        exporting = true
        exportWriting = false
        status = "PDF exporteren…"
        exportTask = Task { @MainActor in
            do {
                // Rendering owns its CoreText context and PDF objects on a background task.
                let data = try await BriefingPDF.render(document: snapshotDocument, insights: snapshotInsights, analyzed: snapshotAnalyzed,
                                                focus: snapshotFocus, neutral: snapshotNeutral, summary: snapshotSummary,
                                                summaryScope: snapshotSummaryScope, includeSources: configuration.sources,
                                                notice: snapshotNotice, configuration: configuration, title: title,
                                                selectedIDs: snapshotSelection, selectedOrder: snapshotSelectionOrder, selectionStatuses: snapshotSelectionStatuses, glossary: material.glossary, tables: snapshotTables,
                                                readings: snapshotReadings, annotations: snapshotAnnotations,
                                                chosenPassages: snapshotChosenPassages, committeeLabels: material.committeeLabels)
                // The atomic write is the commit point. Cancellation remains available
                // during rendering, but cannot interrupt a write that has already begun.
                try Task.checkCancellation()
                self.exportWriting = true
                self.status = "PDF opslaan…"
                try await Task.detached(priority: .utility) { try data.write(to: url, options: .atomic) }.value
                if self.documentID == snapshotID { self.status = "PDF opgeslagen: \(url.lastPathComponent)" }
            } catch is CancellationError {
                if self.documentID == snapshotID { self.status = "PDF-export geannuleerd." }
            } catch {
                self.error = error.localizedDescription
            }
            self.exportWriting = false
            self.exporting = false
            self.exportTask = nil
        }
    }
    func saveReviewedTable(_ reviewed: DocumentTable) {
        guard canStartAnalysis, tableAnalysisID == nil, let index = tables.firstIndex(where: { $0.id == reviewed.id }) else { return }
        guard reviewed.recognizedWithOCR == true else { return }
        tables[index] = reviewed
        markDirty()
        status = reviewed.isOCRConfirmed ? "Tabel aan de bron gecontroleerd. Tabelanalyse is beschikbaar." : "Tabelcorrecties bewaard; controleer de resterende cellen."
    }
    func analyzeReviewedTable(id: String, model: String) {
        guard canStartAnalysis, tableAnalysisID == nil,
              let snapshot = tables.first(where: { $0.id == id }), snapshot.isOCRConfirmed,
              OCRTableValidation.report(snapshot).canConfirm else { return }
        let docID = documentID
        markDirty()
        tableAnalysisID = id; tableAnalysisError = nil
        tableAnalysisTask = Task {
            defer { if documentID == docID { tableAnalysisID = nil } }
            do {
                let result = try await analyzeTableCells(snapshot, model, nil)
                try Task.checkCancellation()
                guard documentID == docID, let index = tables.firstIndex(where: { $0.id == id }),
                      tables[index].isOCRConfirmed, tables[index].reviewSignature == snapshot.reviewSignature else { return }
                var review = tables[index].ocrReview ?? OCRTableReview()
                review.summary = result; review.summaryModel = model
                tables[index].ocrReview = review
                markDirty()
                status = "Gecontroleerde tabelgegevens toegevoegd aan Overzicht."
            } catch is CancellationError {
                if documentID == docID { status = "Tabelanalyse gestopt." }
            } catch { if documentID == docID { tableAnalysisError = error.localizedDescription } }
        }
    }
    func stopTableAnalysis() { tableAnalysisTask?.cancel() }

    func archive(readingPage: Int, viewState: WorkspaceViewState? = nil, allowingTerminationAutosave: Bool = false) throws -> WorkspaceArchive {
        let admission = canStartAnalysis || (allowingTerminationAutosave && terminationAutosaveInProgress &&
            !busy && !committeeReviewBusy && !isSwitchingChatGPTModel)
        guard admission, tableAnalysisID == nil, let document else { throw AppError(message: "Stop of voltooi de huidige verwerking voordat je het werkdocument bewaart.") }
        let latestReviewKeys = Set(committeeReviews.values.map(Self.committeeReviewKey))
        var reviews = committeeReviewHistory.values.filter { !latestReviewKeys.contains(Self.committeeReviewKey($0)) }
            .sorted { Self.committeeReviewKey($0) < Self.committeeReviewKey($1) }
        reviews.append(contentsOf: committeeReviews.values.sorted { $0.purpose.rawValue < $1.purpose.rawValue })
        var saved = WorkspaceArchive(name: document.name, pdf: document.data, pages: document.pages, readings: document.readings, tables: tables,
            summary: documentSummary, summaryScope: summaryScope, summaryPages: summaryPages,
            highlights: keyPoints, highlightScope: highlightScope, highlightsReady: keyPointsReady,
            insights: insights, analyzed: analyzed, neutral: neutralAnalysis, analysisScope: analysisScope, analysisContext: analysisContext,
            state: analysisState, summaryError: summaryError, analysisIssues: analysisIssues, highlightIssues: keyPointIssues,
            citationWarning: citationWarning, starred: starred, annotations: annotations, questions: passageQuestions,
            page: readingPage, model: activeModel, focus: focus, job: lastJob, programName: analysisProgramName,
            programKey: analyzedProgramKey, summaryModel: summaryModel, highlightModel: highlightModel,
            analysisModel: analysisModel, summaryRetryModel: summaryRetry?.model, highlightRetryModel: highlightsRetry?.model,
            highlightPages: highlightsRetry?.pages.enumerated().compactMap { $0.element.isEmpty ? nil : $0.offset + 1 } ?? [], summaryKey: summaryInputKey, highlightsKey: highlightsInputKey, analysisKey: analysisInputKey,
            selectionMetadata: selectionMetadata, viewState: viewState, analysisCompletedPages: analysisCompletedPages,
            chosenPassages: chosenPassages, meetingPurpose: meetingPurpose, committeeReviews: reviews,
            savedChatThreads: savedChatThreads, savedChartAnalyses: savedChartAnalyses, savedSelectionSummaries: savedSelectionSummaries)
        saved.referenceDocument = archivedReference ?? (try? loadProgram())
        saved.analysisLanguage = AnalysisLanguage.code
        return saved
    }
    func restore(_ saved: WorkspaceArchive, persist: Bool = true) throws {
        try restore(saved, persist: persist, prevalidated: false)
    }
    private func restore(_ saved: WorkspaceArchive, persist: Bool, prevalidated: Bool) throws {
        guard canStartAnalysis else { throw AppError(message: "Wacht tot de huidige verwerking klaar is.") }
        if !prevalidated { try saved.validate() }
        releaseOpenedWorkdocumentAccess()
        observedReferenceSettings = (try? loadProgram()).map { LocalCache.key([$0.name, $0.criteria ?? ""] + $0.pages) } ?? "none"
        archivedReference = saved.referenceDocument
        tableAnalysisTask?.cancel(); tableAnalysisID = nil; tableAnalysisError = nil
        documentChat.reset(); pageChat.reset()
        document = OpenPDF(name: saved.name, data: saved.pdf, pages: saved.pages, findings: [], readings: saved.readings, extractedTables: saved.tables)
        documentSummary = saved.summary; summaryScope = saved.summaryScope; summaryPages = saved.summaryPages
        keyPoints = saved.highlights; highlightScope = saved.highlightScope; keyPointsReady = saved.highlightsReady
        tables = saved.tables; insights = saved.insights; analyzed = saved.analyzed; neutralAnalysis = saved.neutral
        analysisScope = saved.analysisScope; analysisContext = saved.analysisContext
        analysisState = saved.state == .running ? .incomplete : saved.state
        summaryError = saved.summaryError; analysisIssues = saved.analysisIssues; keyPointIssues = saved.highlightIssues; citationWarning = saved.citationWarning
        selectionDocumentKey = "snapshot-" + (saved.snapshotID ?? UUID()).uuidString
        starred = saved.starred; annotations = saved.annotations; passageQuestions = saved.questions
        chosenPassages = saved.chosenPassages ?? []
        savedChatThreads = (saved.savedChatThreads ?? []).filter { SavedChatThread.validate($0, pageCount: saved.pages.count) }
        savedChartAnalyses = (saved.savedChartAnalyses ?? []).filter { SavedChartAnalysis.validate($0, pageCount: saved.pages.count) }
        savedSelectionSummaries = (saved.savedSelectionSummaries ?? []).filter { SavedSelectionSummary.validate($0, pageCount: saved.pages.count) }
        selectionMetadata = saved.selectionMetadata ?? .init()
        normalizeSelectionMetadata()
        meetingPurpose = saved.meetingPurpose ?? .raad
        let restoredCommitteeReviews = prevalidated
            ? (saved.committeeReviews ?? [])
            : WorkspaceArchive.validCommitteeReviews(saved.committeeReviews ?? [], pages: saved.pages)
        publishCommitteeReviewHistory(restoredCommitteeReviews)
        committeeReviewError = nil
        let restoredSelectedReview = committeeReviews[meetingPurpose.rawValue]
        committeeReviewStatus = restoredSelectedReview.map { _ in "Bewaarde profielbeoordeling beschikbaar." } ?? ""
        committeeReviewCompleted = restoredSelectedReview?.entries.filter { $0.rating != .unassessed }.count ?? 0
        committeeReviewTotal = restoredSelectedReview?.entries.count ?? 0
        restoredViewState = saved.viewState
        requestedSelection = saved.job?.selection ?? ""
        activeModel = saved.model; activeScope = saved.analysisScope; focus = saved.focus; localFocus = saved.focus; lastJob = saved.job
        analysisProgramName = saved.programName; analyzedProgramKey = saved.programKey
        summaryInputKey = saved.summaryKey; highlightsInputKey = saved.highlightsKey; analysisInputKey = saved.analysisKey
        analysisCompletedPages = saved.analysisCompletedPages
        summaryModel = saved.summaryModel
        highlightModel = saved.highlightModel
        analysisModel = saved.analysisModel
        summaryRetry = (saved.summaryRetryModel ?? saved.summaryModel).map { (PageScope.mask(saved.pages, selected: saved.summaryPages), $0) }
        highlightsRetry = (saved.highlightRetryModel ?? saved.highlightModel).map { (PageScope.mask(saved.pages, selected: saved.highlightPages), $0, saved.highlightScope) }
        if let job = saved.job {
            _ = try PageScope.parse(job.selection, count: saved.pages.count)
            retryParameters = (job.model, job.context, job.selection, job.compare, job.targeted)
        } else { retryParameters = nil }
        page = min(max(1, saved.page), saved.pages.count); navigationID = UUID(); documentID = UUID()
        terminationReadingPage = page; terminationViewState = saved.viewState
        chatGPTModelSwitchToken = UUID(); analysisPhase = nil; isSwitchingChatGPTModel = false
        processingName = saved.name; canSwitchCurrentAnalysisWorkflow = false
        error = nil; chatGPTFailed = false; processingPresented = false; processingMessage = nil; showsWelcome = false
        status = "Werkdocument hersteld. Bewaarde resultaten zijn beschikbaar."
        refreshProgram()
        markRestoredClean()
        guard persist else { return }
        SavedWork.schedule(saved.questions, key: "questions-" + selectionDocumentKey)
        SavedWork.schedule(saved.annotations, key: "annotations-" + selectionDocumentKey)
        persistChosenPassages()
        persistSelectionMetadata()
        do { try SavedSelection.write(saved.starred, documentKey: selectionDocumentKey) }
        catch { self.error = "Werkdocument geopend; selectie kon niet lokaal worden bewaard: " + error.localizedDescription }
    }

    func normalizeSelectionMetadata() {
        let current = Set(starred)
        var seen = Set<String>()
        var order = selectionMetadata.order.filter { current.contains($0) && seen.insert($0).inserted }
        let visibleSelected = exportInsights.filter(isStarred).map(Self.selectionKey)
        for key in visibleSelected + current.sorted() where seen.insert(key).inserted { order.append(key) }
        selectionMetadata.order = order
        selectionMetadata.statuses = selectionMetadata.statuses.filter { current.contains($0.key) }
        for key in current where selectionMetadata.statuses[key] == nil { selectionMetadata.statuses[key] = .discuss }
    }
    @Published private(set) var savedChatThreads: [SavedChatThread] = []
    @Published private(set) var savedSelectionSummaries: [SavedSelectionSummary] = []
    func rememberSelectionSummary(_ saved: SavedSelectionSummary, expectedDocumentID: UUID) {
        guard documentID == expectedDocumentID, !saved.summary.isEmpty else { return }
        savedSelectionSummaries.append(saved)
        markDirty()
    }
    @Published private(set) var savedChartAnalyses: [SavedChartAnalysis] = []
    func chatStorageKey(_ key: String) -> String {
        selectionDocumentKey.hasPrefix("snapshot-") ? selectionDocumentKey + "-" + key : key
    }
    func rememberChat(_ thread: SavedChatThread, expectedDocumentID: UUID) {
        guard documentID == expectedDocumentID, !thread.messages.isEmpty else { return }
        guard savedChatThreads.first(where: { $0.id == thread.id }) != thread else { return }
        savedChatThreads.removeAll { $0.id == thread.id }
        savedChatThreads.append(thread)
        markDirty()
    }
    func rememberChart(_ selected: SelectedChart, explanation: ChartExplanation, expectedDocumentID: UUID) {
        guard documentID == expectedDocumentID else { return }
        do {
            let record = try SavedChartAnalysis.make(selected: selected, explanation: explanation)
            savedChartAnalyses.append(record)
            markDirty()
        } catch { self.error = "De diagramuitleg kon niet in het werkdocument worden opgenomen: " + error.localizedDescription }
    }

    private func recordRecentWorkspace(_ url: URL) {
        // A history failure must never invalidate a successfully saved/restored document.
        try? RecentWorkspaceDocuments.shared.record(url)
    }
    func openRecentWorkspace(_ entry: RecentWorkspaceDocuments.Entry) {
        guard canStartAnalysis else { return }
        do { openWorkspace(at: try RecentWorkspaceDocuments.shared.resolve(entry)) }
        catch { self.error = error.localizedDescription }
    }
    func relocateRecentWorkspace(_ entry: RecentWorkspaceDocuments.Entry) {
        guard canStartAnalysis else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(exportedAs: "app.foliance.mac.work", conformingTo: .data)]
        panel.message = "Choose the work document at its new location."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(at: url, replacingRecent: entry)
    }
    func saveWorkspace(readingPage: Int, viewState: WorkspaceViewState? = nil, completion: ((Bool) -> Void)? = nil) {
        guard canStartAnalysis, let document else { completion?(false); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(exportedAs: "app.foliance.mac.work", conformingTo: .data)]
        panel.nameFieldStringValue = (document.name as NSString).deletingPathExtension + ".foliance"
        panel.message = "Saves the source PDF, results, selection, notes and reading position in one local work document."
        guard panel.runModal() == .OK, let url = panel.url else { completion?(false); return }
        writeWorkspaceArchive(to: url, readingPage: readingPage, viewState: viewState, completion: completion)
    }

    private func writeWorkspaceArchive(to url: URL, readingPage: Int, viewState: WorkspaceViewState?, completion: ((Bool) -> Void)?) {
        do {
            terminationReadingPage = readingPage
            terminationViewState = viewState
            let snapshot = try archive(readingPage: readingPage, viewState: viewState)
            let capturedRevision = revisionToken
            let capturedDocumentID = documentID
            let retainDestinationAsOpenedWorkdocument = openedWorkdocumentURL != nil
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            let writer = workspaceArchiveWriter
            exporting = true; status = "Werkdocument bewaren…"
            Task {
                do {
                    try await Task.detached(priority: .utility) { try writer(snapshot, url) }.value
                    if documentID == capturedDocumentID { markSaved(capturedRevision) }
                    if retainDestinationAsOpenedWorkdocument, documentID == capturedDocumentID {
                        adoptAccess(to: url, alreadyStarted: hasScopedAccess)
                    } else if hasScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                    exporting = false
                    status = "Werkdocument bewaard: " + url.lastPathComponent
                    recordRecentWorkspace(url)
                    completion?(documentID == capturedDocumentID)
                }
                catch {
                    if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
                    exporting = false; self.error = error.localizedDescription; completion?(false)
                }
            }
        } catch { self.error = error.localizedDescription; completion?(false) }
    }

    func saveWorkspace(to url: URL, readingPage: Int, viewState: WorkspaceViewState? = nil, completion: ((Bool) -> Void)? = nil) {
        guard canStartAnalysis, let document else { completion?(false); return }
        writeWorkspaceArchive(to: url, readingPage: readingPage, viewState: viewState, completion: completion)
    }
    func openWorkspace() {
        guard canStartAnalysis else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(exportedAs: "app.foliance.mac.work", conformingTo: .data)]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspace(at: url)
    }
    func openWorkspace(at url: URL, replacingRecent: RecentWorkspaceDocuments.Entry? = nil) {
        guard canStartAnalysis else { return }
        let acquiredAccess = url.startAccessingSecurityScopedResource()
        exporting = true; status = "Werkdocument openen…"
        Task {
            do {
                let saved = try await Task.detached(priority: .userInitiated) { try WorkspaceArchive.read(url) }.value
                exporting = false
                try restore(saved, persist: true, prevalidated: true)
                adoptAccess(to: url, alreadyStarted: acquiredAccess)
                if let replacingRecent { try? RecentWorkspaceDocuments.shared.replace(replacingRecent, with: url) }
                else { recordRecentWorkspace(url) }
            } catch {
                if acquiredAccess { url.stopAccessingSecurityScopedResource() }
                exporting = false; self.error = error.localizedDescription
            }
        }
    }

}


enum AnalysisState: String, Codable {
    case notStarted = "Nog niet geanalyseerd"
    case running = "Analyse bezig…"
    case needsProgram = "Voeg een referentiedocument toe via Instellingen om de analyse te starten."
    case noSummaryPoints = "Geen samenvattingspunten met bevestigde broncitaten gevonden."
    case noMatches = "Analyse afgerond: geen onderbouwde verbanden gevonden."
    case unconfirmed = "Analyse afgerond: gevonden verbanden konden niet met broncitaten worden bevestigd."
    case complete = "Analyse gereed"
    case incomplete = "Analyse gedeeltelijk afgerond; ontbrekende stappen opnieuw proberen."
    case failed = "Analyse mislukt; probeer opnieuw."
    case cancelled = "Analyse gestopt; je kunt opnieuw analyseren."
}
