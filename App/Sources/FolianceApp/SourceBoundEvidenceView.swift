import AppKit
import SwiftUI

struct SourceBoundEvidenceView: View {
    let item: SourceHighlights.Item
    let pages: [String]
    let showSource: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var context: SourceBoundEvidence.Context? {
        SourceBoundEvidence.context(item: item, pages: pages)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UIStrings.text("Volledige broncontext")).font(.title2.bold())
                    Text(UIStrings.text("De volledige beschikbare geëxtraheerde tekst van alle bronpagina’s, met één pagina ervoor en erna. Dit bewijst niet dat de PDF-tekstextractie elk zichtbaar element bevat."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(UIStrings.text("Sluit")) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }.padding(20)
            Divider()
            if let context {
                if context.verifiedQuote == nil {
                    Label(UIStrings.text("Bron niet geverifieerd: het citaat is leeg of komt niet letterlijk voor op de opgegeven fysieke PDF-pagina."), systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(context.pages) { page in
                            VStack(alignment: .leading, spacing: 10) {
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        pageHeading(page)
                                        Spacer(minLength: 8)
                                        pageActions(page)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        pageHeading(page)
                                        pageActions(page)
                                    }
                                }
                                Text(page.text.isEmpty ? UIStrings.text("Geen geëxtraheerde tekst op deze pagina.") : page.text)
                                    .font(.body).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.padding(20)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text("Bron niet geverifieerd: de opgegeven pagina valt buiten dit document."))
                        .font(.callout).foregroundStyle(.secondary)
                    let pdfPage = min(max(1, item.page), max(1, pages.count))
                    Button(UIStrings.text("Toon in PDF · p. \(pdfPage)"), systemImage: "doc.text.magnifyingglass") {
                        openPDF(pdfPage)
                    }.buttonStyle(FocusSecondaryButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(20)
            }
        }
        .frame(minWidth: 620, idealWidth: 920, minHeight: 420, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private func openPDF(_ page: Int) {
        dismiss()
        DispatchQueue.main.async { showSource(page, "") }
    }

    private func pageHeading(_ page: SourceBoundEvidence.PageContext) -> some View {
        Text(UIStrings.text("PDF-pagina \(page.physicalPage) · volledige beschikbare pagina"))
            .font(.headline)
    }

    private func pageActions(_ page: SourceBoundEvidence.PageContext) -> some View {
        HStack(spacing: 8) {
            Button(UIStrings.text("Toon in PDF"), systemImage: "doc.text.magnifyingglass") {
                openPDF(page.physicalPage)
            }.buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small)
            Button(UIStrings.text("Kopieer paginatekst"), systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(page.text, forType: .string)
            }.buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small)
        }
    }
}
