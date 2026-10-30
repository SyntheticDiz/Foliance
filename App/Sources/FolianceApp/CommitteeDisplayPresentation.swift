import Foundation

/// View-only structure for the committee points list. It never changes an
/// assessment, its topic metadata, or its associated points and sources.
enum CommitteeDisplayPresentation {
    struct CategoryGroup: Identifiable {
        let id: String
        let title: String
        let rows: [CommitteePointPresentation.Row]
        let importantCount: Int
        var isUnassigned: Bool { id == CommitteeCategory.unassignedID }
    }

    struct Subgroup: Identifiable {
        let id: String
        let title: String
        let rows: [CommitteePointPresentation.Row]
    }

    /// Belangrijkste is limited to important rows. Alle punten contains every
    /// rating; the view decides whether the checking fold is shown separately.
    static func mainRows(_ rows: [CommitteePointPresentation.Row], showAll: Bool) -> [CommitteePointPresentation.Row] {
        rows.filter { row in
            switch row.assessment.rating {
            case .important: true
            case .relevant, .other, .uncertain, .unassessed: showAll
            }
        }
    }

    static func checkingRows(_ rows: [CommitteePointPresentation.Row]) -> [CommitteePointPresentation.Row] {
        rows.filter { [.uncertain, .unassessed].contains($0.assessment.rating) }
    }

    static func categoryGroups(_ rows: [CommitteePointPresentation.Row], purpose: MeetingPurpose) -> [CategoryGroup] {
        let definitions = CommitteeCategory.categories(for: purpose)
        let orderedIDs = definitions.map(\.id) + [CommitteeCategory.unassignedID]
        return orderedIDs.compactMap { id in
            let members = rows.filter {
                (CommitteeCategorizationService.validatedPrimaryCategoryID(for: $0.assessment, purpose: purpose)
                    ?? CommitteeCategory.unassignedID) == id
            }
            guard !members.isEmpty else { return nil }
            return CategoryGroup(id: id,
                                 title: id == CommitteeCategory.unassignedID ? CommitteeCategory.unassignedTitle : (definitions.first { $0.id == id }?.title ?? id),
                                 rows: members,
                                 importantCount: members.filter { $0.assessment.rating == .important }.count)
        }
    }

    /// Initial ordering uses important counts, with category-definition order
    /// as the tie breaker. Once initialized, surviving IDs never move and new
    /// IDs are appended, so progress updates do not reorder an open list.
    static func stableCategoryOrder(existing: [String]?, groups: [CategoryGroup], purpose: MeetingPurpose) -> [String] {
        guard let existing else {
            let categoryOrder = CommitteeCategory.categories(for: purpose).map(\.id)
            let definitionOrder = Dictionary(uniqueKeysWithValues: categoryOrder.enumerated().map { ($1, $0) })
            let categories = groups.filter { !$0.isUnassigned }.sorted {
                $0.importantCount == $1.importantCount
                    ? (definitionOrder[$0.id, default: .max] < definitionOrder[$1.id, default: .max])
                    : $0.importantCount > $1.importantCount
            }.map(\.id)
            return categories + groups.filter(\.isUnassigned).map(\.id)
        }
        var result = existing
        let alreadyIncluded = Set(result)
        result.append(contentsOf: groups.map(\.id).filter { !alreadyIncluded.contains($0) })
        return result
    }

    static func initialExpandedCategoryState(storedState: Set<String>, hasStoredState: Bool,
                                             orderedIDs: [String], groups: [CategoryGroup]) -> Set<String>? {
        guard !groups.isEmpty else { return nil }
        guard !hasStoredState else { return storedState }
        guard let firstImportant = orderedIDs.first(where: { id in (groups.first(where: { $0.id == id })?.importantCount ?? 0) > 0 }) else { return [] }
        return [firstImportant]
    }

    /// Local display buckets for rows whose topic is missing. These are based
    /// only on the saved rating; no topic inference is performed.
    static func unassignedSubgroups(_ rows: [CommitteePointPresentation.Row]) -> [Subgroup] {
        let buckets: [(String, String, Set<CommitteeAssessmentService.Rating>)] = [
            ("topic-missing", "Relevant/belangrijk · onderwerp ontbreekt", [.important, .relevant]),
            ("uncertain", "Twijfel", [.uncertain]),
            ("unassessed", "Nog niet beoordeeld", [.unassessed]),
            ("other", "Overige passages", [.other])
        ]
        return buckets.compactMap { id, title, ratings in
            let members = rows.filter { ratings.contains($0.assessment.rating) }
            return members.isEmpty ? nil : Subgroup(id: id, title: title, rows: members)
        }
    }
}
