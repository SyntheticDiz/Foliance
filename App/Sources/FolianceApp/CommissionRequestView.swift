import SwiftUI
import NaturalLanguage

enum CommissionRequests {
    struct Request: Identifiable {
        let page: Int
        let quote: String
        var occurrence: Int = 0
        var id: String { "\(page)-\(occurrence)" }
    }
    static func extract(_ pages: [String]) -> [Request] {
        var result: [Request] = []
        for (i, text) in pages.enumerated() {
            let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if sentence.range(of: #"(?i)(commissie|raad)\s+wordt\s+(gevraagd|verzocht)|\b(gevraagd|verzocht)\s+aan\s+de\s+(commissie|raad)|\bwij\s+vragen\s+de\s+(commissie|raad)"#, options: .regularExpression) != nil {
                    result.append(.init(page: i + 1, quote: sentence, occurrence: result.count))
                }
                return true
            }
        }
        return result
    }
}
struct CommissionRequestView: View {
    let pages: [String]
    let showPage: (Int) -> Void
    @State private var requests: [CommissionRequests.Request] = []
    private let uiLanguage = "en"
    private var grouped: [(quote: String, pages: [Int])] {
        var seen = Set<String>()
        return requests.filter { seen.insert($0.quote).inserted }.map { request in
            (request.quote, Array(Set(requests.filter { $0.quote == request.quote }.map(\.page))).sorted())
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !requests.isEmpty {
                Divider()
                Text(UIStrings.text("Vragen om uit te zoeken")).font(.headline)
                ForEach(grouped, id: \.quote) { request in
                    Text("• " + request.quote).font(.callout).textSelection(.enabled)
                    ForEach(request.pages, id: \.self) { page in
                        Button(UIStrings.text("Toon in PDF · p. \(page)")) { showPage(page) }
                            .buttonStyle(FocusQuietActionStyle())
                    }
                }
            }
        }.task(id: pages) {
            let input = pages
            let found = await Task.detached { CommissionRequests.extract(input) }.value
            if !Task.isCancelled { requests = found }
        }
    }
}
