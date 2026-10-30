import Foundation

/// A sheet-local immutable copy of the values used to describe and preview an
/// export. Capturing happens on the workspace actor; the pure derivation can run
/// off the UI actor without asking the live workspace for computed properties.
struct ExportPresentationSource: Sendable {
    let document: OpenPDF?
    let documentID: UUID
    let revisionToken: UUID
    let pages: [String]
    let readings: [PageReading]
    let insights: [Insight]
    let passageQuestions: [String: [PassageQuestion]]
    let starred: Set<String>
    let selectionMetadata: SavedSelectionMetadata
    let annotations: [String: PointAnnotation]
    let committeeReviews: [String: CommitteeAssessmentService.Review]
    let summary: DocumentSummary?
    let summaryScope: String
    let tables: [DocumentTable]
    let chosenPassages: [ChosenPassage]
    let notice: String
    let context: String
    let neutralAnalysis: Bool
    let analyzed: Bool
    let analysisScope: String

    @MainActor
    static func capture(from workspace: SimpleWorkspace) -> Self {
        Self(document: workspace.document,
             documentID: workspace.documentID,
             revisionToken: workspace.revisionToken,
             pages: workspace.document?.pages ?? [],
             readings: workspace.document?.readings ?? [],
             insights: workspace.insights,
             passageQuestions: workspace.passageQuestions,
             starred: workspace.starred,
             selectionMetadata: workspace.selectionMetadata,
             annotations: workspace.annotations,
             committeeReviews: workspace.committeeReviews,
             summary: workspace.documentSummary,
             summaryScope: workspace.summaryScope,
             tables: workspace.tables,
             chosenPassages: workspace.chosenPassages,
             notice: workspace.exportNotice,
             context: workspace.exportContext,
             neutralAnalysis: workspace.neutralAnalysis,
             analyzed: workspace.analyzed,
             analysisScope: workspace.analysisScope)
    }
}

/// Config fields that affect the export wizard. This avoids JSON encoding and
/// source-content hashing just to decide whether the current sheet cache applies.
struct ExportPresentationConfigurationKey: Hashable, Sendable {
    let committeePurpose: String?
    let summary: Bool
    let pagePoints: Bool
    let politics: Bool
    let questions: Bool
    let glossary: Bool
    let tables: Bool
    let notes: Bool
    let chosenPassages: Bool
    let sources: Bool
    let selectedPoints: Bool
    let selectedQuestions: Bool

    init(_ value: ExportConfiguration) {
        committeePurpose = value.committeePurpose?.rawValue
        summary = value.summary
        pagePoints = value.pagePoints
        politics = value.politics
        questions = value.questions
        glossary = value.glossary
        tables = value.tables
        notes = value.notes
        chosenPassages = value.chosenPassages
        sources = value.sources
        selectedPoints = value.selectedPoints
        selectedQuestions = value.selectedQuestions
    }
}

struct ExportPresentationSourceKey: Hashable, Sendable {
    let documentID: UUID
    let revisionToken: UUID
    let glossaryRevision: UUID
}

struct ExportPresentationCacheKey: Hashable, Sendable {
    let source: ExportPresentationSourceKey
    let configuration: ExportPresentationConfigurationKey
}

struct ExportPresentationSnapshot: Sendable {
    let sourceKey: ExportPresentationSourceKey
    let configurationKey: ExportPresentationConfigurationKey
    let configuration: ExportConfiguration
    let scopedRequest: ExportConfiguration
    let effective: ExportConfiguration
    let requestedContent: ScopedExportContent
    let content: ScopedExportContent
    let availableInsights: [Insight]
    let selectedInsights: [Insight]
    let baseInsights: [Insight]
    let questions: [Insight]
    let noteCount: Int
    let selectedIDs: Set<String>
    let selectedOrder: [String]
    let selectionStatuses: [String: SelectionMeetingStatus]
    let annotations: [String: PointAnnotation]
    let hasPoliticalInsights: Bool
    let hasQuestions: Bool
    let document: OpenPDF?
    let analyzed: Bool
    let analysisScope: String

    var cacheKey: ExportPresentationCacheKey {
        .init(source: sourceKey, configuration: configurationKey)
    }
}

/// One reusable base derivation per visible export sheet, plus at most a small
/// number of configuration-specific snapshots for back-and-forth wizard edits.
struct ExportPresentationBase: Sendable {
    let source: ExportPresentationSource
    let sourceKey: ExportPresentationSourceKey
    let exportInsights: [Insight]
    let selectionKeys: [String: [String]]
    let selectionKeyByPointID: [String: String]
    let starredInsights: [Insight]
    let selectedInsights: [Insight]
    let exportAnnotations: [String: PointAnnotation]

    init(source: ExportPresentationSource, glossaryRevision: UUID) throws {
        try Task.checkCancellation()
        self.source = source
        self.sourceKey = .init(documentID: source.documentID,
                               revisionToken: source.revisionToken,
                               glossaryRevision: glossaryRevision)

        let organized = InsightOrganization.merged(source.insights)
        try Task.checkCancellation()
        var keysByPointID: [String: [String]] = [:]
        keysByPointID.reserveCapacity(organized.count)
        var selectionKeyByPointID: [String: String] = [:]
        selectionKeyByPointID.reserveCapacity(organized.count)
        var exported: [Insight] = []
        exported.reserveCapacity(organized.count)
        for (index, point) in organized.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let pointKeys = SimpleWorkspace.selectionKeys(point)
            let pointID = point.id
            keysByPointID[pointID] = pointKeys
            selectionKeyByPointID[pointID] = SimpleWorkspace.selectionKey(point)
            var seenQuestions = Set<String>()
            let questions = ([point.question] + pointKeys.flatMap { source.passageQuestions[$0] ?? [] }.map(\.question)).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seenQuestions.insert($0).inserted
            }
            exported.append(Insight(title: point.title, summary: point.summary, relevance: point.relevance,
                                    question: questions.count > 1 ? questions.map { "• " + $0 }.joined(separator: "\n\n") : questions.first ?? "",
                                    quote: point.quote, page: point.page, programSource: point.programSource,
                                    otherSources: point.otherSources, passageID: point.passageID,
                                    relevanceClass: point.relevanceClass, relevanceReason: point.relevanceReason,
                                    contextSources: point.contextSources, passagePartIndex: point.passagePartIndex,
                                    passagePartCount: point.passagePartCount, passageSources: point.passageSources))
        }
        exportInsights = exported

        var starred: [Insight] = []
        starred.reserveCapacity(exported.count)
        for (index, point) in exported.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            if (keysByPointID[point.id] ?? SimpleWorkspace.selectionKeys(point)).contains(where: source.starred.contains) {
                starred.append(point)
            }
        }
        starredInsights = starred
        var selectedByKey: [String: Insight] = [:]
        for (index, point) in starred.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let key = selectionKeyByPointID[point.id] ?? SimpleWorkspace.selectionKey(point)
            if selectedByKey[key] == nil { selectedByKey[key] = point }
        }
        var seenSelectionOrder = Set<String>()
        let orderedKeys = source.selectionMetadata.order.filter {
            selectedByKey[$0] != nil && seenSelectionOrder.insert($0).inserted
        }
        let orderedSet = seenSelectionOrder
        selectedInsights = orderedKeys.compactMap { selectedByKey[$0] } + starred.filter {
            !orderedSet.contains(selectionKeyByPointID[$0.id] ?? SimpleWorkspace.selectionKey($0))
        }

        var annotationsByKey: [String: PointAnnotation] = [:]
        for (index, point) in organized.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let key = selectionKeyByPointID[point.id] ?? SimpleWorkspace.selectionKey(point)
            guard let annotation = source.annotations[key], !annotation.note.isEmpty || annotation.checkedSignature != nil else { continue }
            if annotationsByKey[key] == nil { annotationsByKey[key] = annotation }
        }
        exportAnnotations = annotationsByKey
        selectionKeys = keysByPointID
        self.selectionKeyByPointID = selectionKeyByPointID
    }

    func snapshot(configuration choices: ExportConfiguration,
                  glossary: [ExportGlossaryItem]) throws -> ExportPresentationSnapshot {
        try Task.checkCancellation()
        let configurationKey = ExportPresentationConfigurationKey(choices)
        var request = choices
        request.tables = request.tables && !source.tables.isEmpty
        request.summary = request.summary && source.summary != nil
        request.chosenPassages = request.chosenPassages && (!source.chosenPassages.isEmpty || choices.committeePurpose != nil)
        request.glossary = request.glossary && !glossary.isEmpty
        let questionCandidates = choices.selectedQuestions ? selectedInsights : exportInsights
        request.questions = request.questions && questionCandidates.contains {
            !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        request.politics = request.politics && !source.neutralAnalysis && exportInsights.contains { !$0.relevance.isEmpty }
        request.sources = request.sources && (request.pagePoints || request.politics || request.questions)

        let requestedContent = makeContent(configuration: request, glossary: glossary)
        try Task.checkCancellation()
        let availableInsights = choices.committeePurpose == nil ? exportInsights : requestedContent.insights
        let baseInsights: [Insight]
        let eligibleKeys = Set(availableInsights.map(SimpleWorkspace.selectionKey))
        if choices.selectedPoints {
            var selectedBase: [Insight] = []
            selectedBase.reserveCapacity(selectedInsights.count)
            for (index, point) in selectedInsights.enumerated() {
                if index.isMultiple(of: 64) { try Task.checkCancellation() }
                if eligibleKeys.contains(selectionKeyByPointID[point.id] ?? SimpleWorkspace.selectionKey(point)) {
                    selectedBase.append(point)
                }
            }
            baseInsights = selectedBase
        } else {
            baseInsights = availableInsights
        }
        let questions = availableInsights.filter { point in
            let isSelected = (selectionKeys[point.id] ?? SimpleWorkspace.selectionKeys(point)).contains(where: source.starred.contains)
            return (!choices.selectedQuestions || isSelected) && !point.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let baseKeys = Set(baseInsights.map { selectionKeyByPointID[$0.id] ?? SimpleWorkspace.selectionKey($0) })
        let noteCount = exportAnnotations.keys.filter(baseKeys.contains).count

        var effective = request
        effective.tables = effective.tables && !requestedContent.tables.isEmpty
        effective.summary = effective.summary && requestedContent.summary != nil
        effective.chosenPassages = effective.chosenPassages && !requestedContent.chosenPassages.isEmpty
        effective.glossary = effective.glossary && !requestedContent.glossary.isEmpty
        effective.pagePoints = effective.pagePoints && !baseInsights.isEmpty
        effective.politics = effective.politics && !source.neutralAnalysis && requestedContent.insights.contains { !$0.relevance.isEmpty }
        effective.questions = effective.questions && !questions.isEmpty
        effective.notes = effective.notes && noteCount > 0
        effective.sources = effective.sources && (effective.pagePoints || effective.politics || effective.questions)

        // `effective` only turns off components that were already empty in the
        // requested content. ScopedExportContent.make is more expensive for
        // committee scopes because it validates and materializes all source rows.
        let content = requestedContent
        try Task.checkCancellation()
        let selectedIDs = Set(content.insights.filter { point in
            (selectionKeys[point.id] ?? SimpleWorkspace.selectionKeys(point)).contains(where: source.starred.contains)
        }.map { selectionKeyByPointID[$0.id] ?? SimpleWorkspace.selectionKey($0) })

        return ExportPresentationSnapshot(sourceKey: sourceKey,
                                          configurationKey: configurationKey,
                                          configuration: choices,
                                          scopedRequest: request,
                                          effective: effective,
                                          requestedContent: requestedContent,
                                          content: content,
                                          availableInsights: availableInsights,
                                          selectedInsights: selectedInsights,
                                          baseInsights: baseInsights,
                                          questions: questions,
                                          noteCount: noteCount,
                                          selectedIDs: selectedIDs,
                                          selectedOrder: selectedInsights.map { selectionKeyByPointID[$0.id] ?? SimpleWorkspace.selectionKey($0) },
                                          selectionStatuses: source.selectionMetadata.statuses,
                                          annotations: exportAnnotations,
                                          hasPoliticalInsights: !source.neutralAnalysis && exportInsights.contains { !$0.relevance.isEmpty },
                                          hasQuestions: exportInsights.contains { !$0.question.isEmpty },
                                          document: source.document,
                                          analyzed: source.analyzed,
                                          analysisScope: source.analysisScope)
    }

    private func makeContent(configuration: ExportConfiguration,
                             glossary: [ExportGlossaryItem]) -> ScopedExportContent {
        ScopedExportContent.make(configuration: configuration,
                                 pages: source.pages,
                                 insights: exportInsights,
                                 review: configuration.committeePurpose.flatMap { source.committeeReviews[$0.rawValue] },
                                 summary: source.summary,
                                 summaryScope: source.summaryScope,
                                 tables: source.tables,
                                 chosenPassages: source.chosenPassages,
                                 glossary: glossary,
                                 notice: source.notice,
                                 context: source.context,
                                 neutralAnalysis: source.neutralAnalysis)
    }
}
