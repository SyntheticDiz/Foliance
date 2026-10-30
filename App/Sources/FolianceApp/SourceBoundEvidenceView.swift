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
                    Text("Full source context").font(.title2.bold())
                    Text(UIStrings.text("All available extracted text from the source pages, with one page before and after. This does not prove that PDF text extraction includes every visible element."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }.padding(20)
            Divider()
            if let context {
                if context.verifiedQuote == nil {
                    Label(UIStrings.text("Source not verified: the quote is empty or does not appear verbatim on the stated physical PDF page."), systemImage: "exclamationmark.triangle")
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
                                Text(page.text.isEmpty ? UIStrings.text("No text was extracted from this page.") : page.text)
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
                    Text(UIStrings.text("Source not verified: the stated page is outside this document."))
                        .font(.callout).foregroundStyle(.secondary)
                    let pdfPage = min(max(1, item.page), max(1, pages.count))
                    Button("Show in PDF · p. \(pdfPage)", systemImage: "doc.text.magnifyingglass") {
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
        Text("PDF page \(page.physicalPage) · full available page")
            .font(.headline)
    }

    private func pageActions(_ page: SourceBoundEvidence.PageContext) -> some View {
        HStack(spacing: 8) {
            Button(UIStrings.text("Show in PDF"), systemImage: "doc.text.magnifyingglass") {
                openPDF(page.physicalPage)
            }.buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small)
            Button("Copy page text", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(page.text, forType: .string)
            }.buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small)
        }
    }
}
