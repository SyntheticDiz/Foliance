import XCTest
import PDFKit
@testable import FolianceApp

@MainActor final class NativeReviewFixtureTests: XCTestCase {
    func testFictionalPDFRoundTripAndExportPreserveSourcesWithoutAI() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document = try OpenPDF.read(root.appendingPathComponent("AppStore/Sample.pdf"))
        XCTAssertTrue(document.pages.joined().contains("Project Lantern"))
        let text = try XCTUnwrap(document.pages.first)
        let workspace = SimpleWorkspace()
        workspace.loadProgram = { nil }
        workspace.document = document
        workspace.insights = [.init(title: "Prepared review sample — not AI output", summary: "This fictional proposal estimates EUR 18,000. No purchase has been authorized.", relevance: "", question: "Does the lighting estimate include electrical work?", quote: text, page: 1)]
        workspace.documentSummary = .init(digest: .init(overview: "Prepared review sample — not AI output. A fictional team is reviewing a reading-room proposal. Costs and delivery depend on confirmation.", bullets: ["The budget is an estimate.", "No purchase has been authorized."]), sections: [])
        workspace.analyzed = true
        workspace.neutralAnalysis = true
        workspace.analysisState = .complete
        workspace.focus = "Inspect costs and conditional commitments"
        let archive = try workspace.archive(readingPage: 1)
        try archive.validate()
        let restored = try JSONDecoder().decode(WorkspaceArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(restored.pdf, document.data)
        XCTAssertEqual(restored.insights.first?.quote, text)
        XCTAssertEqual(restored.focus, workspace.focus)
        let exported = try await BriefingPDF.render(document: document, insights: restored.insights, analyzed: true, neutral: true, includeSources: true)
        let output = try XCTUnwrap(PDFDocument(data: exported))
        let rendered = (output.string ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        XCTAssertTrue(rendered.contains("No purchase has been authorized"))
        XCTAssertTrue(rendered.contains("Project Lantern"))
        if let destination = ProcessInfo.processInfo.environment["FOLIANCE_NATIVE_REVIEW_FIXTURE"] {
            let url = URL(fileURLWithPath: destination)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try archive.write(url)
        }
    }
}
