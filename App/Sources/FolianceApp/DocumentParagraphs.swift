import Foundation
import PDFKit

struct DocumentParagraph {
    var sources: [Insight.Source]
    var text: String { sources.map(\.quote).joined(separator: "\n") }
}

enum DocumentParagraphs {
    struct Line {
        let text: String
        let bounds: CGRect
        var heading = false
    }
    static func isList(_ text: String) -> Bool {
        text.range(of: #"^\s*(?:[•●▪◦–-]|\d+[.)]|[a-z][.)])\s+"#, options: .regularExpression) != nil
    }
    static func isHeading(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(whereSeparator: \.isWhitespace)
        let unfinishedEnding: Set<String> = ["de", "het", "een", "van", "voor", "op", "om", "met", "en", "of", "naar", "tot", "dat", "die"]
        if let last = words.last, unfinishedEnding.contains(last.lowercased()) { return false }
        return !isList(text) && !text.isEmpty && words.count <= 12 && text.count <= 110 && !text.contains(where: { ".!?;:".contains($0) })
    }

    /// PDFKit's physical line selections remove artificial newlines embedded in PDF text.
    static func text(from page: PDFPage) -> String {
        guard let raw = page.string, let selection = page.selection(for: NSRange(location: 0, length: (raw as NSString).length)) else { return "" }
        let lines = selection.selectionsByLine().compactMap { selection -> Line? in
            guard let value = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            let rect = selection.bounds(for: page)
            guard !rect.isEmpty, !rect.isInfinite else { return nil }
            let font = selection.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            return Line(text: value, bounds: rect, heading: isHeading(value) && font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        }
        let ordered = lines.sorted { a, b in
            if abs(a.bounds.minY - b.bounds.minY) < 2 { return a.bounds.minX < b.bounds.minX }
            return a.bounds.minY > b.bounds.minY
        }
        return rebuild(ordered)
    }

    /// Use observed line spacing, not the bounding box of one letter (which differs
    /// for capitals, punctuation and lowercase letters). Indentation alone never splits.
    static func rebuild(_ lines: [Line]) -> String {
        guard !lines.isEmpty else { return "" }
        let gaps = zip(lines, lines.dropFirst()).compactMap { a, b -> CGFloat? in
            let gap = a.bounds.minY - b.bounds.minY
            guard gap > 0, gap < max(a.bounds.height, b.bounds.height) * 4,
                  abs(a.bounds.height - b.bounds.height) < max(a.bounds.height, b.bounds.height) * 0.35 else { return nil }
            return gap
        }.sorted()
        // The lower half represents normal lines even when many paragraphs have extra spacing.
        let normal = gaps.isEmpty ? max(1, lines[0].bounds.height * 1.2) : gaps[(gaps.count - 1) / 3]
        var result = lines[0].text
        for i in 1..<lines.count {
            let previous = lines[i - 1]; let line = lines[i]
            let gap = previous.bounds.minY - line.bounds.minY
            if abs(gap) < normal * 0.35 && line.bounds.minX >= previous.bounds.maxX - 2 {
                result += " " + line.text
                continue
            }
            let columnChange = gap < -normal || (line.bounds.minX > previous.bounds.maxX + 20)
            let clearlySeparated = gap > max(normal * 1.45, normal + 3)
            let shortPrevious = previous.bounds.width < line.bounds.width * 0.8
            let supportedIndent = line.bounds.minX - previous.bounds.minX > 10 && shortPrevious && gap > normal * 1.15
            let headingBoundary = previous.heading || line.heading
            result += (columnChange || clearlySeparated || supportedIndent || headingBoundary) ? "\n\n" : "\n"
            result += line.text
        }
        return result
    }

    private static func headerKey(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\d{1,2}\s+\p{L}+\s+\d{4}\s+\d+\s+van\s+\d+\s*"#, with: "", options: .regularExpression)
    }

    static func extract(_ pages: [String]) -> [DocumentParagraph] {
        var result: [DocumentParagraph] = []
        let boundaryLines = pages.flatMap { page -> [String] in
            let lines = page.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            return Array(Set(Array(lines.prefix(8)) + Array(lines.suffix(3))))
        }
        let repeated = Dictionary(grouping: boundaryLines, by: { headerKey($0) }).filter { $0.value.count >= 3 && $0.key.count < 160 && !$0.key.contains(where: { ".!?;".contains($0) }) }.keys
        let headers = Set(repeated)
        var pending: [Insight.Source] = []
        for (index, page) in pages.enumerated() {
            if page.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pending = []; continue }
            let clean = page.components(separatedBy: "\n").enumerated().map { offset, line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                let lower = t.lowercased()
                if (lower.contains("postadres") && lower.contains("bezoekadres")) || (lower.contains("telefoon") && lower.contains("e-mail")) { return "" }
                if offset < 18 && ["memo", "aan van", "datum pagina", "datum pagina betreft"].contains(lower) { return "" }
                if headers.contains(headerKey(t)) || (offset < 18 && t.range(of: #"^\d{1,2}\s+\p{L}+\s+\d{4}\s+\d+\s+van\s+\d+"#, options: .regularExpression) != nil) || t.range(of: #"^(?:Pagina\s+)?\d+(?:\s+(?:van|/)\s*\d+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil { return "" }
                return line
            }.joined(separator: "\n")
            let blocks = clean.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            for (blockIndex, block) in blocks.enumerated() {
                let source = Insight.Source(page: index + 1, quote: block)
                let previous = result.last
                let priorText = previous?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let continuesPage = blockIndex == 0 && previous?.sources.last?.page == index
                    && unfinishedPageTail(priorText, next: block)
                if isHeading(block) && !continuesPage {
                    append(source, to: &pending)
                    continue
                }
                let continuesList = isList(block) && previous.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") || $0.text.components(separatedBy: "\n").contains(where: isList) } == true
                if pending.isEmpty && (continuesList || continuesPage), !result.isEmpty,
                   result.last!.sources.last!.page >= index {
                    append(source, to: &result[result.count - 1].sources)
                } else {
                    var sources = pending
                    append(source, to: &sources)
                    result.append(.init(sources: sources))
                }
                pending = []
            }
        }
        if !pending.isEmpty { result.append(.init(sources: pending)) }
        return result
    }
    private static func unfinishedPageTail(_ previous: String, next: String) -> Bool {
        let unfinishedWords: Set<String> = ["de", "het", "een", "van", "voor", "met", "door", "en", "of", "dat", "die", "waarvoor", "om", "aan", "over", "ter", "tot", "in", "op", "bij", "als", "uit", "te", "naar", "onder", "wordt", "zijn"]
        let lastWord = previous.split(whereSeparator: \.isWhitespace).last?.trimmingCharacters(in: .punctuationCharacters).lowercased() ?? ""
        let strong = previous.hasSuffix("-") || unfinishedWords.contains(lastWord)
        let allCaps = next == next.uppercased() && next.contains(where: \.isLetter)
        let structuralHeading = next.range(of: #"^(?:Hoofdstuk|Artikel|Bijlage|Paragraaf|Deel|§)\b"#, options: [.regularExpression, .caseInsensitive]) != nil || allCaps
        if strong { return !structuralHeading }
        guard !structuralHeading else { return false }
        return previous.hasSuffix(":") || (previous.last.map { !".!?;".contains($0) } == true && next.first?.isLowercase == true)
    }
    private static func append(_ source: Insight.Source, to sources: inout [Insight.Source]) {
        if let last = sources.last, last.page == source.page {
            sources[sources.count - 1] = .init(page: last.page, quote: last.quote + "\n\n" + source.quote)
        } else { sources.append(source) }
    }
}
