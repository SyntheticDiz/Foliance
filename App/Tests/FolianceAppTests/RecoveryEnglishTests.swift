import XCTest
@testable import FolianceApp

final class RecoveryEnglishTests: XCTestCase {
    func testFixedAppleFailuresHaveEnglishDescriptionsAndUnknownDetailsStayVerbatim() throws {
        XCTAssertEqual(try XCTUnwrap(AppleFailure.context.errorDescription), "Apple Intelligence ran out of room for the source and response.")
        XCTAssertEqual(try XCTUnwrap(AppleFailure.refusal.errorDescription), "Apple Intelligence declined this content. This part was not processed.")
        XCTAssertEqual(try XCTUnwrap(AppleFailure.temporary.errorDescription), "Apple Intelligence is temporarily busy or did not respond in time.")
        XCTAssertEqual(try XCTUnwrap(AppleFailure.unavailable.errorDescription), "Apple Intelligence or the required language or model files are unavailable.")
        XCTAssertEqual(try XCTUnwrap(AppleFailure.invalid.errorDescription), "AI returned invalid output or unknown source references.")

        let detail = "A provider supplied this error without translation."
        XCTAssertEqual(AppleFailure.other(detail).errorDescription, detail)
    }

    func testIncompleteAppleAnalysisUsesEnglishTemplateAndPreservesIssueDetails() throws {
        let issue = "Geïmporteerde bronmelding blijft behouden."
        let failure = AppleAnalysisIncomplete(points: [], completed: 2, total: 5, issues: [issue])
        XCTAssertEqual(try XCTUnwrap(failure.errorDescription), "Analysis incomplete: processed 2 of 5 steps.\n\(issue)")
    }

    func testFailureTitlesAndExplanationsAreEnglishForEveryCode() {
        let codes: [CommitteeFailurePresentation.FailureCode] = [
            .legacyUnknown, .notAttempted, .noDecision, .invalidRating,
            .missingReason, .missingQuote, .quoteMismatch, .requestFailure
        ]
        let titles = [
            "Cause not recorded", "Not processed", "No decision returned", "Unrecognized rating returned",
            "Explanation missing", "Source quote missing", "Source quote not found", "Processing failed"
        ]
        let explanations = [
            "An earlier version saved only a general error message, so the exact cause is no longer known.",
            "No response has been processed for these passages yet.",
            "AI did not return a usable decision. The passage remains available and is not marked as unimportant.",
            "The response did not contain a recognized rating.",
            "The response did not include an explanation for the rating.",
            "The response did not include a literal quote from the assessed passage.",
            "The supplied quote could not be matched safely to the original passage. Source verification was not relaxed.",
            "Processing did not return a usable response. See the saved message for this passage."
        ]

        XCTAssertEqual(codes.map(CommitteeFailurePresentation.title), titles)
        XCTAssertEqual(codes.map(CommitteeFailurePresentation.explanation), explanations)
    }

    func testReviewRecoveryActionsUseEnglishForMissingStaleCompleteAndIncompleteReview() {
        let incomplete = CommitteeAssessmentService.Review(purpose: .bestuur, model: "current", inputKey: "key",
                                                           entries: [], issues: [], complete: false)
        let complete = CommitteeAssessmentService.Review(purpose: .bestuur, model: "current", inputKey: "key",
                                                          entries: [], issues: [], complete: true)
        let stale = CommitteeAssessmentService.Review(purpose: .bestuur, model: "old", inputKey: "key",
                                                       entries: [], issues: [], complete: true)

        XCTAssertEqual(CommitteeFailurePresentation.actionTitle(review: nil, model: "current"), "Review this profile")
        XCTAssertEqual(CommitteeFailurePresentation.actionTitle(review: incomplete, model: "current"), "Resume profile review")
        XCTAssertEqual(CommitteeFailurePresentation.actionTitle(review: complete, model: "current"), "Refresh profile review")
        XCTAssertEqual(CommitteeFailurePresentation.actionTitle(review: stale, model: "current"), "Review with current model")
    }
}
