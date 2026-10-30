import Foundation

/// A single-document, single-purpose cache for committee display derivations.
/// The inputs are immutable review/point snapshots; display filters stay live.
@MainActor
final class CommitteePresentationCache {
    private struct Key: Equatable {
        let documentID: UUID
        let purpose: MeetingPurpose
        let pointsRevision: UUID
        let reviewRevision: UUID
    }

    private var key: Key?
    private var snapshot: CommitteePresentationSnapshot?

    func value(documentID: UUID, purpose: MeetingPurpose,
               pointsRevision: UUID, reviewRevision: UUID,
               review: CommitteeAssessmentService.Review,
               points: [Insight]) -> CommitteePresentationSnapshot {
        let requested = Key(documentID: documentID, purpose: purpose,
                            pointsRevision: pointsRevision, reviewRevision: reviewRevision)
        if key == requested, let snapshot { return snapshot }
        let built = CommitteePresentationSnapshot(review: review, points: points, purpose: purpose)
        key = requested
        snapshot = built
        return built
    }

    func clear() {
        key = nil
        snapshot = nil
    }
}

@MainActor
final class CommitteePresentationSnapshot {
    struct Filtered {
        let rows: [CommitteePointPresentation.Row]
        let categoryGroups: [CommitteeDisplayPresentation.CategoryGroup]
        let mainGroups: [CommitteeDisplayPresentation.CategoryGroup]
        let checkingGroups: [CommitteeDisplayPresentation.CategoryGroup]
    }

    let presentation: CommitteePointPresentation
    let purpose: MeetingPurpose
    private let categoryIDsByPassage: [String: String]
    private let pagesByPassage: [String: Set<Int>]
    private let categoryTitles: [String: String]

    init(review: CommitteeAssessmentService.Review, points: [Insight], purpose: MeetingPurpose) {
        let presentation = CommitteePointPresentation(review: review, points: points)
        self.presentation = presentation
        self.purpose = purpose
        let definitions = CommitteeCategory.categories(for: purpose)
        categoryTitles = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.title) })
        var categories: [String: String] = [:]
        var pages: [String: Set<Int>] = [:]
        categories.reserveCapacity(presentation.rows.count)
        pages.reserveCapacity(presentation.rows.count)
        for row in presentation.rows {
            categories[row.id] = CommitteeCategorizationService.validatedPrimaryCategoryID(
                for: row.assessment, purpose: purpose) ?? CommitteeCategory.unassignedID
            pages[row.id] = Set(row.assessment.sources.map(\.page))
        }
        categoryIDsByPassage = categories
        pagesByPassage = pages
    }

    /// Applies current page/review/annotation state in one ordered pass and
    /// forms display groups without revalidating category metadata per body.
    func filtered(pages selectedPages: Set<Int>?, reviewFilter: Int,
                  annotation: (Insight) -> PointAnnotation) -> Filtered {
        var rows: [CommitteePointPresentation.Row] = []
        var grouped: [String: [CommitteePointPresentation.Row]] = [:]
        var importantByCategory: [String: [CommitteePointPresentation.Row]] = [:]
        var checkingByCategory: [String: [CommitteePointPresentation.Row]] = [:]
        var importantCounts: [String: Int] = [:]
        rows.reserveCapacity(presentation.ordered.count)
        grouped.reserveCapacity(categoryTitles.count + 1)
        importantByCategory.reserveCapacity(categoryTitles.count + 1)
        checkingByCategory.reserveCapacity(categoryTitles.count + 1)

        for row in presentation.ordered {
            if let selectedPages, pagesByPassage[row.id, default: []].isDisjoint(with: selectedPages) { continue }
            guard PointDisplayFilter.matches(row, pages: nil, reviewFilter: reviewFilter,
                                             annotation: annotation) else { continue }
            rows.append(row)
            let categoryID = categoryIDsByPassage[row.id, default: CommitteeCategory.unassignedID]
            grouped[categoryID, default: []].append(row)
            switch row.assessment.rating {
            case .important:
                importantByCategory[categoryID, default: []].append(row)
                importantCounts[categoryID, default: 0] += 1
            case .uncertain, .unassessed:
                checkingByCategory[categoryID, default: []].append(row)
            case .relevant, .other:
                break
            }
        }

        let definitions = CommitteeCategory.categories(for: purpose)
        let orderedIDs = definitions.map(\.id) + [CommitteeCategory.unassignedID]
        let categoryGroups = orderedIDs.compactMap { id -> CommitteeDisplayPresentation.CategoryGroup? in
            guard let members = grouped[id], !members.isEmpty else { return nil }
            return CommitteeDisplayPresentation.CategoryGroup(
                id: id,
                title: id == CommitteeCategory.unassignedID ? CommitteeCategory.unassignedTitle : (categoryTitles[id] ?? id),
                rows: members,
                importantCount: importantCounts[id, default: 0])
        }
        let mainGroups = categoryGroups.compactMap { group -> CommitteeDisplayPresentation.CategoryGroup? in
            guard let members = importantByCategory[group.id], !members.isEmpty else { return nil }
            return .init(id: group.id, title: group.title, rows: members, importantCount: group.importantCount)
        }
        let checkingGroups = categoryGroups.compactMap { group -> CommitteeDisplayPresentation.CategoryGroup? in
            guard let members = checkingByCategory[group.id], !members.isEmpty else { return nil }
            return .init(id: group.id, title: group.title, rows: members, importantCount: group.importantCount)
        }
        return Filtered(rows: rows, categoryGroups: categoryGroups, mainGroups: mainGroups,
                        checkingGroups: checkingGroups)
    }
}
