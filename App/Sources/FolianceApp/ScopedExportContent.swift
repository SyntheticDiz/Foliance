import Foundation

/// Immutable export snapshot content for whole-document, selection, and
/// reading-profile scopes. Content stays unchanged; app-owned scope labels are normalized to English.
struct ScopedExportContent: Sendable {
    let insights: [Insight]
    let chosenPassages: [ChosenPassage]
    let summary: DocumentSummary?
    let summaryScope: String
    let tables: [DocumentTable]
    let glossary: [ExportGlossaryItem]
    let notice: String
    let context: String
    let neutralAnalysis: Bool
    let committeeLabels: [String: String]

    init(insights: [Insight], chosenPassages: [ChosenPassage], summary: DocumentSummary?,
         summaryScope: String, tables: [DocumentTable], glossary: [ExportGlossaryItem],
         notice: String, context: String, neutralAnalysis: Bool,
         committeeLabels: [String: String] = [:]) {
        self.insights = insights
        self.chosenPassages = chosenPassages
        self.summary = summary
        self.summaryScope = summaryScope
        self.tables = tables
        self.glossary = glossary
        self.notice = notice
        self.context = context
        self.neutralAnalysis = neutralAnalysis
        self.committeeLabels = committeeLabels
    }

    static func make(configuration: ExportConfiguration, pages: [String], insights: [Insight],
                     review: CommitteeAssessmentService.Review?, summary: DocumentSummary?,
                     summaryScope: String, tables: [DocumentTable], chosenPassages: [ChosenPassage],
                     glossary: [ExportGlossaryItem], notice: String, context: String,
                     neutralAnalysis: Bool) -> ScopedExportContent {
        guard let purpose = configuration.committeePurpose else {
            return ScopedExportContent(insights: insights, chosenPassages: chosenPassages,
                                       summary: summary, summaryScope: UIStrings.text(summaryScope), tables: tables,
                                       glossary: glossary, notice: notice, context: context,
                                       neutralAnalysis: neutralAnalysis)
        }

        guard let review, review.purpose == purpose,
              CommitteeAssessmentService.validateSources(review, pages: pages) else {
            return ScopedExportContent(insights: [], chosenPassages: configuration.chosenPassages ? chosenPassages : [],
                                       summary: configuration.summary ? summary : nil,
                                       summaryScope: "Entire document", tables: configuration.tables ? tables : [],
                                       glossary: configuration.glossary ? glossary : [], notice: notice,
                                       context: committeeContext(purpose: purpose, original: context,
                                                                 generalComponents: generalComponents(configuration: configuration,
                                                                                                      summary: summary,
                                                                                                      tables: tables,
                                                                                                      glossary: glossary)),
                                       neutralAnalysis: neutralAnalysis)
        }

        let presentation = CommitteePointPresentation(review: review, points: insights)
        let passages = Dictionary(uniqueKeysWithValues: PassageEngine.passages(pages).map { ($0.id, $0) })
        var scopedInsights: [Insight] = []
        var committeeLabels = [String: String]()
        var generatedSourceOnly = [ChosenPassage]()
        for row in presentation.rows where row.assessment.rating != .other {
            if row.points.isEmpty {
                guard let sourcePassage = passages[row.assessment.passageID] else { continue }
                let text = sourcePassage.text
                generatedSourceOnly.append(ChosenPassage(
                    id: stablePassageUUID(row.assessment.passageID),
                    title: "Profile review: \(ratingTitle(row.assessment.rating)) · full source passage",
                    note: row.assessment.reason,
                    text: text,
                    pages: sourcePassage.sources.map(\.page),
                    sources: row.assessment.sources.map { .init(page: $0.page, quote: $0.quote) }))
            } else {
                scopedInsights += row.points
                let label = ratingLabel(row.assessment.rating)
                for point in row.points { committeeLabels[SimpleWorkspace.selectionKey(point)] = label }
            }
        }
        scopedInsights += presentation.unmatchedPoints
        for point in presentation.unmatchedPoints {
            committeeLabels[SimpleWorkspace.selectionKey(point)] = "Not safely linked to a reading-profile passage · check the source"
        }

        let configuredPassages = configuration.chosenPassages ? chosenPassages : []
        let allPassages = configuredPassages + generatedSourceOnly.filter { generated in
            !configuredPassages.contains(where: { sameLiteralPassage($0, generated) })
        }
        let global = generalComponents(configuration: configuration, summary: summary,
                                       tables: tables, glossary: glossary)
        let scopedSummary = configuration.summary ? summary : nil
        let hasGlobal = !global.isEmpty
        let scopeContext = "Profile scope: \(purpose.title). The findings list includes only passages with an existing rating other than ‘other’, safely linked findings, and separately identified unmatched findings."
        func count(_ rating: CommitteeAssessmentService.Rating) -> Int {
            review.entries.filter { $0.rating == rating }.count
        }
        let ratingContext = "Paragraph-level profile review (AI assessment; check against the source): " +
            "\(count(.important)) important, \(count(.relevant)) relevant, \(count(.uncertain)) uncertain, " +
            "\(count(.unassessed)) not assessed; \(count(.other)) ‘other’ passages excluded."
        let unmatchedContext: String? = {
            let count = presentation.unmatchedPoints.count
            guard count > 0 else { return nil }
            return count == 1
                ? "1 finding could not be safely linked to an assessed passage; its content is unchanged and separately labeled."
                : "\(count) findings could not be safely linked to an assessed passage; their content is unchanged and separately labeled."
        }()
        let fullContext = [context.isEmpty ? nil : context, scopeContext, ratingContext, unmatchedContext,
                           hasGlobal ? "Document-wide sections (not limited to this reading profile): " + global.joined(separator: ", ") + "." : nil]
            .compactMap { $0 }
            .joined(separator: "\n")

        return ScopedExportContent(insights: scopedInsights, chosenPassages: allPassages,
                                   summary: scopedSummary,
                                   summaryScope: scopedSummary == nil ? UIStrings.text(summaryScope) : "Entire document (profile review shown separately)",
                                   tables: configuration.tables ? tables : [],
                                   glossary: configuration.glossary ? glossary : [],
                                   notice: notice, context: fullContext,
                                   neutralAnalysis: neutralAnalysis, committeeLabels: committeeLabels)
    }

    private static func generalComponents(configuration: ExportConfiguration, summary: DocumentSummary?,
                                          tables: [DocumentTable], glossary: [ExportGlossaryItem]) -> [String] {
        var result = [String]()
        if configuration.summary, summary != nil { result.append("document summary") }
        if configuration.tables, !tables.isEmpty { result.append("table explanations") }
        if configuration.glossary, !glossary.isEmpty { result.append("abbreviations and definitions") }
        return result
    }

    private static func committeeContext(purpose: MeetingPurpose, original: String,
                                         generalComponents: [String]) -> String {
        let prefix = "Profile scope: \(purpose.title). No current source-validated review is available, so the profile findings section is empty."
        let global = generalComponents.isEmpty ? nil : "Document-wide sections (not limited to this reading profile): " + generalComponents.joined(separator: ", ") + "."
        return [original.isEmpty ? nil : original, prefix, global]
            .compactMap { $0 }.joined(separator: "\n")
    }

    private static func stablePassageUUID(_ passageID: String) -> UUID {
        let bytes = Array(LocalCache.key(["committee-export-passage", passageID]).utf8.prefix(32))
        let hex = String(bytes: bytes, encoding: .utf8) ?? "00000000000000000000000000000000"
        let chars = Array(hex)
        let raw = (0..<16).map { index -> UInt8 in
            let high = UInt8(chars[index * 2].hexDigitValue ?? 0)
            let low = UInt8(chars[index * 2 + 1].hexDigitValue ?? 0)
            return (high << 4) | low
        }
        return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
    }

    private static func sameLiteralPassage(_ lhs: ChosenPassage, _ rhs: ChosenPassage) -> Bool {
        lhs.pages == rhs.pages && Data(lhs.text.utf8).elementsEqual(Data(rhs.text.utf8)) &&
            lhs.sources.count == rhs.sources.count && zip(lhs.sources, rhs.sources).allSatisfy { a, b in
                a.page == b.page && Data(a.quote.utf8).elementsEqual(Data(b.quote.utf8))
            }
    }

    private static func ratingTitle(_ rating: CommitteeAssessmentService.Rating) -> String {
        switch rating {
        case .important: "important"
        case .relevant: "relevant"
        case .uncertain: "uncertain"
        case .unassessed: "not assessed"
        case .other: "other"
        }
    }

    private static func ratingLabel(_ rating: CommitteeAssessmentService.Rating) -> String {
        switch rating {
        case .important: "Profile review: important"
        case .relevant: "Profile review: relevant"
        case .uncertain: "Profile review: uncertain · check the source"
        case .unassessed: "Profile review: not assessed · check the source"
        case .other: "Profile review: other"
        }
    }
}
