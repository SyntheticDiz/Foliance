import AppKit
import SwiftUI

struct ChartAnalysisView: View {
    let selected: SelectedChart
    let initialExplanation: ChartExplanation?
    let onExplanation: ((ChartExplanation) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var explanation: ChartExplanation?
    @State private var error: String?
    @State private var busy = false
    @State private var analysisTask: Task<Void, Never>?

    init(selected: SelectedChart, initialExplanation: ChartExplanation? = nil,
         onExplanation: ((ChartExplanation) -> Void)? = nil) {
        self.selected = selected
        self.initialExplanation = initialExplanation
        self.onExplanation = onExplanation
        _explanation = State(initialValue: initialExplanation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(UIStrings.text("Diagram uitgelegd · PDF-pagina \(selected.page)"), systemImage: "chart.bar.xaxis")
                    .font(.title2.bold())
                Spacer()
                Button(UIStrings.text("Sluiten"), systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
            GeometryReader { geometry in
                Group {
                    if geometry.size.width >= 760 {
                        HSplitView { chartPreview; explanationPane }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                chartPreview.frame(height: min(geometry.size.height * 0.42, 250))
                                explanationContent
                            }
                        }
                    }
                }
            }
            Text(UIStrings.text("Controleer de uitleg altijd naast het oorspronkelijke diagram. Onleesbare cijfers worden niet als exacte waarden overgenomen."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(UIStrings.text("Sluiten")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 860, minHeight: 380, idealHeight: 620)
        .background(SPTheme.background)
        .task { if initialExplanation == nil { run() } }
        .onDisappear { analysisTask?.cancel() }
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private var chartPreview: some View {
        ScrollView {
            Image(nsImage: NSImage(cgImage: selected.image, size: .zero))
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(12)
        }
        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel(UIStrings.text("Geselecteerd diagram uit PDF-pagina \(selected.page)"))
    }

    private var explanationPane: some View {
        ScrollView { explanationContent }
            .frame(minWidth: 260, idealWidth: 420)
    }

    @ViewBuilder private var explanationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if busy { ProgressView(UIStrings.text("Diagram lokaal analyseren…")) }
            if let error {
                Label(UIStrings.text(error), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button(UIStrings.text("Opnieuw proberen")) { run() }.disabled(busy)
            }
            if let explanation {
                Button(UIStrings.text("Kopieer uitleg"), systemImage: "doc.on.doc") { copy(explanation) }
                Text(UIStrings.text(explanation.title.isEmpty ? explanation.kind.capitalized : explanation.title)).font(.title3.bold())
                Text(explanation.summary).textSelection(.enabled)
                if !explanation.observations.isEmpty {
                    Text(UIStrings.text("Wat laat het diagram zien?")).font(.headline)
                ForEach(explanation.observations, id: \.self) { value in Text("• " + value).textSelection(.enabled) }
                }
                if !explanation.visibleValues.isEmpty {
                    Text(UIStrings.text("Leesbare waarden")).font(.headline)
                ForEach(explanation.visibleValues, id: \.self) { value in Text("• " + value).textSelection(.enabled) }
                }
                Label(explanation.caution, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            if !busy && explanation == nil && error == nil {
                Text(UIStrings.text("De geselecteerde uitsnede wordt lokaal met Apple Intelligence geanalyseerd.")).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func run() {
        guard !busy else { return }
        busy = true; error = nil; explanation = nil
        analysisTask = Task {
            defer { busy = false }
            do {
                let result = try await ChartAnalysisService.analyze(selected.image)
                guard !Task.isCancelled else { return }
                explanation = result
                onExplanation?(result)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }

    private func copy(_ explanation: ChartExplanation) {
        var sections = ["Chart · PDF page \(selected.page)", explanation.title, explanation.summary]
        if !explanation.observations.isEmpty {
            sections.append("What the chart shows\n" + explanation.observations.map { "• " + $0 }.joined(separator: "\n"))
        }
        if !explanation.visibleValues.isEmpty {
            sections.append("Readable values\n" + explanation.visibleValues.map { "• " + $0 }.joined(separator: "\n"))
        }
        sections.append(explanation.caution)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sections.joined(separator: "\n\n"), forType: .string)
    }
}
