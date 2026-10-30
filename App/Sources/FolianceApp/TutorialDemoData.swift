import AppKit
import CoreText
import PDFKit

/// In-memory example data for the tutorial. It is never loaded from or written to the user's files.
@MainActor enum TutorialDemoData {
    static let quote = "The project team proposes a quiet reading room on the second floor."
    static let pages = [
        "Workspace refresh proposal. The team is exploring a quiet reading room for staff and visitors.",
        "The room would use an existing space beside the main stairwell. Opening hours are still being discussed.",
        "The initial cost estimate is 18,000 euros. The estimate is preliminary and excludes future maintenance.",
        quote + " A final layout will be prepared after accessibility feedback.",
        "If approved, the room could open in September. The schedule depends on ordering furniture.",
        "Initial estimate. Furniture: 12,000 euros. Lighting: 6,000 euros. Total: 18,000 euros."
    ]

    static let insight = Insight(
        title: "A quiet reading room is proposed",
        summary: "The project team proposes adapting an existing room. The layout and schedule are not final.",
        relevance: "", question: "Which costs are not included in the estimate?",
        quote: quote, page: 4)

    static func makeWorkspace() -> SimpleWorkspace {
        let workspace = SimpleWorkspace()
        workspace.document = OpenPDF(name: "Workspace-refresh.pdf", data: pdfData(), pages: pages, findings: [])
        workspace.showsWelcome = false
        workspace.page = 4
        workspace.status = "Processing complete"
        workspace.analyzed = true
        workspace.neutralAnalysis = true
        workspace.analysisState = .complete
        workspace.insights = [insight]
        workspace.keyPointsReady = true
        workspace.keyPoints = [
            .init(kind: .decisions, page: 4, quote: quote, title: "Reading room proposal", decisionStatus: "Proposal", importance: 1),
            .init(kind: .amounts, page: 3, quote: "The initial cost estimate is 18,000 euros.", title: "Initial estimate: €18,000", importance: 1),
            .init(kind: .dates, page: 5,
                  quote: "If approved, the room could open in September. The schedule depends on ordering furniture.",
                  title: "Possible opening in September", importance: 1)
        ]
        workspace.documentSummary = DocumentSummary(
            digest: .init(overview: "The team is exploring a quiet reading room using an existing space. The proposal includes a preliminary estimate of €18,000 and a possible September opening.", bullets: ["The estimate excludes future maintenance; the layout and schedule are not final."]),
            sections: [
                .init(page: 3, digest: .init(overview: "The preliminary estimate is €18,000 and excludes future maintenance.", bullets: [])),
                .init(page: 4, digest: .init(overview: quote + " A final layout will follow accessibility feedback.", bullets: []))
            ])
        workspace.tables = [.init(id: "tutorial-table", title: "Initial estimate", pages: [6],
                                  headers: ["Item", "Amount"], rows: [["Furniture", "€12,000"], ["Lighting", "€6,000"], ["Total", "€18,000"]],
                                  notes: [], reliable: true)]
        return workspace
    }

    static func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        for (pageIndex, text) in pages.enumerated() {
            context.beginPDFPage(nil)
            for (lineIndex, line) in (["Fictional workspace project · PDF page \(pageIndex + 1)", ""] + text.components(separatedBy: ". ")).enumerated() {
                let content = line.hasSuffix(".") || line.isEmpty ? line : line + "."
                let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: content, attributes: attributes))
                context.textPosition = CGPoint(x: 48, y: 775 - lineIndex * 35)
                CTLineDraw(textLine, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
