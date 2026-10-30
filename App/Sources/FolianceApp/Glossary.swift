import Foundation

struct GlossaryEntry: Identifiable, Sendable {
    let abbreviation: String
    let occurrences: [Occurrence]
    let definitions: [Definition]
    let reference: Glossary.Reference?
    var id: String { abbreviation.lowercased() }
    struct Occurrence: Sendable { let page: Int; let excerpt: String }
    struct Definition: Hashable, Sendable { let text: String; let page: Int }
    var searchURL: URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: abbreviation + " meaning")]
        return components.url!
    }
}

enum Glossary {
    struct Reference: Sendable {
        let term: String
        let meaning: String
        let explanation: String
        let url: URL
        init(_ term: String, _ meaning: String, _ explanation: String, _ url: String) {
            self.term = term; self.meaning = meaning; self.explanation = explanation; self.url = URL(string: url)!
        }
    }
    // Definitions come from the open document or the reader's own glossary.
    static let references: [Reference] = []
    static func key(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    static func extract(pages: [String], personalTerms: Set<String> = []) -> [GlossaryEntry] {
        let referenceMap = Dictionary(uniqueKeysWithValues: references.map { (key($0.term), $0) })
        let ignored: Set<String> = ["pdf", "www", "http", "https", "isbn", "nvt", "de", "het", "een", "en", "van", "voor", "in", "op", "te", "bij", "na", "of", "is", "om", "al", "dan", "dat", "die", "wat", "wie", "dit", "zijn", "niet", "onze", "onder", "over", "met", "naar", "aan", "uit", "als", "we", "wij", "ons", "doen", "gaan", "gemeente", "bestuur", "wonen", "zorg", "werk", "inkomen", "klimaat", "energie"]
        let pattern = #"(?<![\p{L}\p{N}])(?:[A-Z](?:\.[A-Z]){1,8}\.?|[A-Za-z][A-Za-z0-9&]{1,11}(?:[-–][A-Z0-9]{2,8})*)(?![\p{L}\p{N}])"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var occurrences: [String: [GlossaryEntry.Occurrence]] = [:]
        var names: [String: String] = [:]
        var definitions: [String: [GlossaryEntry.Definition]] = [:]
        for (index, page) in pages.enumerated() {
            // Preserve row boundaries in abbreviation tables before whitespace is flattened.
            let rowPattern = #"^\s*([A-Za-z][A-Za-z0-9.&–-]{1,15})\s*(?::|=|–|\t)\s*(.{3,180})\s*$"#
            let rowRegex = try! NSRegularExpression(pattern: rowPattern)
            for line in page.components(separatedBy: "\n") {
                guard let match = rowRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let shortRange = Range(match.range(at: 1), in: line), let longRange = Range(match.range(at: 2), in: line) else { continue }
                let term = String(line[shortRange]); let identifier = key(term)
                let candidate = String(line[longRange]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
                if alignedExpansion(short: identifier, long: candidate) == candidate {
                    names[identifier] = referenceMap[identifier]?.term ?? term
                    definitions[identifier, default: []].append(.init(text: candidate, page: index + 1))
                }
            }
            let text = page.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let term = String(text[range])
                let identifier = key(term)
                let known = referenceMap[identifier] != nil || personalTerms.contains(identifier) || definitions[identifier] != nil
                let capitals = term.filter { $0.isUppercase }.count
                let before = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let after = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let parenthesized = (before.hasSuffix("(") && after.hasPrefix(")")) || after.hasPrefix("(")
                guard !ignored.contains(identifier), known || capitals >= 2 || after.lowercased().hasPrefix("staat voor ") || after.lowercased().hasPrefix("betekent ") || (parenthesized && term.first?.isUppercase == true) else { continue }
                // Plain all-capitals words in headings are not reliable abbreviations.
                if !known && term.count > 16 { continue }
                let start = text.index(range.lowerBound, offsetBy: -100, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 180, limitedBy: text.endIndex) ?? text.endIndex
                let excerpt = String(text[start..<end])
                names[identifier] = referenceMap[identifier]?.term ?? names[identifier] ?? term
                if !(occurrences[identifier] ?? []).contains(where: { $0.page == index + 1 }) {
                    occurrences[identifier, default: []].append(.init(page: index + 1, excerpt: excerpt))
                }
                var expansion: String?
                if before.hasSuffix("(") && after.hasPrefix(")") {
                    let prefix = String(before.dropLast()).trimmingCharacters(in: .whitespaces)
                    let tail = String(prefix.suffix(180))
                    expansion = alignedExpansion(short: identifier, long: tail)
                } else if after.hasPrefix("("), let close = after.firstIndex(of: ")") {
                    let candidate = String(after[after.index(after.startIndex, offsetBy: 1)..<close])
                    if candidate.count <= 180, candidate.split(separator: " ").count >= 2,
                       let aligned = alignedExpansion(short: identifier, long: candidate), aligned == candidate {
                        expansion = candidate
                    }
                }
                if expansion == nil {
                    let pattern = #"^(?:staat\s+voor|betekent|[:=–-])\s+([^.!?;]{3,180})"#
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: after, range: NSRange(after.startIndex..., in: after)),
                       let range = Range(match.range(at: 1), in: after) {
                        let candidate = String(after[range]).trimmingCharacters(in: .whitespaces)
                        if after.lowercased().hasPrefix("staat voor") || after.lowercased().hasPrefix("betekent") {
                            expansion = candidate
                        } else if let aligned = alignedExpansion(short: identifier, long: candidate), aligned == candidate { expansion = candidate }
                    }
                }
                if let expansion, expansion.split(separator: " ").count >= 2 {
                    let definition = GlossaryEntry.Definition(text: expansion, page: index + 1)
                    if !(definitions[identifier] ?? []).contains(definition) { definitions[identifier, default: []].append(definition) }
                }
            }
        }
        return names.map { identifier, name in
            GlossaryEntry(abbreviation: name, occurrences: occurrences[identifier] ?? [], definitions: definitions[identifier] ?? [], reference: referenceMap[identifier])
        }.sorted { $0.abbreviation.localizedStandardCompare($1.abbreviation) == .orderedAscending }
    }

    /// Align letters backwards and require the first abbreviation letter to begin a word.
    static func alignedExpansion(short: String, long: String) -> String? {
        let letters = Array(short.filter(\.isLetter))
        let chars = Array(long)
        guard letters.count >= 2, !chars.isEmpty else { return nil }
        var cursor = chars.count - 1
        var start = 0
        for index in letters.indices.reversed() {
            var found = false
            while cursor >= 0 {
                if String(chars[cursor]).lowercased() == String(letters[index]).lowercased(),
                   index != 0 || cursor == 0 || !chars[cursor - 1].isLetter {
                    start = cursor; cursor -= 1; found = true; break
                }
                cursor -= 1
            }
            if !found { return nil }
        }
        let result = String(chars[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.split(separator: " ").count <= min(letters.count + 5, letters.count * 2),
              !result.contains("."), !result.contains("("), !result.contains(")") else { return nil }
        return result
    }
}
