import Foundation

/// Presentation-only paragraph breaks for long overview text. Chunks concatenate
/// to the original string exactly; analysis, storage, and exports keep the source.
enum SummaryDisplayText {
    private static let abbreviations: Set<String> = [
        "dhr.", "mevr.", "dr.", "prof.", "mr.", "ir.", "ing.",
        "bijv.", "o.a.", "d.w.z.", "m.a.w.", "i.v.m.", "t.o.v.",
        "n.v.t.", "enz.", "etc.", "resp.", "ca.", "nr.", "art.", "blz.", "p.",
        "n.v.", "b.v."
    ]
    private static let sentencePunctuation: Set<Character> = [".", "!", "?", "…"]
    private static let closingPunctuation: Set<Character> = ["\"", "'", "”", "’", ")", "]"]
    private static let listMarkers: Set<Character> = ["-", "–", "—", "•", "*", "‣"]

    static func chunks(_ text: String) -> [String] {
        // Keep short overviews exactly as a single reading block.
        guard text.count > 300 else { return text.isEmpty ? [] : [text] }
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        var sentences: [String] = []
        var start = 0
        var index = 0
        while index < characters.count {
            guard characters[index] == "." || characters[index] == "!" || characters[index] == "?" else {
                index += 1
                continue
            }

            if characters[index] == ".", index > 0, index + 1 < characters.count,
               characters[index - 1].isNumber, characters[index + 1].isNumber {
                index += 1
                continue
            }

            var end = index + 1
            while end < characters.count, sentencePunctuation.contains(characters[end]) { end += 1 }
            while end < characters.count, closingPunctuation.contains(characters[end]) { end += 1 }

            // Keep newlines, list rows, and their existing paragraph structure
            // untouched. Only prose separated by horizontal whitespace is split.
            guard end < characters.count, characters[end].isWhitespace,
                  !characters[end].isNewline,
                  !isListLine(in: characters, at: index) else {
                index = end
                continue
            }
            var next = end
            while next < characters.count, characters[next].isWhitespace, !characters[next].isNewline { next += 1 }
            guard next < characters.count,
                  characters[next].isUppercase || characters[next].isNumber,
                  !isAbbreviation(in: characters, start: start, end: end) else {
                index = next
                continue
            }

            sentences.append(String(characters[start..<next]))
            start = next
            index = next
        }
        if start < characters.count { sentences.append(String(characters[start...])) }
        return grouped(sentences)
    }

    private static func grouped(_ sentences: [String]) -> [String] {
        guard sentences.count > 1 else { return sentences }
        var paragraphs: [String] = []
        var current: [String] = []
        var currentLength = 0

        for sentence in sentences {
            if !current.isEmpty, currentLength + sentence.count > 600 {
                paragraphs.append(current.joined())
                current = []
                currentLength = 0
            }
            current.append(sentence)
            currentLength += sentence.count

            if current.count >= 3 || (current.count >= 2 && currentLength >= 360) {
                paragraphs.append(current.joined())
                current = []
                currentLength = 0
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined()) }
        return paragraphs
    }

    private static func isAbbreviation(in characters: [Character], start: Int, end: Int) -> Bool {
        let rawToken = String(characters[start..<end])
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .last.map(String.init) ?? ""
        return abbreviations.contains(rawToken.lowercased())
            || rawToken.range(of: #"^\p{L}(?:\.\p{L})*\.$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isListLine(in characters: [Character], at index: Int) -> Bool {
        let lineStart = characters[..<index].lastIndex(where: { $0.isNewline }).map { $0 + 1 } ?? 0
        let prefix = characters[lineStart..<index].drop(while: { $0.isWhitespace })
        guard let first = prefix.first else { return false }
        if listMarkers.contains(first) { return true }
        let trimmed = String(prefix)
        return trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
    }
}
