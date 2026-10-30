import Foundation

enum ReadingAgendaCategory: String, CaseIterable, Identifiable, Sendable {
    case decisions = "Decisions"
    case money = "Costs"
    case deadlines = "Deadlines"
    case actions = "Actions"
    case risks = "Risks"
    case openQuestions = "Open questions"
    var id: String { rawValue }
}

struct ReadingAgendaEntry: Identifiable, Sendable {
    let category: ReadingAgendaCategory
    let point: Insight
    var id: String { point.id }
}

/// A navigation aid over existing findings. It selects existing text and never
/// writes a combined interpretation or creates a new statement.
enum ReadingAgenda {
    private static func normalized(_ text: String) -> String {
        " " + text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") + " "
    }
    private static let decisionTerms = [" decision ", " decided ", " approved ", " confirmed ", " proposal ", " proposed ", " commitment ", " besluit ", " besloten ", " vastgesteld ", " voorstel ", " voorgesteld ", " toezegging "]
    private static let moneyTerms = ["€", " euro ", " cost ", " budget ", " funding ", " expense ", " finance ", " kosten ", " begroting ", " financiering ", " uitgaven "]
    private static let deadlineTerms = [" deadline ", " due date ", " timeline ", " milestone ", " by ", " before ", " uiterlijk ", " termijn ", " planning ", " vanaf ", " eind 20", " in 20"]
    private static let actionTerms = [" action ", " task ", " owner ", " responsible ", " follow up ", " assigned ", " actie ", " taak ", " eigenaar ", " verantwoordelijk ", " opdracht "]
    private static let riskTerms = [" risk ", " dependency ", " constraint ", " blocker ", " issue ", " risico ", " afhankelijkheid ", " beperking ", " knelpunt "]

    static func entries(_ points: [Insight]) -> [ReadingAgendaEntry] {
        points.flatMap { point -> [ReadingAgendaEntry] in
            guard point.relevanceClass != "background" else { return [] }
            let text = normalized(point.title + " " + point.summary)
            var result: [ReadingAgendaEntry] = []
            if decisionTerms.contains(where: text.contains) { result.append(.init(category: .decisions, point: point)) }
            if (point.title + " " + point.summary).contains("€") || moneyTerms.contains(where: text.contains) { result.append(.init(category: .money, point: point)) }
            if deadlineTerms.contains(where: text.contains) { result.append(.init(category: .deadlines, point: point)) }
            if actionTerms.contains(where: text.contains) { result.append(.init(category: .actions, point: point)) }
            if riskTerms.contains(where: text.contains) { result.append(.init(category: .risks, point: point)) }
            if !point.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.init(category: .openQuestions, point: point)) }
            return result
        }
    }
}

struct DocumentCoverage: Sendable {
    enum CoverageStatus: Sendable, Equatable { case unknown, partial, complete(total: Int) }
    let readablePages: Int
    let totalPages: Int
    let unreadablePageNumbers: [Int]
    let analysis: CoverageStatus
    let completedAnalysisPageNumbers: [Int]?
    let uncertainTableIDs: [String]
    let unconfirmedOCRTableIDs: [String]
    let confirmedOCRTables: Int
    let unconfirmedOCRTables: Int
    let reliableTextTables: Int
    let uncertainTextTables: Int

    static func make(pages: [String], completedAnalysisPages: [Int]?, analysisState: AnalysisState, tables: [DocumentTable]) -> Self {
        let readable = pages.enumerated().compactMap { index, text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : index + 1
        }
        let analysis: CoverageStatus
        if let completedAnalysisPages {
            analysis = .complete(total: Set(completedAnalysisPages).intersection(readable).count)
        } else {
            switch analysisState {
            case .running, .incomplete, .failed, .cancelled: analysis = .partial
            default: analysis = .unknown
            }
        }
        let ocr = tables.filter { $0.recognizedWithOCR == true }
        let textTables = tables.filter { $0.recognizedWithOCR != true }
        return .init(readablePages: readable.count, totalPages: pages.count,
                     unreadablePageNumbers: pages.isEmpty ? [] : (1...pages.count).filter { !readable.contains($0) }, analysis: analysis,
                     completedAnalysisPageNumbers: completedAnalysisPages.map { Array(Set($0).intersection(readable)).sorted() },
                     uncertainTableIDs: textTables.filter { !$0.reliable }.map(\.id),
                     unconfirmedOCRTableIDs: ocr.filter { !$0.isOCRConfirmed }.map(\.id),
                     confirmedOCRTables: ocr.filter(\.isOCRConfirmed).count,
                     unconfirmedOCRTables: ocr.filter { !$0.isOCRConfirmed }.count,
                     reliableTextTables: textTables.filter(\.reliable).count,
                     uncertainTextTables: textTables.filter { !$0.reliable }.count)
    }
}
