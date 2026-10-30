import XCTest
@testable import FolianceApp

final class WorkspaceSourceIssueEnglishTests: XCTestCase {
    func testIssueTitlesUseEnglishForEveryKind() {
        let unreadable = WorkspaceSourceIssue(page: 2, kind: .unreadable, notice: "")
        let region = WorkspaceSourceIssue(page: 3, kind: .limitedRegion, notice: "")
        let ocr = WorkspaceSourceIssue(page: 4, kind: .ocr, notice: "")

        XCTAssertEqual(unreadable.title, "Not included · PDF page 2")
        XCTAssertEqual(region.title, "Selected text region · PDF page 3")
        XCTAssertEqual(ocr.title, "Check image table · PDF page 4")
    }

    func testLegacyAndEnglishRegionAndOCRNoticesAreClassified() throws {
        let notices = [
            PageReading(text: "Text", notice: "Alleen het handmatig aangewezen tekstgebied is meegenomen."),
            PageReading(text: "Text", notice: "Only the manually selected text region was included."),
            PageReading(text: "Text", notice: "Afbeeldingstabel met OCR gelezen. Controleer de cellen."),
            PageReading(text: "Text", notice: "An image table was read with OCR. Check the cells."),
            PageReading(text: "Text", notice: "Image table was read with OCR. Check the cells.")
        ]
        let issues = WorkspaceSourceIssue.make(readings: notices)

        XCTAssertEqual(issues.count, notices.count)
        let values = try XCTUnwrap(issues.count == 5 ? issues : nil)
        func isRegion(_ issue: WorkspaceSourceIssue) -> Bool {
            if case .limitedRegion = issue.kind { return true }; return false
        }
        func isOCR(_ issue: WorkspaceSourceIssue) -> Bool {
            if case .ocr = issue.kind { return true }; return false
        }
        XCTAssertTrue(isRegion(values[0]), "Legacy Dutch region notice should be recognized")
        XCTAssertTrue(isRegion(values[1]), "English region notice should be recognized")
        XCTAssertTrue(isOCR(values[2]), "Legacy Dutch OCR notice should be recognized")
        XCTAssertTrue(isOCR(values[3]), "English OCR notice with an article should be recognized")
        XCTAssertTrue(isOCR(values[4]), "English OCR notice without an article should be recognized")
    }

    func testLegacyExactAndCompositeNoticesTranslateWithoutLosingMeaning() {
        let legacyOCR = "Afbeeldingstabel met OCR gelezen. Controleer de herkende cellen in Tabellen; deze zijn niet in de AI-analyse opgenomen."
        XCTAssertEqual(
            WorkspaceSourceIssue.englishNotice(legacyOCR),
            "An image table was read with OCR. Check the recognized cells in Tables; it was not included in AI analysis."
        )

        let composite = "Alleen het handmatig aangewezen tekstgebied is meegenomen. Afbeeldingstabel met OCR gelezen. Controleer de herkende cellen in Tabellen; deze zijn niet in de AI-analyse opgenomen."
        XCTAssertEqual(
            WorkspaceSourceIssue.englishNotice(composite),
            "Only the manually selected text region was included. An image table was read with OCR. Check the recognized cells in Tables; it was not included in AI analysis."
        )
        XCTAssertEqual(
            WorkspaceSourceIssue.englishNotice("Pagina niet leesbaar."),
            "This PDF page could not be read."
        )
    }

    func testUnknownNoticeRemainsUnchanged() {
        let notice = "An unfamiliar saved notice with source-specific wording."
        XCTAssertEqual(WorkspaceSourceIssue.englishNotice(notice), notice)
    }
}
