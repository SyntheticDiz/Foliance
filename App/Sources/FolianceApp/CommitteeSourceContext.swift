import Foundation

/// Supplies separately attributed, literal context for a committee passage.
/// Returned context can help identify a table row or its subject; it is never
/// a replacement for the passage's core sources.
enum CommitteeSourceContext {
    static let cacheVersion = "committee-source-context-v1"
    static let maximumUTF8Bytes = 12_000
    static let maximumSources = 3

    static func valid(sources: [Insight.Source]?, pages: [String]) -> Bool {
        guard let sources else { return true }
        return sources.count <= maximumSources &&
            Set(sources.map(\.page)).count == sources.count &&
            sources.reduce(0, { $0 + $1.quote.utf8.count }) <= maximumUTF8Bytes &&
            sources.allSatisfy { isExactSource($0, in: pages) }
    }

    static func context(pages: [String], passage: PassageEngine.Passage) -> [Insight.Source] {
        var result = ChatGPTTableContext.retrieve(pages: pages, sources: passage.sources)
            .filter { isExactSource($0, in: pages) }
        guard result.count < maximumSources,
              !hasSeveralNumbers(passage.text),
              let heading = precedingSubjectHeading(pages: pages, passage: passage),
              !result.contains(where: { $0.page == heading.page }),
              result.reduce(0, { $0 + $1.quote.utf8.count }) + heading.quote.utf8.count <= maximumUTF8Bytes else {
            return result
        }
        result.append(heading)
        return result
    }

    private static func precedingSubjectHeading(pages: [String], passage: PassageEngine.Passage) -> Insight.Source? {
        guard let core = passage.sources.first,
              core.page > 0, core.page <= pages.count,
              passage.text.utf8.count <= 1_200,
              !core.quote.isEmpty,
              isExactSource(core, in: pages),
              let range = pages[core.page - 1].range(of: core.quote, options: .literal) else { return nil }
        let prefix = pages[core.page - 1][..<range.lowerBound]
        guard let rawHeading = prefix.split(whereSeparator: \.isNewline).last.map(String.init) else { return nil }
        let candidate = Insight.Source(page: core.page, quote: rawHeading)
        guard DocumentParagraphs.isHeading(rawHeading),
              isSubjectHeading(rawHeading),
              sharesSubjectWord(rawHeading, with: passage.text),
              isExactSource(candidate, in: pages) else { return nil }
        return candidate
    }

    private static func isExactSource(_ source: Insight.Source, in pages: [String]) -> Bool {
        guard source.page > 0, source.page <= pages.count, !source.quote.isEmpty else { return false }
        // Context may not be clipped or normalized to fit the prompt.
        let page = Data(pages[source.page - 1].utf8), quote = Data(source.quote.utf8)
        guard let match = page.range(of: quote) else { return false }
        return page.range(of: quote, in: (match.lowerBound + 1)..<page.endIndex) == nil
    }

    private static func isSubjectHeading(_ text: String) -> Bool {
        let words = subjectWords(text)
        // A unit-only line such as “Bedragen x € 1.000” has no subject words.
        return !words.isEmpty
    }

    private static func sharesSubjectWord(_ heading: String, with core: String) -> Bool {
        !subjectWords(heading).isDisjoint(with: subjectWords(core))
    }

    private static func subjectWords(_ text: String) -> Set<String> {
        let excluded: Set<String> = [
            "bedrag", "bedragen", "euro", "duizend", "duizenden", "miljoen", "miljoenen",
            "procent", "percentage", "x", "van", "voor", "met", "bij", "aan", "de", "het", "een"
        ]
        return Set(text.lowercased().split { !$0.isLetter }.map(String.init)
            .filter { $0.count >= 4 && !excluded.contains($0) })
    }

    private static func hasSeveralNumbers(_ text: String) -> Bool {
        let pattern = #"(?<![\p{L}\p{N}])[-−+–]?(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d+)?%?(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) >= 3
    }
}
