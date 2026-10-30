import Foundation

/// Display grouping for points that share the same exact parent passage.
/// Each child keeps its identity and relative order within its group.
struct PassagePointGroup: Identifiable {
    var points: [Insight]

    var id: String { points.first?.id ?? "" }

    static func partition(_ points: [Insight]) -> [PassagePointGroup] {
        var result: [PassagePointGroup] = []
        var groupIndices: [Key: Int] = [:]

        for point in points {
            guard let key = groupingKey(for: point) else {
                result.append(PassagePointGroup(points: [point]))
                continue
            }

            if let groupIndex = groupIndices[key] {
                result[groupIndex].points.append(point)
            } else {
                groupIndices[key] = result.count
                result.append(PassagePointGroup(points: [point]))
            }
        }
        return result
    }

    private struct SourceKey: Hashable {
        let page: Int
        let quoteBytes: Data
    }

    private struct Key: Hashable {
        let passageIDBytes: Data
        let sources: [SourceKey]
    }

    private static func groupingKey(for point: Insight) -> Key? {
        guard let passageID = point.passageID,
              !passageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sources = point.passageSources, !sources.isEmpty,
              sources.contains(where: { $0.page == point.page }),
              sources.map(\.page) == sources.map(\.page).sorted(),
              sources.allSatisfy({ $0.page > 0 && !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        return Key(
            passageIDBytes: Data(passageID.utf8),
            sources: sources.map { SourceKey(page: $0.page, quoteBytes: Data($0.quote.utf8)) }
        )
    }
}
