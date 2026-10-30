import Foundation

/// Display-only formatting for a source quote. The archived quote remains the source of truth.
enum SourceCardText {
    struct Presentation: Equatable {
        let title: String
        let body: String
    }

    /// A reading-only view of the complete quote. Unlike `presentation`, this
    /// never extracts a heading, so source evidence remains in the displayed text.
    static func readingText(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return reflow(normalized)
    }

    static func presentation(quote: String, fallbackTitle: String) -> Presentation {
        let fallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFallback = fallback.isEmpty ? "Bronpassage" : fallback
        let normalized = quote.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        guard let firstContentIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              firstContentIndex == 0,
              isConfidentHeading(lines[0], following: Array(lines.dropFirst())) else {
            return Presentation(title: safeFallback, body: reflow(normalized))
        }

        let title = lines[0].trimmingCharacters(in: .whitespaces)
        let remaining = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return Presentation(title: title, body: reflow(remaining))
    }

    private static func isConfidentHeading(_ line: String, following: [String]) -> Bool {
        let candidate = line.trimmingCharacters(in: .whitespaces)
        let words = candidate.split(whereSeparator: \.isWhitespace)
        guard !candidate.isEmpty,
              line.first?.isWhitespace != true,
              candidate.count <= 56,
              (2...6).contains(words.count),
              let first = words.first?.first,
              first.isUppercase,
              !candidate.hasSuffix("."), !candidate.hasSuffix(","),
              !candidate.hasSuffix(":"), !candidate.hasSuffix(";"),
              !candidate.hasSuffix("?"), !candidate.hasSuffix("!"),
              !candidate.contains("\t"),
              !isListLine(candidate), !looksLikeTableRow(candidate) else { return false }

        // A title-like line followed by an ordinary paragraph is reliable; otherwise keep it in the quote.
        let next = following.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !next.isEmpty, !isListLine(next), !next.contains("\t") else { return false }
        let hasTitleCaseWord = words.dropFirst().contains { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
        let hasParagraphGap = following.first?.trimmingCharacters(in: .whitespaces).isEmpty == true
        let nextStartsLowercase = next.first?.isLowercase == true
        let sentenceStarts: Set<String> = ["de", "het", "een", "er", "dit", "dat", "als", "indien", "wanneer", "wij", "we", "zij"]
        let startsLikeSentence = words.first.map { sentenceStarts.contains($0.lowercased()) } ?? false
        return !nextStartsLowercase && !startsLikeSentence && (hasParagraphGap || hasTitleCaseWord)
    }

    private static func reflow(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            if paragraph.contains(where: isProtectedLine) {
                output.append(contentsOf: paragraph)
            } else {
                output.append(paragraphizeLongProse(joinWrappedLines(paragraph)))
            }
            paragraph.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                output.append(line)
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return output.joined(separator: "\n")
    }

    private static func paragraphizeLongProse(_ text: String) -> String {
        guard text.count > 300 else { return text }

        // PDF extraction may put a sentence boundary on a new line. Normalize
        // only those breaks; uncertain wraps and hyphenated line breaks stay put.
        let sentenceScanText = exposingSentenceBreaks(in: text)
        let chunks = SummaryDisplayText.chunks(sentenceScanText)
        guard chunks.count > 1 else { return text }
        return chunks.joined(separator: "\n\n")
    }

    private static func exposingSentenceBreaks(in text: String) -> String {
        let characters = Array(text)
        let sentenceEndings: Set<Character> = [".", "!", "?", "…"]
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]"]
        var output = String()
        output.reserveCapacity(text.count)

        for index in characters.indices {
            guard characters[index] == "\n" else {
                output.append(characters[index])
                continue
            }

            var previous = index
            while previous > characters.startIndex {
                previous -= 1
                if !characters[previous].isWhitespace { break }
            }
            while closers.contains(characters[previous]), previous > characters.startIndex {
                previous -= 1
            }
            output.append(sentenceEndings.contains(characters[previous]) ? " " : "\n")
        }
        return output
    }

    private static func joinWrappedLines(_ lines: [String]) -> String {
        guard let first = lines.first else { return "" }
        var result = first.trimmingCharacters(in: .whitespaces)
        for line in lines.dropFirst() {
            let next = line.trimmingCharacters(in: .whitespaces)
            guard shouldJoin(previous: result, next: next) else {
                result += "\n" + line
                continue
            }
            result += " " + next
        }
        return result
    }

    private static func shouldJoin(previous: String, next: String) -> Bool {
        guard let nextFirst = next.first, nextFirst.isLowercase,
              let previousLast = previous.last,
              !".!?:".contains(previousLast),
              previousLast != "-", previousLast != "‐", previousLast != "‑" else { return false }
        return true
    }

    private static func isProtectedLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return line.contains("\t") || line.first?.isWhitespace == true || isListLine(trimmed)
            || looksLikeTableRow(trimmed)
    }

    private static func isListLine(_ line: String) -> Bool {
        let prefixes = ["•", "‣", "◦", "▪", "– ", "— ", "- ", "* "]
        if prefixes.contains(where: line.hasPrefix) { return true }
        return line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
            || line.range(of: #"^[A-Za-z][.)]\s"#, options: .regularExpression) != nil
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        if line.contains("|") || line.contains("│") || line.contains("┃") || line.contains("¦") { return true }
        // PDF table extraction commonly leaves two or more spaces between adjacent columns.
        return line.range(of: #"\S {2,}\S"#, options: .regularExpression) != nil
    }
}
