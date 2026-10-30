import SwiftUI

/// Opens saved answers; viewing this list never starts a model request.
struct SavedWorkspaceExtrasView: View {
    let threads: [SavedChatThread]
    let charts: [SavedChartAnalysis]
    var summaries: [SavedSelectionSummary] = []
    var openSummary: (SavedSelectionSummary) -> Void = { _ in }
    let openThread: (SavedChatThread) -> Void
    let openChart: (SavedChartAnalysis) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(UIStrings.text("Bewaarde antwoorden")).font(.title2.weight(.semibold))
                Spacer()
                Button(UIStrings.text("Sluiten")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(UIStrings.text("Deze antwoorden zijn bewaard. Openen vraagt geen nieuwe AI-analyse."))
                .font(.callout).foregroundStyle(.secondary)
            List {
                if !threads.isEmpty {
                    Section(UIStrings.text("Gesprekken")) {
                        ForEach(threads.reversed()) { thread in
                            Button { openThread(thread) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thread.messages.first(where: \.isUser)?.text ?? UIStrings.text("Documentchat"))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text(UIStrings.text(thread.wholeDocument ? "Hele document" : "PDF-pagina’s " + thread.pages.map(String.init).joined(separator: ", ")) + " · " + AIConfiguration.label(thread.model))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !summaries.isEmpty {
                    Section(UIStrings.text("Selectiesamenvattingen")) {
                        ForEach(summaries.reversed()) { saved in
                            Button { openSummary(saved) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(saved.summary).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(UIStrings.text(saved.selection.pageLabel)).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !charts.isEmpty {
                    Section(UIStrings.text("Diagramuitleg")) {
                        ForEach(charts.reversed()) { chart in
                            Button { openChart(chart) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chart.explanation.title.isEmpty ? UIStrings.text("Diagramuitleg") : chart.explanation.title)
                                        .lineLimit(2)
                                    Text(UIStrings.text("PDF-pagina \(chart.page)"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(24).frame(minWidth: 460, idealWidth: 620, minHeight: 360, idealHeight: 500)
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
