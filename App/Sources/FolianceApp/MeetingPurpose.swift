import Foundation

/// A stable analysis profile. The legacy raw values remain the archive keys so
/// existing workspaces continue to decode without a migration.
enum MeetingPurpose: String, Codable, CaseIterable, Sendable {
    case raad
    case bestuur
    case leefomgeving
    case sociaalDomein

    /// Semantic alias for new call sites; `.raad` remains the persisted case.
    static var council: MeetingPurpose { .raad }

    var title: String {
        switch self {
        case .raad: return "Overview"
        case .bestuur: return "Report"
        case .leefomgeving: return "Project plan"
        case .sociaalDomein: return "Meeting notes"
        }
    }

    var topics: [String] { CommitteeCategory.categories(for: self).map(\.title) }

    var categories: [CommitteeCategory] { CommitteeCategory.categories(for: self) }

    var boundaries: String {
        "Use only information stated in the source. Preserve whether an item is a proposal, a stated intention or commitment, or a confirmed decision. Name an owner or date only when the source explicitly identifies it."
    }
}
