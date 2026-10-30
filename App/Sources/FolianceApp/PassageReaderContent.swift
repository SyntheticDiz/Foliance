import Foundation

/// The full source passage shown by the passage reader. Passage provenance is
/// retained in its original order, including repeated pages and exact quotes.
struct PassageReaderContent: Sendable {
    enum Provenance: Sendable, Equatable {
        case fullParagraph
        case legacyQuote
        case chosenSelection
    }

    let text: String
    let sources: [Insight.Source]
    let isCompletePassage: Bool
    let provenance: Provenance
    let title: String
    let userNote: String?

    init(point: Insight) {
        if let passageSources = point.passageSources, !passageSources.isEmpty {
            sources = passageSources
            text = passageSources.map(\.quote).joined(separator: "\n")
            isCompletePassage = true
            provenance = .fullParagraph
        } else {
            sources = [Insight.Source(page: point.page, quote: point.quote)]
            text = point.quote
            isCompletePassage = false
            provenance = .legacyQuote
        }
        title = point.title
        userNote = nil
    }

    /// Chosen selections are displayed verbatim. Their source-page quotes are
    /// navigation aids only and must never replace or label the selected text.
    init(chosenPassage: ChosenPassage) {
        text = chosenPassage.text
        title = chosenPassage.title.isEmpty ? "Gekozen passage" : chosenPassage.title
        userNote = chosenPassage.note.isEmpty ? nil : chosenPassage.note
        provenance = .chosenSelection
        isCompletePassage = false

        let quoteByPage = Dictionary(chosenPassage.sources.map { ($0.page, $0.quote) }, uniquingKeysWith: { first, _ in first })
        let pages = chosenPassage.pages.map { Insight.Source(page: $0, quote: quoteByPage[$0] ?? "") }
        let extraSources = chosenPassage.sources
            .filter { !chosenPassage.pages.contains($0.page) }
            .map { Insight.Source(page: $0.page, quote: $0.quote) }
        sources = pages + extraSources
    }

    /// Finds literal occurrences after collapsing whitespace and applying
    /// Dutch-locale lowercase conversion. Returned ranges refer to the exact
    /// original UTF-16 offsets, including all source whitespace in a match.
    static func matches(in text: String, query: String) -> [NSRange] {
        let index = SearchIndex(text: text)
        return (try? index.matches(query: query)) ?? []
    }

    static func matchCountDescription(_ count: Int, isEnglish: Bool = true) -> String {
        let noun = count == 1 ? "match" : "matches"
        return "\(count) \(noun)"
    }

    /// Reusable folded source and UTF-16 offset map. Build once per passage,
    /// then reuse it for each live search query.
    struct SearchIndex: Sendable {
        private let indexedText: FoldedText

        init(text: String) {
            indexedText = FoldedText(text)
        }

        private init(indexedText: FoldedText) {
            self.indexedText = indexedText
        }

        static func build(text: String, cancellationCheck: @Sendable () -> Bool) throws -> Self {
            try Self(indexedText: FoldedText(text, cancellationCheck: cancellationCheck))
        }

        func matches(query: String, cancellationCheck: @Sendable () -> Bool = { false }) throws -> [NSRange] {
            let foldedQuery = try FoldedText(query, cancellationCheck: cancellationCheck).value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !foldedQuery.isEmpty, !indexedText.value.isEmpty else { return [] }

            let source = indexedText.value as NSString
            let needle = foldedQuery as NSString
            var searchRange = NSRange(location: 0, length: source.length)
            var results: [NSRange] = []

            while searchRange.length > 0 {
                if results.count.isMultiple(of: 64), cancellationCheck() { throw CancellationError() }
                let found = source.range(of: needle as String, options: .literal, range: searchRange)
                guard found.location != NSNotFound, found.length > 0 else { break }
                let first = indexedText.originalRanges[found.location]
                let last = indexedText.originalRanges[NSMaxRange(found) - 1]
                results.append(NSRange(location: first.location,
                                       length: NSMaxRange(last) - first.location))
                let next = NSMaxRange(found)
                guard next < source.length else { break }
                searchRange = NSRange(location: next, length: source.length - next)
            }
            return results
        }
    }

    /// Returns literal whole-sentence snippets containing the prototype's
    /// lexical cues. These labels describe words found, not semantic meaning.
    static func cues(in text: String) -> [PassageReaderCue] {
        let source = text as NSString
        var result: [PassageReaderCue] = []

        for range in sentenceRanges(in: text) {
            let sentence = source.substring(with: range)
            let kinds = cuePatterns.compactMap { kind, pattern in
                pattern.firstMatch(in: sentence, range: NSRange(location: 0, length: (sentence as NSString).length)) == nil
                    ? nil : kind
            }
            guard !kinds.isEmpty else { continue }
            result.append(PassageReaderCue(id: result.count,
                                           range: range,
                                           text: sentence,
                                           kind: kinds.joined(separator: " · ")))
        }
        return result
    }

    private struct FoldedText: Sendable {
        let value: String
        let originalRanges: [NSRange]

        init(_ original: String) {
            try! self.init(original, cancellationCheck: { false })
        }

        init(_ original: String, cancellationCheck: @Sendable () -> Bool = { false }) throws {
            var folded = ""
            var ranges: [NSRange] = []
            let nsOriginal = original as NSString
            var index = 0
            var nextCancellationCheck = 0
            var pendingWhitespace: NSRange?

            while index < nsOriginal.length {
                if index >= nextCancellationCheck {
                    if cancellationCheck() { throw CancellationError() }
                    nextCancellationCheck = index + 2048
                }
                let range = nsOriginal.rangeOfComposedCharacterSequence(at: index)
                let piece = nsOriginal.substring(with: range)
                if piece.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                    if let pending = pendingWhitespace {
                        pendingWhitespace = NSRange(location: pending.location,
                                                     length: NSMaxRange(range) - pending.location)
                    } else {
                        pendingWhitespace = range
                    }
                } else {
                    if let whitespace = pendingWhitespace, !folded.isEmpty {
                        folded.append(" ")
                        ranges.append(whitespace)
                    }
                    pendingWhitespace = nil
                    let lowered = piece.lowercased(with: Locale(identifier: "nl_NL"))
                    folded.append(lowered)
                    for _ in 0..<(lowered as NSString).length { ranges.append(range) }
                }
                index = NSMaxRange(range)
            }
            value = folded
            originalRanges = ranges
        }
    }

    private static let cuePatterns: [(String, NSRegularExpression)] = [
        ("Termijn of datum", regex(#"\b(?:termijn(?:en)?|uiterlijk|binnen|vóór|vanaf|nadat|op\s+\d|\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{1,2}\s+(?:januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december))\b"#)),
        ("Woorden bij voorwaarden", regex(#"\b(?:als|indien|mits|tenzij|alleen|uitsluitend|zodra|wanneer|voordat|zonder|voorwaarde(?:n)?)\b"#)),
        ("Woorden over besluiten", regex(#"\b(?:besluit(?:en)?|besloten|vastgesteld|goedgekeurd|afgewezen|voorstel|nog\s+geen|status)\b"#))
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are static literals maintained with the reader's cue list.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func sentenceRanges(in text: String) -> [NSRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var start = 0
        var index = 0
        let closingQuotes: Set<unichar> = [0x22, 0x27, 0x29, 0x5D, 0x7D, 0x00BB, 0x2019, 0x201D, 0x203A]

        func appendTrimmed(_ rawRange: NSRange) {
            guard rawRange.length > 0 else { return }
            let fragment = source.substring(with: rawRange) as NSString
            let trimmed = fragment.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
            guard trimmed.location != NSNotFound else { return }
            var end = NSMaxRange(rawRange)
            let beginning = rawRange.location + trimmed.location
            while end > beginning {
                let finalCharacter = source.rangeOfComposedCharacterSequence(at: end - 1)
                guard finalCharacter.location >= beginning else { break }
                let finalText = source.substring(with: finalCharacter)
                guard finalText.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { break }
                end = finalCharacter.location
            }
            ranges.append(NSRange(location: beginning, length: end - beginning))
        }

        while index < source.length {
            let unit = source.character(at: index)
            let isTerminal = unit == 0x21 || unit == 0x3F || unit == 0x2E
            let previous = index > 0 ? source.character(at: index - 1) : 0
            let next = index + 1 < source.length ? source.character(at: index + 1) : 0
            let decimalDot = unit == 0x2E && (0x30...0x39).contains(previous) && (0x30...0x39).contains(next)

            if isTerminal && !decimalDot {
                var end = index + 1
                while end < source.length {
                    let trailing = source.character(at: end)
                    guard trailing == 0x21 || trailing == 0x3F || trailing == 0x2E else { break }
                    end += 1
                }
                while end < source.length, closingQuotes.contains(source.character(at: end)) { end += 1 }
                let followingCharacter = end < source.length
                    ? source.substring(with: source.rangeOfComposedCharacterSequence(at: end))
                    : ""
                let followedByBoundary = end == source.length ||
                    followingCharacter.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) })
                let isAbbreviation = unit == 0x2E && isCommonAbbreviation(endingAt: index, source: source, sentenceStart: start)
                if followedByBoundary && !isAbbreviation {
                    appendTrimmed(NSRange(location: start, length: end - start))
                    index = end - 1
                    start = end
                }
            }
            index += 1
        }
        appendTrimmed(NSRange(location: start, length: source.length - start))
        return ranges
    }

    private static func isCommonAbbreviation(endingAt period: Int, source: NSString, sentenceStart: Int) -> Bool {
        guard period >= sentenceStart else { return false }
        let prefix = source.substring(with: NSRange(location: sentenceStart, length: period - sentenceStart)).lowercased()
        guard let last = prefix.components(separatedBy: .whitespacesAndNewlines).last else { return false }
        let token = last.trimmingCharacters(in: .punctuationCharacters)
        return ["dhr", "mevr", "dr", "mr", "prof", "ir", "ds", "nr", "art", "blz", "bijv", "etc", "ca", "e.g", "o.a", "e.d", "m.a.w", "m.b.t", "i.v.m", "t.a.v", "z.g", "j.l", "a.s"].contains(token)
    }
}

struct PassageReaderCue: Identifiable, Sendable {
    let id: Int
    let range: NSRange
    let text: String
    let kind: String
}
