import XCTest
@testable import FolianceCore

final class AnalysisTests: XCTestCase {
    func testPageReferencesIncludeEmptyPages() {
        let findings = Analyzer.analyze(pages: ["", "The cost estimate is 500 euros."])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.page, 2)
        XCTAssertEqual(findings.first?.excerpt, "The cost estimate is 500 euros.")
        XCTAssertEqual(findings.first?.theme, "Costs")
    }

    func testGeneralThemesFindActionsCostsDatesRisksAndDecisionsWithoutChangingEvidence() {
        let text = "The findings report a supplier risk. The owner is explicitly assigned to review it by the stated deadline of 30 June 2027. The estimated cost is 12,000 euros; the team committed to finish the work, but approval is not confirmed."
        let findings = Analyzer.analyze(pages: ["", text])
        let themes = Set(findings.map(\.theme))
        XCTAssertEqual(themes, Set(Theme.defaults.map(\.id).filter { $0 != "Context" }))
        XCTAssertTrue(findings.allSatisfy { $0.page == 2 && $0.excerpt == text })
        XCTAssertTrue(findings.allSatisfy { !$0.question.isEmpty && !$0.matchedKeywords.isEmpty })
    }

    func testEnglishAndDutchCuesAreRecognizedCaseInsensitivelyAcrossPDFLineWraps() {
        let findings = Analyzer.analyze(pages: ["KOSTEN\nare capped at 2,000 euros. Risks and termijnen remain under review."])
        XCTAssertEqual(Set(findings.map(\.theme)), Set(["Costs", "Risks", "Deadlines"]))
    }

    func testNoSubstringFalsePositive() {
        XCTAssertTrue(Analyzer.analyze(pages: ["The patterner is ordinarily useful."]).isEmpty)
    }

    func testNegatedProposalRemainsLiteralAndDoesNotBecomeAConfirmedDecision() {
        let text = "No proposed action was confirmed."
        let findings = Analyzer.analyze(pages: [text])
        XCTAssertEqual(Set(findings.map(\.theme)), Set(["Decisions", "Actions"]))
        XCTAssertTrue(findings.allSatisfy { $0.excerpt == text })
        XCTAssertTrue(findings.first(where: { $0.theme == "Decisions" })?.question.contains("proposed") == true)
    }
}
