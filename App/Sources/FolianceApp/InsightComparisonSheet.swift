import SwiftUI
import FolianceCore

struct InsightComparisonSheet: View {
    let points: [Insight]
    let showSource: (Insight, Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var firstID = ""
    @State private var secondID = ""

    private var first: Insight? { points.first { $0.id == firstID } }
    private var second: Insight? { points.first { $0.id == secondID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.text("Vergelijk bestaande punten"))
                .font(.title2.weight(.semibold))
            Text(UIStrings.text("Kies twee punten. De tekst, passage en bron blijven afzonderlijk; er wordt geen gecombineerde uitleg gemaakt."))
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                pointPicker(title: "Eerste punt", selection: $firstID)
                pointPicker(title: "Tweede punt", selection: $secondID)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    if let first { comparisonColumn(first) }
                    if let second { comparisonColumn(second) }
                }
            }
            HStack { Spacer(); Button(UIStrings.text("Gereed")) { dismiss() }.buttonStyle(FocusSecondaryButtonStyle()).keyboardShortcut(.cancelAction) }
        }
        .padding(22).frame(minWidth: 720, minHeight: 500)
        .onAppear {
            if firstID.isEmpty { firstID = points.first?.id ?? "" }
            if secondID.isEmpty { secondID = points.dropFirst().first?.id ?? firstID }
        }
        .onChange(of: firstID) { _, newValue in if secondID == newValue { secondID = points.first(where: { $0.id != newValue })?.id ?? newValue } }
        .onChange(of: secondID) { _, newValue in if firstID == newValue { firstID = points.first(where: { $0.id != newValue })?.id ?? newValue } }
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private func pointPicker(title: String, selection: Binding<String>) -> some View {
        FocusMenuPicker(UIStrings.text(title), selection: selection,
                        selectedTitle: UIStrings.text(points.first { $0.id == selection.wrappedValue }.map { "\($0.title) · p. \($0.page)" } ?? "Kies een punt")) {
                ForEach(points) { point in
                    Text("\(point.title) · p. \(point.page)").tag(point.id)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func comparisonColumn(_ point: Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(point.title).font(.headline)
            Text(point.summary).font(.callout).textSelection(.enabled)
            if !point.relevance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(UIStrings.text("Oorspronkelijke duiding" )).font(.caption.weight(.semibold))
                Text(point.relevance).font(.callout).textSelection(.enabled)
            }
            if !point.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(UIStrings.text("Open vraag" )).font(.caption.weight(.semibold))
                Text(point.question).font(.callout).textSelection(.enabled)
            }
            Divider()
            Text(UIStrings.text("Oorspronkelijke passage" )).font(.caption.weight(.semibold))
            Text(point.quote).font(.callout).textSelection(.enabled)
            Button(UIStrings.text("Open bron op PDF-pagina \(point.page)")) {
                showSource(point, point.page, point.quote)
            }.buttonStyle(FocusQuietActionStyle())
            ForEach(Array((point.otherSources ?? []).enumerated()), id: \.offset) { _, source in
                Text(source.quote).font(.callout).textSelection(.enabled)
                Button(UIStrings.text("Open aanvullende bron op pagina \(source.page)")) {
                    showSource(point, source.page, source.quote)
                }.buttonStyle(FocusQuietActionStyle())
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
