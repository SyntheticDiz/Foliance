import Foundation

/// View-only associations: generated points and complete assessment sources are
/// never rewritten. Points without a safe parent match stay separately visible.
struct CommitteePointPresentation {
    struct Row: Identifiable {
        let assessment: CommitteeAssessmentService.Assessment
        let points: [Insight]
        var id: String { assessment.passageID }
        var scrollID: String { "committee-passage-" + id }
    }
    let rows: [Row]
    let unmatchedPoints: [Insight]
    let ordered: [Row]

    init(review: CommitteeAssessmentService.Review, points: [Insight]) {
        func key(_ sources: [Insight.Source]) -> String {
            LocalCache.key(sources.flatMap { [String($0.page), $0.quote] })
        }
        let byID = Dictionary(review.entries.enumerated().map { ($0.element.passageID, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let bySource = Dictionary(review.entries.enumerated().map { (key($0.element.sources), $0.offset) }, uniquingKeysWith: { first, _ in first })
        var matched: [Int: [Insight]] = [:]
        var unmatched: [Insight] = []
        for point in points {
            var destination: Int?
            if let sources = point.passageSources, !sources.isEmpty {
                if let id = point.passageID, let index = byID[id], key(review.entries[index].sources) == key(sources) {
                    destination = index
                } else { destination = bySource[key(sources)] }
            }
            if let destination { matched[destination, default: []].append(point) }
            else { unmatched.append(point) }
        }
        let builtRows = review.entries.enumerated().map { Row(assessment: $0.element, points: matched[$0.offset] ?? []) }
        rows = builtRows
        unmatchedPoints = unmatched
        let ranks: [CommitteeAssessmentService.Rating: Int] = [.important: 0, .relevant: 1, .uncertain: 2, .unassessed: 3, .other: 4]
        ordered = builtRows.enumerated().sorted {
            let a = ranks[$0.element.assessment.rating, default: 3], b = ranks[$1.element.assessment.rating, default: 3]
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    var important: [Row] { rows.filter { $0.assessment.rating == .important } }
    func scrollID(containing pointID: String) -> String? {
        rows.first(where: { $0.points.contains(where: { $0.id == pointID }) })?.scrollID
    }
    var checking: [Row] { rows.filter { [.uncertain, .unassessed].contains($0.assessment.rating) } }
}
