import Foundation

/// Pure presentation layout for a source quote and a literal evidence excerpt.
/// Matching is case-, punctuation-, and digit-sensitive; only whitespace runs
/// are normalized to find the excerpt in the display-formatted source.
enum SourceQuoteLayout {
    struct Segment: Equatable {
        let text: String
        let isEvidence: Bool
    }

    struct Paragraph: Equatable {
        let segments: [Segment]
    }

    struct Layout {
        let paragraphs: [Paragraph]
        let evidenceIsMarked: Bool
        /// Number of exact matches, capped at two so callers can detect ambiguity.
        let evidenceOccurrenceCount: Int
    }

    private struct NormalizedUnit {
        let character: Character
        let range: NSRange
    }

    private struct ParagraphSpan {
        let range: NSRange
    }

    static func make(text: String, evidence: String? = nil) -> Layout {
        let displayText = SourceCardText.readingText(text)
        let source = displayText as NSString
        let paragraphSpans = splitParagraphs(in: displayText)
        let matchResult = findMatches(evidence, in: displayText)
        let match = matchResult.range
        let evidenceIsMarked = matchResult.occurrenceCount == 1

        let paragraphs = paragraphSpans.map { paragraph -> Paragraph in
            let evidenceRange = match.flatMap { intersection($0, paragraph.range) }
            guard let evidenceRange, evidenceRange.length > 0 else {
                return Paragraph(segments: [Segment(text: source.substring(with: paragraph.range), isEvidence: false)])
            }

            var segments: [Segment] = []
            let beforeLength = evidenceRange.location - paragraph.range.location
            if beforeLength > 0 {
                segments.append(Segment(text: source.substring(with: NSRange(location: paragraph.range.location, length: beforeLength)), isEvidence: false))
            }
            segments.append(Segment(text: source.substring(with: evidenceRange), isEvidence: true))
            let afterLocation = NSMaxRange(evidenceRange)
            let afterLength = NSMaxRange(paragraph.range) - afterLocation
            if afterLength > 0 {
                segments.append(Segment(text: source.substring(with: NSRange(location: afterLocation, length: afterLength)), isEvidence: false))
            }
            return Paragraph(segments: segments)
        }
        return Layout(paragraphs: paragraphs, evidenceIsMarked: evidenceIsMarked, evidenceOccurrenceCount: matchResult.occurrenceCount)
    }

    private static func splitParagraphs(in text: String) -> [ParagraphSpan] {
        let nsText = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\n[ \t]*\n(?:[ \t]*\n)*"#)
        let fullRange = NSRange(location: 0, length: nsText.length)
        let boundaries = regex.matches(in: text, range: fullRange).map(\.range)
        var spans: [ParagraphSpan] = []
        var start = 0
        for boundary in boundaries {
            appendParagraph(NSRange(location: start, length: boundary.location - start), from: nsText, to: &spans)
            start = NSMaxRange(boundary)
        }
        appendParagraph(NSRange(location: start, length: nsText.length - start), from: nsText, to: &spans)
        return spans
    }

    private static func appendParagraph(_ range: NSRange, from source: NSString, to spans: inout [ParagraphSpan]) {
        guard range.length > 0,
              source.substring(with: range).rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil else { return }
        spans.append(ParagraphSpan(range: range))
    }

    private static func findMatches(_ evidence: String?, in source: String) -> (range: NSRange?, occurrenceCount: Int) {
        guard let evidence, !evidence.isEmpty else { return (nil, 0) }
        let sourceUnits = normalizedUnits(in: source)
        let evidenceCharacters = normalizedCharacters(in: evidence)
        guard evidenceCharacters.contains(where: { !$0.isWhitespace }),
              evidenceCharacters.count <= sourceUnits.count else { return (nil, 0) }

        let failure = prefixTable(for: evidenceCharacters)
        var matched = 0
        var matchStart: Int?
        var occurrenceCount = 0
        for (index, unit) in sourceUnits.enumerated() {
            while matched > 0 && unit.character != evidenceCharacters[matched] {
                matched = failure[matched - 1]
            }
            if unit.character == evidenceCharacters[matched] { matched += 1 }
            if matched == evidenceCharacters.count {
                let candidateStart = index - evidenceCharacters.count + 1
                if matchStart == nil { matchStart = candidateStart }
                occurrenceCount = min(2, occurrenceCount + 1)
                matched = failure[matched - 1]
            }
        }
        guard let matchStart else { return (nil, 0) }
        let first = sourceUnits[matchStart].range
        let last = sourceUnits[matchStart + evidenceCharacters.count - 1].range
        let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        return (occurrenceCount == 1 ? range : nil, occurrenceCount)
    }

    private static func prefixTable(for pattern: [Character]) -> [Int] {
        var prefix = Array(repeating: 0, count: pattern.count)
        var length = 0
        for index in 1..<pattern.count {
            while length > 0 && pattern[index] != pattern[length] {
                length = prefix[length - 1]
            }
            if pattern[index] == pattern[length] { length += 1 }
            prefix[index] = length
        }
        return prefix
    }

    private static func normalizedCharacters(in text: String) -> [Character] {
        var result: [Character] = []
        var inWhitespace = false
        for character in text {
            if character.isWhitespace {
                if !inWhitespace { result.append(" ") }
                inWhitespace = true
            } else {
                result.append(character)
                inWhitespace = false
            }
        }
        return result
    }

    private static func normalizedUnits(in text: String) -> [NormalizedUnit] {
        var result: [NormalizedUnit] = []
        var utf16Offset = 0
        var whitespaceStart: Int?
        var whitespaceEnd = 0

        func flushWhitespace() {
            if let start = whitespaceStart {
                result.append(NormalizedUnit(character: " ", range: NSRange(location: start, length: whitespaceEnd - start)))
                whitespaceStart = nil
            }
        }

        for character in text {
            let length = String(character).utf16.count
            if character.isWhitespace {
                if whitespaceStart == nil { whitespaceStart = utf16Offset }
                whitespaceEnd = utf16Offset + length
            } else {
                flushWhitespace()
                result.append(NormalizedUnit(character: character, range: NSRange(location: utf16Offset, length: length)))
            }
            utf16Offset += length
        }
        flushWhitespace()
        return result
    }

    private static func intersection(_ lhs: NSRange, _ rhs: NSRange) -> NSRange? {
        let start = max(lhs.location, rhs.location)
        let end = min(NSMaxRange(lhs), NSMaxRange(rhs))
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
