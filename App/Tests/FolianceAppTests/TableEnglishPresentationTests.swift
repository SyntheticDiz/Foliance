import XCTest
@testable import FolianceApp

final class TableEnglishPresentationTests: XCTestCase {
    func testGeneratedTableCopyIsEnglishAndSourceTextRemainsVerbatim() throws {
        let sourceNote = "Brontekst: bedragen volgens de leverancier."
        let table = DocumentTable(
            id: "fictional-project-costs",
            title: "Project costs in euros",
            pages: [4],
            headers: ["Work item", "2026", "2027"],
            rows: [["Site preparation", "1.250", "2.500"]],
            notes: [sourceNote],
            reliable: true
        )

        XCTAssertEqual(table.overview, "This table contains 1 data row, including any subtotals and totals. Columns: 2026, 2027. Key reading points follow.")
        let change = try XCTUnwrap(table.bullets.first)
        XCTAssertTrue(change.contains("Site preparation"))
        XCTAssertTrue(change.contains("from 1.250 in 2026 to 2.500 in 2027"))
        XCTAssertTrue(change.contains("increases by 1,250 euros"))
        XCTAssertEqual(table.notes, [sourceNote])
        XCTAssertEqual(table.cautions.first, sourceNote)
        XCTAssertTrue(table.cautions.last?.hasPrefix("Differences do not explain their cause.") == true)
        XCTAssertTrue(table.rows[0].contains("1.250"), "Cell text remains unchanged for source review.")
    }

    func testOCRAndUncertainTableExplanationsAreEnglish() {
        let table = DocumentTable(
            id: "fictional-ocr-table",
            title: "Project schedule",
            pages: [2],
            headers: ["Milestone", "Date"],
            rows: [["Design review", "2027-03"]],
            notes: [],
            reliable: false,
            recognizedWithOCR: true
        )

        XCTAssertTrue(table.overview.hasPrefix("Local OCR recognized 1 row and 2 columns."))
        XCTAssertTrue(table.overview.contains("Check the recognized cells against the source."))
        XCTAssertTrue(table.bullets.first?.contains("Check the original table") == true)
        XCTAssertTrue(table.cautions.first?.hasPrefix("Table recognition is uncertain:") == true)
        XCTAssertTrue(table.cautions.contains { $0.hasPrefix("Blank cells were not treated as zero.") })
    }
}
