import SwiftUI

struct PassageQuestion: Codable, Sendable, Equatable {
    let question: String
    let quote: String
}

enum PassageQuestions {
    static func generate(passage: String, model: String, focus: String = "", existing: [PassageQuestion] = [], progress: @escaping ([PassageQuestion]) async -> Void = { _ in }, request: AIService.Request? = nil) async throws -> [PassageQuestion] {
        guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError(message: "This passage contains no readable text.") }
        if request == nil { _ = try await AIRouting.resolve(model) }
        return try await ApplePassageQuestions.generate(passage: passage, focus: focus, existing: existing, progress: progress,
                                                       request: request ?? AIService.response(for: model), useCache: request == nil && !AIConfiguration.isChatGPT(model))
    }

    /// Keep verified results through at most two repair attempts and through manual retries.
    static func complete(passage: String, existing: [PassageQuestion] = [], progress: ([PassageQuestion]) async -> Void = { _ in }, request: ([PassageQuestion]) async throws -> [PassageQuestion]) async throws -> [PassageQuestion] {
        func normalized(_ text: String) -> String {
            text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
        }
        var accepted: [PassageQuestion] = []
        func appendValid(_ candidates: [PassageQuestion]) {
            for candidate in candidates where accepted.count < 5 {
                let name = normalized(candidate.question)
                guard !name.isEmpty,
                      !accepted.contains(where: { normalized($0.question) == name }),
                      AIService.contains(quote: candidate.quote, page: 1, pages: [passage]) else { continue }
                accepted.append(candidate)
            }
        }
        appendValid(existing)
        for _ in 0..<3 where accepted.count < 5 {
            try Task.checkCancellation()
            do {
                appendValid(try await request(accepted))
                try Task.checkCancellation()
                await progress(accepted)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || error is ChatGPTError { throw error }
                if accepted.isEmpty { throw error }
                return accepted
            }
        }
        return accepted
    }

}

struct PassageActions: View {
    private let uiLanguage = "en"
    let passage: String
    let page: Int
    let model: String
    var focus: String = ""
    let showPage: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var showingQuestions = false
    @State private var questions: [PassageQuestion] = []
    @State private var loading = false
    @State private var notice: String?
    @State private var error: String?
    @State private var generation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack {
                        Text(UIStrings.text("Volledige passage")).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(UIStrings.text("PDF-pagina \(page)")).font(.caption).foregroundStyle(.secondary)
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityValue(UIStrings.text(expanded ? "Uitgeklapt" : "Ingeklapt"))
                    .help(UIStrings.text("Volledige passage tonen of verbergen"))
                Button { showingQuestions = true } label: { Image(systemName: "questionmark").frame(width: 28, height: 28) }
                    .buttonStyle(FocusSecondaryButtonStyle())
                    .help(UIStrings.text("Genereer vijf vragen met bronverwijzingen")).accessibilityLabel(UIStrings.text("Vijf vragen genereren"))
            }
            if expanded { fullPassage }
        }
        .sheet(isPresented: $showingQuestions, onDismiss: { generation?.cancel(); loading = false }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(UIStrings.text("Vragen bij de passage")).font(.title2.bold()); Spacer(); Button(UIStrings.text("Gereed")) { showingQuestions = false }.keyboardShortcut(.cancelAction) }
                Text(UIStrings.text("PDF-pagina \(page) · Vragen over de hele passage, met per vraag het bijbehorende broncitaat.")).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if loading { ProgressView(UIStrings.text("Vijf vragen genereren…")) }
                        if let error { Text(UIStrings.text(error)).foregroundStyle(.red) }
                        if let notice { Text(UIStrings.text(notice)).foregroundStyle(.secondary) }
                        if !loading && (error != nil || questions.count < 5) {
                            Button(UIStrings.text(questions.isEmpty ? "Probeer opnieuw" : "Vul ontbrekende vragen aan")) { generate() }
                        }
                        ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). \(question.question)").font(.headline)
                                Text(UIStrings.text("Bij deze passage: ‘\(question.quote)’")).font(.callout).foregroundStyle(.secondary)
                            }.textSelection(.enabled)
                        }
                        Divider()
                        fullPassage
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24).frame(width: 620, height: 620)
                .onAppear { if questions.isEmpty { generate() } }
                .buttonStyle(FocusSecondaryButtonStyle())
        }

    }

    private var fullPassage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(passage).textSelection(.enabled)
            Button(UIStrings.text("Toon in PDF · p. \(page)")) { showPage() }.buttonStyle(FocusQuietActionStyle())
        }
    }

    private func generate() {
        guard !loading else { return }
        loading = true; error = nil; notice = nil
        generation = Task { @MainActor in
            defer { loading = false }
            do {
                let result = try await PassageQuestions.generate(passage: passage, model: model, focus: focus, existing: questions) { confirmed in
                    await MainActor.run { questions = confirmed }
                }
                try Task.checkCancellation()
                questions = result
                if result.count < 5 {
                    notice = result.isEmpty
                        ? "Er konden geen vragen met een bevestigd broncitaat worden gemaakt. Probeer opnieuw."
                        : "\(result.count) van 5 vragen bevestigd. De overige vragen konden niet worden aangevuld met geldige broncitaten. Je kunt opnieuw proberen; deze vragen blijven behouden."
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
