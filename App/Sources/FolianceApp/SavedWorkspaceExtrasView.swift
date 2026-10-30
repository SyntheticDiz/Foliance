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
                Text(UIStrings.text("Saved answers")).font(.title2.weight(.semibold))
                Spacer()
                Button(UIStrings.text("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(UIStrings.text("These answers are saved. Opening them does not request a new AI analysis."))
                .font(.callout).foregroundStyle(.secondary)
            List {
                if !threads.isEmpty {
                    Section(UIStrings.text("Conversations")) {
                        ForEach(threads.reversed()) { thread in
                            Button { openThread(thread) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thread.messages.first(where: \.isUser)?.text ?? UIStrings.text("Document chat"))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text((thread.wholeDocument ? "Entire document" : "PDF pages " + thread.pages.map(String.init).joined(separator: ", ")) + " · " + AIConfiguration.label(thread.model))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if !summaries.isEmpty {
                    Section(UIStrings.text("Selection summaries")) {
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
                    Section(UIStrings.text("Chart explanation")) {
                        ForEach(charts.reversed()) { chart in
                            Button { openChart(chart) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chart.explanation.title.isEmpty ? UIStrings.text("Chart explanation") : chart.explanation.title)
                                        .lineLimit(2)
                                    Text("PDF page \(chart.page)")
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
