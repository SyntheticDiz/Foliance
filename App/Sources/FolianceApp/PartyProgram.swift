import Foundation
import SwiftUI

struct PartyProgram: Codable, Sendable {
    let name: String
    let pages: [String]
    let pdf: Data
    var criteria: String? = nil

    static var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Foliance/reference-document.json")
    }
    static func load(from url: URL = storageURL) throws -> PartyProgram? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PartyProgram.self, from: Data(contentsOf: url))
    }
    func save(to url: URL = storageURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Small, ranked source fragments keep the local Apple model within its context budget.
    func candidates(for text: String) -> [DocumentChunk] {
        Array(rankedCandidates(for: text).prefix(2))
    }

    struct SearchIndex: Sendable {
        let chunks: [DocumentChunk]
        let terms: [Set<String>]
        func rankedCandidates(for text: String) -> [DocumentChunk] {
            let target = PartyProgram.words(text)
            var ranked: [(index: Int, score: Int)] = []
            for index in chunks.indices { ranked.append((index, terms[index].intersection(target).count)) }
            ranked.sort { left, right in
                left.score == right.score ? left.index < right.index : left.score > right.score
            }
            return ranked.map { chunks[$0.index] }
        }
    }
    private static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["worden", "hebben", "kunnen", "moeten", "onze", "deze", "voor", "door", "naar", "niet", "zijn", "wordt", "meer", "over", "onder", "zoals", "daar", "alle", "waar", "zich", "maar", "heeft"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 4 && !stop.contains($0) }.map { String($0.prefix(7)) })
    }
    var searchIndex: SearchIndex {
        let chunks = TextChunks.chunks(pages, maxBytes: 700)
        return SearchIndex(chunks: chunks, terms: chunks.map { Self.words($0.text) })
    }
    func rankedCandidates(for text: String) -> [DocumentChunk] { searchIndex.rankedCandidates(for: text) }

}

struct PartyProgramSettings: View {
    private let uiLanguage = "en"
    @State private var program: PartyProgram?
    @State private var choosing = false
    @State private var busy = false
    @State private var message = ""
    @State private var criteria = ""
    var body: some View {
        GroupBox(UIStrings.text("Reference document")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(UIStrings.text(program.map { "\($0.name) · \($0.pages.count) pages" } ?? "No reference document saved"))
                    .font(.callout).lineLimit(2)
                TextField(UIStrings.text("Comparison criteria (optional)"), text: $criteria, axis: .vertical)
                    .lineLimit(2...5).disabled(busy)
                if program != nil {
                    Button(UIStrings.text("Save criteria")) {
                        guard let program else { return }
                        var updated = program
                        let trimmed = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.criteria = trimmed.isEmpty ? nil : String(trimmed.prefix(2_000))
                        do { try updated.save(); self.program = updated; message = "Criteria saved. Start a new analysis to use them." }
                        catch { message = error.localizedDescription }
                    }.disabled(busy)
                }
                HStack {
                    Button(UIStrings.text(program == nil ? "Add PDF…" : "Replace PDF…")) { choosing = true }.disabled(busy)
                    if program != nil {
                        Button("Remove", role: .destructive) {
                            do { try FileManager.default.removeItem(at: PartyProgram.storageURL); program = nil; criteria = ""; message = "Deleted. Start a new analysis to refresh reference comparisons." }
                            catch { message = error.localizedDescription }
                        }.disabled(busy)
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
                Text(UIStrings.text("Stored locally. A new AI analysis can compare document content with this reference and any criteria you provide. Text-based retrieval may miss indirect connections. The PDF needs readable text.")).font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(UIStrings.text(message)).font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .task { do { program = try PartyProgram.load(); criteria = program?.criteria ?? "" } catch { message = "Could not load reference document: \(error.localizedDescription)" } }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .failure(let error): if !ImportFailure.isCancellation(error) { message = error.localizedDescription }
            case .success(let url):
                busy = true; message = "Importing reference document…"
                Task { @MainActor in
                    defer { busy = false }
                    do {
                        let trimmedCriteria = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
                        let saved = try await Task.detached(priority: .userInitiated) {
                            let pdf = try OpenPDF.read(url)
                            let saved = PartyProgram(name: pdf.name, pages: pdf.pages, pdf: pdf.data,
                                                     criteria: trimmedCriteria.isEmpty ? nil : String(trimmedCriteria.prefix(2_000)))
                            try saved.save()
                            return saved
                        }.value
                        program = saved; message = "Saved. Start a new analysis to use this reference."
                    } catch { message = error.localizedDescription }
                }
            }
        }
    }
}
