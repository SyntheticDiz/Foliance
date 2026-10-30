import Foundation

/// A complete, immutable presentation snapshot for one cloud insight update.
/// The raw points are retained for persistence and provenance; the other values
/// are the exact derived views consumed by the workspace.
struct CloudInsightPresentation: Sendable {
    let insights: [Insight]
    let organizedInsights: [Insight]
    let insightGroups: [InsightGroup]
    let featuredInsightGroups: [InsightGroup]

    static func make(insights: [Insight], readings: [PageReading]) -> Self {
        let organized = InsightOrganization.merged(insights)
        let groups = InsightOrganization.groups(organized, readings: readings)
        let featured = InsightOrganization.featured(groups)
        return Self(insights: insights, organizedInsights: organized,
                    insightGroups: groups, featuredInsightGroups: featured)
    }

    static func makeOffMain(insights: [Insight], readings: [PageReading]) async throws -> Self {
        try Task.checkCancellation()
        try Task.checkCancellation()
        let work = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let snapshot = make(insights: insights, readings: readings)
            try Task.checkCancellation()
            return snapshot
        }
        return try await withTaskCancellationHandler {
            let snapshot = try await work.value
            try Task.checkCancellation()
            return snapshot
        } onCancel: {
            work.cancel()
        }
    }
}
