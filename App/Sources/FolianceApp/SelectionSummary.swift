import SwiftUI

struct SelectedPDFText: Equatable, Codable, Sendable {
    let text: String
    let pages: [Int]
    let sources: [ChosenPassage.Source]
    init(text: String, pages: [Int], sources: [ChosenPassage.Source] = []) {
        self.text = text
        self.pages = pages
        self.sources = sources
    }
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
    var pageLabel: String { "PDF-pagina’s " + pages.map(String.init).joined(separator: ", ") }
}

@MainActor final class SelectionSummary: ObservableObject {
    var summarizeDocument = SummaryService.generate
    var onSummary: ((SavedSelectionSummary) -> Void)?
    @Published var selection: SelectedPDFText?
    @Published var summary = ""
    @Published var status = ""
    @Published var error: String?
    @Published var busy = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var retryModel: String?
    @discardableResult func start(_ selection: SelectedPDFText, model: String) -> Task<Void, Never> {
        close()
        self.selection = selection; retryModel = model; busy = true; status = "Selectie samenvatten…"
        let id = generation
        task = Task {
            do {
                let result = try await summarizeDocument([selection.text], model) { current, total in
                    await MainActor.run {
                        guard self.generation == id else { return }
                        self.status = current == 0 ? "Samenvatting samenvoegen…" : "Selectie samenvatten: deel \(current) van \(total)…"
                    }
                }
                try Task.checkCancellation()
                guard generation == id else { return }
                summary = result.digest.overview; error = result.incompleteNotice
                onSummary?(SavedSelectionSummary(selection: selection, summary: result.digest.overview,
                                                 notice: result.incompleteNotice, model: model))
            } catch {
                guard generation == id else { return }
                self.error = Task.isCancelled ? "Samenvatten gestopt." : error.localizedDescription
            }
            if generation == id { busy = false }
        }
        return task!
    }
    @discardableResult func retry() -> Task<Void, Never>? {
        guard !busy, let selection, let retryModel else { return nil }
        return start(selection, model: retryModel)
    }
    func restore(_ saved: SavedSelectionSummary) {
        task?.cancel()
        generation = UUID()
        task = nil
        selection = saved.selection
        summary = saved.summary
        error = saved.notice
        retryModel = saved.model
        status = ""
        busy = false
    }
    func stop() { task?.cancel() }
    func close() { task?.cancel(); generation = UUID(); selection = nil; summary = ""; error = nil; retryModel = nil; busy = false }
}

struct SelectionSummaryCard: View {
    @ObservedObject var session: SelectionSummary
    var body: some View {
        if let selection = session.selection {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(UIStrings.text("Samenvatting van je selectie")).font(.headline)
                    Spacer()
                    Button(UIStrings.text("Sluiten"), systemImage: "xmark") { session.close() }
                        .buttonStyle(FocusQuietActionStyle())
                }
                Text(UIStrings.text(selection.pageLabel) + " · \(selection.wordCount) " + UIStrings.text("woorden geselecteerd")).font(.caption).foregroundStyle(.secondary)
                if session.busy {
                    HStack { ProgressView().controlSize(.small); Text(UIStrings.text(session.status)); Spacer(); Button(UIStrings.text("Stop")) { session.stop() }.buttonStyle(FocusQuietActionStyle()) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !session.summary.isEmpty { Text(session.summary).textSelection(.enabled) }
                        if let error = session.error {
                            Text(error).foregroundStyle(.orange).textSelection(.enabled)
                            if !session.busy { Button(UIStrings.text("Opnieuw proberen")) { session.retry() }.buttonStyle(FocusSecondaryButtonStyle()) }
                        }
                        DisclosureGroup(UIStrings.text("Bekijk geselecteerde tekst")) { Text(selection.text).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }.font(.body).lineSpacing(5).padding(20)
                .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20)
                .buttonStyle(FocusSecondaryButtonStyle())
        }
    }
}
