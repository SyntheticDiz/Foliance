import SwiftUI
import PDFKit

/// Read-only rendering of the tutorial's real PDF page. PDFKit supplies both the
/// pixels and the text-selection bounds; only the interaction is simulated.
struct TutorialPDFPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let data: Data
    let page: Int
    let highlight: String?
    let selectionColor: Color
    @ObservedObject var controls: PDFControls
    var selectionProgress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            if let pdf = PDFDocument(data: data), let pdfPage = pdf.page(at: page - 1) {
                let media = pdfPage.bounds(for: .mediaBox)
                // Fit to the card's width, as PDFPreview does; show the top of the
                // page instead of shrinking an entire A4 page into a short demo.
                let scale = geometry.size.width / media.width
                let width = media.width * scale
                let height = media.height * scale
                let left = (geometry.size.width - width) / 2
                let top: CGFloat = 0
                Image(nsImage: pdfPage.thumbnail(of: CGSize(width: media.width * 2, height: media.height * 2), for: .mediaBox))
                    .resizable().interpolation(.high)
                    .frame(width: width, height: height)
                    .position(x: left + width / 2, y: top + height / 2)
                if let highlight,
                   let selection = PDFPassageLocator.selection(in: pdf, page: page, quote: highlight) {
                    let bounds = selection.bounds(for: pdfPage)
                    ZStack(alignment: .leading) {
                        Color.clear
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectionColor.opacity(0.38))
                            .frame(width: bounds.width * scale * selectionProgress)
                    }
                        .frame(width: bounds.width * scale, height: bounds.height * scale)
                        .position(x: left + (bounds.midX - media.minX) * scale,
                                  y: top + (media.maxY - bounds.midY) * scale)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.15), value: selectionProgress)
                        .transition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: highlight)
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .bottom) { PDFControlsBar(controls: controls).scaleEffect(0.82).padding(.bottom, 12) }
        .tutorialTarget("pdfPane")
    }
}
