import Foundation

/// Source evidence is verified against the current document's physical-page text.
/// Matching uses UTF-8 bytes so canonically equivalent but differently encoded
/// strings are not treated as literal matches.
enum SourceBoundEvidence {
    struct VerifiedQuote: Equatable {
        let physicalPage: Int
        let quote: String
    }

    struct PageContext: Identifiable, Equatable {
        let physicalPage: Int
        let text: String
        var id: Int { physicalPage }
    }

    struct Context: Equatable {
        let pages: [PageContext]
        let verifiedQuote: VerifiedQuote?
    }

    static func validate(item: SourceHighlights.Item, pages: [String]) -> VerifiedQuote? {
        guard !item.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.page > 0, item.page <= pages.count else { return nil }
        if let sources = item.passageSources {
            guard !sources.isEmpty, sources.first?.page == item.page,
                  Array(sources.map(\.quote).joined(separator: "\n").utf8) == Array(item.quote.utf8),
                  sources.map(\.page) == sources.map(\.page).sorted(),
                  sources.allSatisfy({ source in
                      source.page > 0 && source.page <= pages.count &&
                      !source.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      exactUTF8Substring(source.quote, in: pages[source.page - 1]) != nil
                  }) else { return nil }
            return VerifiedQuote(physicalPage: item.page, quote: sources.map(\.quote).joined(separator: "\n"))
        }
        guard let original = exactUTF8Substring(item.quote, in: pages[item.page - 1]) else { return nil }
        return VerifiedQuote(physicalPage: item.page, quote: original)
    }

    /// Returns complete neighboring physical pages from the supplied document snapshot.
    /// This intentionally makes no claim that the PDF text extraction contains every mark
    /// or every element visible on those pages.
    static func context(item: SourceHighlights.Item, pages: [String]) -> Context? {
        guard item.page > 0, item.page <= pages.count else { return nil }
        // Even if quote validation fails, offer complete original context. Never
        // treat a model-provided quote as a replacement for these source pages.
        let sourcePages = (item.passageSources ?? []).map(\.page).filter { $0 > 0 && $0 <= pages.count }
        let firstPage = min(item.page, sourcePages.min() ?? item.page)
        let lastPage = max(item.page, sourcePages.max() ?? item.page)
        let firstIndex = max(0, firstPage - 2)
        let lastIndex = min(pages.count - 1, lastPage)
        let pageContext = (firstIndex...lastIndex).map { index in
            PageContext(physicalPage: index + 1, text: pages[index])
        }
        return Context(pages: pageContext, verifiedQuote: validate(item: item, pages: pages))
    }

    private static func exactUTF8Substring(_ quote: String, in page: String) -> String? {
        let pageBytes = Array(page.utf8)
        let quoteBytes = Array(quote.utf8)
        guard !quoteBytes.isEmpty, quoteBytes.count <= pageBytes.count else { return nil }
        for start in 0...(pageBytes.count - quoteBytes.count) {
            let end = start + quoteBytes.count
            if pageBytes[start..<end].elementsEqual(quoteBytes) {
                return String(decoding: pageBytes[start..<end], as: UTF8.self)
            }
        }
        return nil
    }
}
