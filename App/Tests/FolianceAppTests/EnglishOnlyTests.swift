import XCTest
@testable import FolianceApp

final class EnglishOnlyTests: XCTestCase {
    func testLegacyDutchPreferenceAndExplicitLanguageArgumentCannotChangeInterfaceLanguage() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "uiLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "uiLanguage") }
            else { defaults.removeObject(forKey: "uiLanguage") }
        }

        defaults.set("nl", forKey: "uiLanguage")
        XCTAssertEqual(UIStrings.language, "en")
        XCTAssertFalse(UIStrings.isDutch)
        XCTAssertEqual(UIStrings.text("Referentiedocument", language: "nl"), "Reference document")
        XCTAssertEqual(UIStrings.text("Leesdoel", language: "nl"), "Reading goal")
        XCTAssertEqual(UIStrings.text("Reference document", language: "nl"), "Reference document")
    }

    func testGeneratedAnswersUseEnglishAndPreserveSourceQuotations() {
        XCTAssertEqual(AnalysisLanguage.code, "en")
        XCTAssertTrue(AnalysisLanguage.instruction.contains("Respond in English"))
        XCTAssertTrue(AnalysisLanguage.instruction.contains("Preserve source quotations exactly in their original language."))

        let quote = "De levering start op 14 mei, mits het budget is goedgekeurd."
        let note = "Controleer dit citaat met de projectleider."
        XCTAssertEqual(UIStrings.text(quote, language: "nl"), quote)
        XCTAssertEqual(UIStrings.text(note, language: "nl"), note)
    }

    func testExportAndAccessibilityLabelsResolveToEnglish() {
        XCTAssertEqual(UIStrings.text("Hele document"), "Entire document")
        XCTAssertEqual(UIStrings.text("Bron · PDF-pagina 4"), "Source · PDF page 4")
        XCTAssertEqual(UIStrings.text("Vouw de categorie uit of in"), "Expand or collapse the category")
        XCTAssertEqual(UIStrings.text("Vastgesteld besluit"), "Confirmed decision")
        XCTAssertEqual(UIStrings.text("Voorstel"), "Proposal")
    }

    @MainActor func testTutorialContentAndAnimatedCaptionsUseEnglishFictionalExamples() {
        XCTAssertEqual(TutorialStep.all.count, 12)
        XCTAssertEqual(TutorialStep.all[0].title, "Open a PDF")
        XCTAssertTrue(TutorialStep.all[0].action.contains("Add PDF…"))
        XCTAssertEqual(TutorialStep.all[9].title, "Understand tables and definitions")
        XCTAssertEqual(TutorialStep.all[11].tip,
                       "An export is a shareable PDF. Save a work document with ⌘S to continue later with your results and selection.")
        XCTAssertEqual(TutorialDemo.caption(step: 0, phase: 0), "Drop the PDF in the start area")
        XCTAssertEqual(TutorialDemo.caption(step: 11, phase: 3), "Review the export before saving")
        XCTAssertEqual(TutorialDemo.caption(step: 12, phase: 0), "Example ready")

        XCTAssertEqual(TutorialDemoData.quote,
                       "The project team proposes a quiet reading room on the second floor.")
        XCTAssertEqual(TutorialDemoData.pages[3].contains(TutorialDemoData.quote), true)
        XCTAssertEqual(TutorialDemoData.pages[4],
                       "If approved, the room could open in September. The schedule depends on ordering furniture.")
        XCTAssertEqual(TutorialDemoData.makeWorkspace().keyPoints[2].quote, TutorialDemoData.pages[4])
        XCTAssertTrue(TutorialStep.all[1].outcome.contains("only after you enable consent"))
        XCTAssertTrue(TutorialStep.all[1].outcome.contains("never switches providers automatically"))
    }

    func testWorkspaceStatusesAndErrorsHaveEnglishMappings() {
        XCTAssertEqual(UIStrings.text("PDF-export geannuleerd."), "PDF export canceled.")
        XCTAssertEqual(UIStrings.text("Werkdocument automatisch bewaard: Review.foliance"),
                       "Workspace saved automatically: Review.foliance")
        XCTAssertEqual(UIStrings.text("Selectie kon niet worden bewaard: Disk full"),
                       "Could not save selection: Disk full")
        XCTAssertEqual(UIStrings.text("Werk kon niet worden bewaard: Disk full"),
                       "Could not save work: Disk full")
        XCTAssertEqual(UIStrings.text("Deze PDF heeft geen leesbare tekstlaag. Maak eerst een doorzoekbare PDF met OCR (tekstherkenning) en importeer die opnieuw."),
                       "This PDF has no readable text layer. First create a searchable PDF with OCR (text recognition), then import it again.")
        XCTAssertEqual(UIStrings.text("Bron · PDF-pagina 4"), "Source · PDF page 4")
        XCTAssertEqual(UIStrings.text("Geen geëxtraheerde tekst op deze pagina."), "No text was extracted from this page.")
        XCTAssertEqual(UIStrings.text("Meer resultaten"), "More results")
    }

    func testSettingsDoNotOfferAnInterfaceLanguagePicker() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/FolianceApp/AppSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("uiLanguage"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("language picker"))
        XCTAssertTrue(source.contains("OpenAISettingsView()"))
        XCTAssertTrue(source.contains("On-device analysis"))
    }
}
