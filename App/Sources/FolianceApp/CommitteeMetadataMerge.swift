import Foundation

/// A category-only result can never replace an importance judgment or source.
enum CommitteeMetadataMerge {
    static func applying(_ update: CommitteeAssessmentService.Review, to original: CommitteeAssessmentService.Review) -> CommitteeAssessmentService.Review? {
        guard update.purpose == original.purpose, update.model == original.model,
              update.inputKey == original.inputKey, update.entries.count == original.entries.count else { return nil }
        var result = original
        for index in original.entries.indices {
            let previous = original.entries[index], incoming = update.entries[index]
            guard previous.passageID == incoming.passageID,
                  previous.sources.count == incoming.sources.count,
                  zip(previous.sources, incoming.sources).allSatisfy({ $0.page == $1.page && Data($0.quote.utf8) == Data($1.quote.utf8) }) else { return nil }
            // Preserve all base fields even if a future classifier accidentally returns different ones.
            result.entries[index].primaryCategoryID = CommitteeCategorizationService.validatedPrimaryCategoryID(for: incoming, purpose: original.purpose)
            result.entries[index].secondaryCategoryIDs = CommitteeCategorizationService.validatedSecondaryCategoryIDs(for: incoming, purpose: original.purpose)
            result.entries[index].categoryModel = incoming.categoryModel
        }
        return result
    }
}
