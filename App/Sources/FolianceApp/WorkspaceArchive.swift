import Foundation
import PDFKit

struct PointAnnotation: Codable, Sendable, Equatable {
    var note = ""
    var checkedSignature: String?
    static func signature(_ point: Insight) -> String {
        var components = [point.title, point.summary, point.relevance, point.quote, point.programSource ?? ""] + (point.otherSources ?? []).map { "\($0.page):\($0.quote)" }
        // Keep existing checkmarks valid for legacy records, but invalidate them when
        // a new passage's classification, context or source scope changes.
        if point.passageID != nil || point.relevanceClass != nil || point.contextSources != nil || point.passageSources != nil {
            components += ["passage-v1", point.passageID ?? "", point.relevanceClass ?? "", point.relevanceReason ?? "", String(point.passagePartIndex ?? 0), String(point.passagePartCount ?? 0)]
            components += (point.contextSources ?? []).map { "context:\($0.page):\($0.quote)" }
            components += (point.passageSources ?? []).map { "passage:\($0.page):\($0.quote)" }
        }
        return LocalCache.key(components)
    }
    func isChecked(_ point: Insight) -> Bool { checkedSignature == Self.signature(point) }
}

struct WorkspaceJob: Codable, Sendable {
    let model: String
    let context: String
    let selection: String
    let compare: Bool
    let targeted: Bool
    func key(pages: [String], program: String) -> String {
        let selected = (try? PageScope.parse(selection, count: pages.count)) ?? []
        return LocalCache.key(PageScope.mask(pages, selected: selected) + ["paragraph-analysis-v1", model, context, compare ? program : "neutral", String(targeted)])
    }
}

/// Explicit local snapshot; includes the original PDF so moved source files do not break restoration.
struct WorkspaceArchive: Codable, Sendable {
    var formatVersion = 1
    var referenceDocument: PartyProgram? = nil
    var analysisLanguage: String? = nil
    var snapshotID: UUID? = UUID()
    let name: String
    let pdf: Data
    let pages: [String]
    let readings: [PageReading]
    let tables: [DocumentTable]
    let summary: DocumentSummary?
    let summaryScope: String
    let summaryPages: [Int]
    let highlights: [SourceHighlights.Item]
    let highlightScope: String
    let highlightsReady: Bool
    let insights: [Insight]
    let analyzed: Bool
    let neutral: Bool
    let analysisScope: String
    let analysisContext: String
    let state: AnalysisState
    let summaryError: String?
    let analysisIssues: String
    let highlightIssues: String
    let citationWarning: String
    let starred: Set<String>
    let annotations: [String: PointAnnotation]
    let questions: [String: [PassageQuestion]]
    let page: Int
    let model: String
    let focus: String
    let job: WorkspaceJob?
    let programName: String
    let programKey: String?
    let summaryModel: String?
    let highlightModel: String?
    var analysisModel: String? = nil
    var summaryRetryModel: String? = nil
    var highlightRetryModel: String? = nil
    let highlightPages: [Int]
    let summaryKey: String?
    let highlightsKey: String?
    let analysisKey: String?
    var selectionMetadata: SavedSelectionMetadata? = nil
    var viewState: WorkspaceViewState? = nil
    var analysisCompletedPages: [Int]? = nil
    var chosenPassages: [ChosenPassage]? = nil
    var meetingPurpose: MeetingPurpose? = nil
    var committeeReviews: [CommitteeAssessmentService.Review]? = nil
    var savedChatThreads: [SavedChatThread]? = nil
    var savedChartAnalyses: [SavedChartAnalysis]? = nil
    var savedSelectionSummaries: [SavedSelectionSummary]? = nil

    func validate() throws {
        guard referenceDocument.map({ !$0.pages.isEmpty && $0.pdf.count <= 100_000_000 && ($0.criteria?.utf8.count ?? 0) <= 8_000 }) ?? true else {
            throw AppError(message: "The saved reference document is invalid.")
        }
        guard formatVersion == 1, !pages.isEmpty, pdf.count <= 100_000_000,
              let document = PDFDocument(data: pdf), !document.isLocked,
              document.pageCount == pages.count,
              readings.isEmpty || readings.count == pages.count,
              analysisCompletedPages?.allSatisfy({ $0 > 0 && $0 <= pages.count }) ?? true,
              summaryPages.allSatisfy({ $0 > 0 && $0 <= pages.count }),
              highlightPages.allSatisfy({ $0 > 0 && $0 <= pages.count }),
              insights.allSatisfy({ Self.validInsight($0, pageCount: pages.count) }),
              Self.validChosenPassages(chosenPassages ?? [], pageCount: pages.count),
              highlights.allSatisfy({ Self.validHighlight($0, pageCount: pages.count) }),
              tables.allSatisfy({ table in
                  let rectangular = table.rows.allSatisfy { $0.count == table.headers.count }
                  let diagnosticRaggedTextTable = table.recognizedWithOCR != true && !table.reliable
                  return !table.pages.isEmpty && table.pages.allSatisfy { $0 > 0 && $0 <= pages.count } &&
                      (rectangular || diagnosticRaggedTextTable) &&
                      (table.recognizedWithOCR != true || (!table.headers.isEmpty && !table.rows.isEmpty))
              }) else {
            throw AppError(message: "This work document is invalid or uses an unsupported version.")
        }
        if let job { _ = try PageScope.parse(job.selection, count: pages.count) }
        // Commission reviews are optional derived records. Their current input
        // keys can become stale across OS or prompt-version changes, so they do
        // not invalidate the underlying workdocument; restore filters bad sources.
    }
    static func validCommitteeReviews(_ reviews: [CommitteeAssessmentService.Review], pages: [String]) -> [CommitteeAssessmentService.Review] {
        let passages = PassageEngine.passages(pages)
        return reviews.filter { review in
            guard !review.inputKey.isEmpty else { return false }
            if review.purpose == .raad { return review.entries.isEmpty && review.complete }
            guard review.entries.count == passages.count else { return false }
            for (passage, assessment) in zip(passages, review.entries) {
                guard assessment.passageID == passage.id, !assessment.model.isEmpty,
                      assessment.contextSources?.isEmpty != false || AIConfiguration.isChatGPT(assessment.model),
                      CommitteeSourceContext.valid(sources: assessment.contextSources, pages: pages),
                      assessment.sources.count == passage.sources.count,
                      zip(assessment.sources, passage.sources).allSatisfy({ pair in
                          pair.0.page == pair.1.page && Data(pair.0.quote.utf8) == Data(pair.1.quote.utf8)
                      }) else { return false }
                if assessment.rating != .unassessed {
                    guard assessment.failureCode == nil,
                          !assessment.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !assessment.evidenceQuote.isEmpty, Data(passage.text.utf8).range(of: Data(assessment.evidenceQuote.utf8)) != nil else { return false }
                }
            }
            return !review.complete || (review.issues.isEmpty && review.entries.allSatisfy { $0.rating != .unassessed })
        }
    }
    static func validHighlight(_ item: SourceHighlights.Item, pageCount: Int) -> Bool {
        // Older archives had no paragraph metadata; retain their compatibility.
        guard let sources = item.passageSources else { return item.passageID == nil }
        guard let id = item.passageID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sources.isEmpty, sources.first?.page == item.page,
              sources.allSatisfy({ $0.page > 0 && $0.page <= pageCount && !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              sources.map(\.page) == sources.map(\.page).sorted(),
              sources.map(\.quote).joined(separator: "\n").utf8.elementsEqual(item.quote.utf8) else { return false }
        return true
    }

    static func validInsight(_ point: Insight, pageCount: Int) -> Bool {
        guard point.page > 0, point.page <= pageCount else { return false }
        // New source metadata is optional; old workdocuments remain readable.
        for sources in [point.contextSources, point.passageSources] {
            if let sources, !sources.allSatisfy({ $0.page > 0 && $0.page <= pageCount && !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return false }
        }
        if let category = point.relevanceClass, !["main", "background", "uncertain"].contains(category) { return false }
        if let id = point.passageID, id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        switch (point.passagePartIndex, point.passagePartCount) {
        case (nil, nil): break
        case let (.some(index), .some(count)):
            guard index >= 1, count >= index, point.passageID != nil else { return false }
        default: return false
        }
        return true
    }
    static func validChosenPassages(_ passages: [ChosenPassage], pageCount: Int) -> Bool {
        var ids = Set<UUID>()
        return passages.allSatisfy { passage in
            guard !passage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !passage.pages.isEmpty,
                  Set(passage.pages).count == passage.pages.count,
                  passage.pages.allSatisfy({ $0 > 0 && $0 <= pageCount }),
                  ids.insert(passage.id).inserted else { return false }
            return passage.sources.allSatisfy { source in
                source.page > 0 && source.page <= pageCount && passage.pages.contains(source.page) &&
                    !source.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }
    static func read(_ url: URL) throws -> Self {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 250_000_000 else { throw AppError(message: "This work document is too large (maximum 250 MB).") }
        var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        value.committeeReviews = value.committeeReviews.map { validCommitteeReviews($0, pages: value.pages) }
        value.savedChatThreads = value.savedChatThreads.map { threads in
            threads.filter { SavedChatThread.validate($0, pageCount: value.pages.count) }
        }
        value.savedChartAnalyses = value.savedChartAnalyses.map { charts in
            charts.filter { SavedChartAnalysis.validate($0, pageCount: value.pages.count) }
        }
        value.savedSelectionSummaries = value.savedSelectionSummaries.map { $0.filter { SavedSelectionSummary.validate($0, pageCount: value.pages.count) } }
        return value
    }
    func write(_ url: URL) throws {
        try validate()
        if let threads = savedChatThreads,
           !threads.allSatisfy({ SavedChatThread.validate($0, pageCount: pages.count) }) {
            throw AppError(message: "A saved document chat is invalid. Check the source quotes before saving the work document again.")
        }
        if let charts = savedChartAnalyses,
           !charts.allSatisfy({ SavedChartAnalysis.validate($0, pageCount: pages.count) }) {
            throw AppError(message: "A saved chart explanation or source image is invalid. Check the chart before saving the work document again.")
        }
        if let summaries = savedSelectionSummaries, !summaries.allSatisfy({ SavedSelectionSummary.validate($0, pageCount: pages.count) }) {
            throw AppError(message: "The selection summary could not be saved completely. Check the saved text and source pages.")
        }
        var safeCopy = self
        safeCopy.committeeReviews = safeCopy.committeeReviews.map { Self.validCommitteeReviews($0, pages: safeCopy.pages) }
        let data = try JSONEncoder().encode(safeCopy)
        guard data.count <= 250_000_000 else { throw AppError(message: "This work document is too large to save.") }
        try data.write(to: url, options: .atomic)
    }
}
