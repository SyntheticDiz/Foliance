import Foundation

enum SelectionMeetingStatus: String, Codable, CaseIterable, Sendable {
    case discuss = "Bespreken"
    case askQuestion = "Vraag stellen"
    case done = "Afgehandeld"
}

struct SavedSelectionMetadata: Codable, Sendable, Equatable {
    var order: [String] = []
    var statuses: [String: SelectionMeetingStatus] = [:]
}

/// The display state captured by a workdocument. Optional fields on the containing
/// archive keep older snapshots readable without pretending their state was saved.
struct WorkspaceViewState: Codable, Sendable, Equatable {
    var section = "Overzicht"
    var pointsMode = "featured"
    var openGroups: Set<String> = []
    var pointPageFilter = ""
    var reviewFilter = 0
    var pdfVisible = true
    var pointsExpanded = false
    var compactReading = false
    var search = ""
    var committeeShowAll: [String: Bool]? = nil
    var committeeOpenCategories: [String: Set<String>]? = nil
    var openTableIDs: Set<String>? = nil
    var lastTableID: String? = nil
}
