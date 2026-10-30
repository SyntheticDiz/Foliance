import Foundation

/// Stable, general-purpose analysis dimensions shared by every document profile.
struct CommitteeCategory: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let topics: [String]

    static let unassignedID = "unassigned"
    static let unassignedTitle = "Other or unclear"

    private static let general: [CommitteeCategory] = [
        .init(id: "findings", title: "Findings", topics: ["findings", "observations", "evidence", "results"]),
        .init(id: "decisions", title: "Decisions", topics: ["decisions", "approvals", "confirmed outcomes"]),
        .init(id: "actions", title: "Actions", topics: ["actions", "tasks", "follow-up", "commitments"]),
        .init(id: "costs", title: "Costs", topics: ["costs", "budgets", "funding", "financial impact"]),
        .init(id: "deadlines", title: "Deadlines", topics: ["dates", "deadlines", "timelines", "milestones"]),
        .init(id: "risks", title: "Risks", topics: ["risks", "constraints", "dependencies", "uncertainties"]),
        .init(id: "context", title: "Context", topics: ["background", "scope", "definitions", "other relevant context"])
    ]

    static func categories(for purpose: MeetingPurpose) -> [CommitteeCategory] {
        purpose == .raad ? [] : general
    }

    static func category(id: String, for purpose: MeetingPurpose) -> CommitteeCategory? {
        categories(for: purpose).first { $0.id == id }
    }

    static func title(for id: String?, purpose: MeetingPurpose) -> String {
        guard let id, let category = category(id: id, for: purpose) else { return unassignedTitle }
        return category.title
    }

    static func validIDs(_ ids: [String], for purpose: MeetingPurpose,
                         excluding primaryID: String? = nil) -> [String]? {
        let allowed = Set(categories(for: purpose).map(\.id))
        guard ids.allSatisfy({ allowed.contains($0) }),
              Set(ids).count == ids.count,
              !ids.contains(where: { $0 == primaryID }) else { return nil }
        return ids
    }
}
