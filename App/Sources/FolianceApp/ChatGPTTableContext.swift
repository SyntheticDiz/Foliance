import Foundation

/// Retrieves verbatim page text that can clarify a table-like source passage.
/// It never interprets cells or turns table text into a document citation.
enum ChatGPTTableContext {
    static let maximumUTF8Bytes = 8_000
    static let maximumSources = 2
    private static let contextVersion = "chatgpt-table-context-v3-footnote-link"

    private struct NumberAnchor {
        let value: String
    }

    private struct HeaderCandidate {
        let line: Int
    }

    private struct PageLine {
        let text: String
        let start: String.Index
        let afterSeparator: String.Index
    }

    /// Returns exact, contiguous text from original pages, separately attributed
    /// to its physical page. A page is eligible only when a structured numeric
    /// source quote maps to one unambiguous year/unit header and at least two
    /// ordered values plus a row-label word on that page.
    static func retrieve(pages: [String], sources: [Insight.Source]) -> [Insight.Source] {
        var result: [Insight.Source] = []
        var seenPages = Set<Int>()
        var totalBytes = 0

        for source in sources {
            guard result.count < maximumSources,
                  source.page > 0, source.page <= pages.count,
                  !seenPages.contains(source.page) else { continue }
            if isTableLike(source.quote),
               let exactPage = safePageContext(pages[source.page - 1], source: source) {
                guard totalBytes + exactPage.utf8.count <= maximumUTF8Bytes else { continue }
                result.append(Insight.Source(page: source.page, quote: exactPage))
                seenPages.insert(source.page)
                totalBytes += exactPage.utf8.count
                continue
            }
            guard let continuation = (isTableLike(source.quote) ? continuationContexts(pages: pages, source: source) : nil)
                    ?? footnoteContinuationContexts(pages: pages, source: source) else { continue }
            var additions: [Insight.Source] = []
            var canAdd = true
            for candidate in continuation {
                if let existingIndex = result.firstIndex(where: { $0.page == candidate.page }) {
                    if result[existingIndex].quote.contains(candidate.quote) { continue }
                    if candidate.quote.contains(result[existingIndex].quote) {
                        additions.append(candidate)
                    } else {
                        canAdd = false
                        break
                    }
                } else {
                    additions.append(candidate)
                }
            }
            let removedBytes = additions.reduce(0) { partial, candidate in
                partial + (result.first(where: { $0.page == candidate.page })?.quote.utf8.count ?? 0)
            }
            let newBytes = additions.reduce(0) { $0 + $1.quote.utf8.count }
            let resultingCount = result.count + additions.filter { candidate in !result.contains(where: { $0.page == candidate.page }) }.count
            guard canAdd, resultingCount <= maximumSources,
                  totalBytes - removedBytes + newBytes <= maximumUTF8Bytes else { continue }
            for candidate in additions {
                if let existingIndex = result.firstIndex(where: { $0.page == candidate.page }) {
                    totalBytes -= result[existingIndex].quote.utf8.count
                    result[existingIndex] = candidate
                } else {
                    result.append(candidate)
                }
                seenPages.insert(candidate.page)
                totalBytes += candidate.quote.utf8.count
            }
        }

        return result
    }

    /// The version is included by callers in their ChatGPT-only cache identities.
    static var cacheVersion: String { contextVersion }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isTableLike(_ text: String) -> Bool {
        let anchors = numbers(in: text).filter { !isYear($0.value) }
        guard anchors.count >= 3 else { return false }
        let separators = text.filter { $0 == ";" || $0 == "|" || $0 == "\t" }.count
        // A prose paragraph containing several numbers is not enough. Require
        // table-like delimiters, or a compact row with three values in one line.
        let compactNumericRow = text.split(whereSeparator: \.isNewline).contains { line in
            numbers(in: String(line)).filter { !isYear($0.value) }.count >= 3
        }
        return separators >= 2 || compactNumericRow
    }

    private static func safePageContext(_ page: String, source: Insight.Source) -> String? {
        guard !page.isEmpty, page.utf8.count <= maximumUTF8Bytes else {
            // Never truncate a page or a table block: a partial header/footnote
            // could make a value appear to carry a unit or condition it lacks.
            return nil
        }
        let lines = page.components(separatedBy: .newlines)
        let sourceNumbers = numbers(in: source.quote).filter { !isYear($0.value) }
        let rowLabelWords = labelWords(source.quote)
        guard sourceNumbers.count >= 3, !rowLabelWords.isEmpty else { return nil }
        let matches = headerCandidates(lines).compactMap { header -> (line: Int, distance: Int)? in
            guard let distance = matchingRowDistance(sourceNumbers, labelWords: rowLabelWords, lines: lines, headerLine: header.line) else { return nil }
            guard distance <= 40 else { return nil }
            return (header.line, distance)
        }
        let orderedDistances = matches.map(\.distance).sorted()
        guard let bestDistance = orderedDistances.first,
              orderedDistances.dropFirst().first.map({ $0 - bestDistance > 2 }) ?? true else { return nil }

        // The full page remains an exact quote and retains nearby unit notes,
        // footnotes, and distinctions between adjacent rows/tables.
        return page
    }

    /// Links a page-start continuation only when its literal row and the unique
    /// previous-page table header agree. The returned sources remain separately
    /// page-attributed; no values are assigned to columns or years.
    private static func continuationContexts(pages: [String], source: Insight.Source) -> [Insight.Source]? {
        guard source.page > 1, source.page <= pages.count,
              isTableLike(source.quote) else { return nil }
        let currentPage = pages[source.page - 1]
        let previousPage = pages[source.page - 2]
        guard currentPage.utf8.count <= maximumUTF8Bytes,
              previousPage.utf8.count <= maximumUTF8Bytes else { return nil }

        let currentLines = pageLines(currentPage)
        guard let prefixEnd = continuationPrefixEnd(currentLines), prefixEnd > currentPage.startIndex else { return nil }
        let prefix = String(currentPage[..<prefixEnd])
        let sourceValues = numbers(in: source.quote).filter { !isYear($0.value) }
        let sourceLabels = labelWords(source.quote)
        guard sourceValues.count >= 3,
              containsExactSourceRow(sourceValues, labels: sourceLabels, in: prefix) else { return nil }

        let previousLines = pageLines(previousPage)
        let candidates = headerCandidates(previousLines.map(\.text)).compactMap { header -> (titleLine: Int, unitLine: Int, rowEnd: Int)? in
            let titleWords = labelWords(previousLines[header.line].text)
            guard titleWords.count >= 2,
                  titleWords.intersection(sourceLabels).count >= 2,
                  yearTokens(in: previousLines[header.line].text).count == sourceValues.count,
                  let unitLine = (max(0, header.line - 2)...header.line).reversed().first(where: { hasExplicitUnit(previousLines[$0].text) }),
                  let rowEnd = previousTableEnd(lines: previousLines, headerLine: header.line),
                  rowEnd >= header.line else { return nil }
            return (header.line, unitLine, rowEnd)
        }
        guard candidates.count == 1, let table = candidates.first else { return nil }
        let headerStart = previousLines[table.unitLine].start
        let previousContext = String(previousPage[headerStart...])
        guard previousContext.utf8.count + prefix.utf8.count <= maximumUTF8Bytes else { return nil }

        return [Insight.Source(page: source.page - 1, quote: previousContext),
                Insight.Source(page: source.page, quote: prefix)]
    }

    /// Link a literal numbered footnote to its unique preceding subtotal row.
    /// The marker supplies identity only: numeric values and the header still
    /// pass through the existing ordered-row and unique year/unit checks.
    private static func footnoteContinuationContexts(pages: [String], source: Insight.Source) -> [Insight.Source]? {
        guard source.page > 1, source.page <= pages.count else { return nil }
        let lines = pageLines(pages[source.page - 1])
        let markers = matches(#"\(\s*(\d+)\s*\)"#, in: source.quote).map { String(source.quote[$0]) }
        guard markers.count == 1, let marker = markers.first else { return nil }
        let markerNumber = marker.filter(\.isNumber)
        guard !markerNumber.isEmpty else { return nil }

        let footnotes = lines.indices.filter { index in
            let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: #"^\(\s*"# + NSRegularExpression.escapedPattern(for: markerNumber) + #"\s*\)\s+\p{L}"#, options: [.regularExpression, .caseInsensitive]) != nil else {
                return false
            }
            // A note definition starts with the marker; a marked numeric row does not.
            return numbers(in: text).filter { !isYear($0.value) }.count <= 1
        }
        guard footnotes.count == 1, let footnoteIndex = footnotes.first else { return nil }
        let footnote = lines[footnoteIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceContainsFootnote = source.quote.components(separatedBy: .newlines)
            .contains { normalized($0) == normalized(footnote) }

        let escapedMarker = NSRegularExpression.escapedPattern(for: markerNumber)
        let subtotalRows = lines.indices.filter { index in
            guard index < footnoteIndex else { return false }
            let text = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: #"\(\s*"# + escapedMarker + #"\s*\)"#, options: .regularExpression) != nil else { return false }
            let withoutMarker = text.replacingOccurrences(of: #"\(\s*"# + escapedMarker + #"\s*\)"#,
                                                          with: "", options: .regularExpression)
            return numbers(in: withoutMarker).filter { !isYear($0.value) }.count >= 3
        }
        guard subtotalRows.count == 1, let rowIndex = subtotalRows.first,
              let headingIndex = lines.indices.reversed().first(where: {
                  $0 < rowIndex && !lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else { return nil }
        let heading = lines[headingIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard heading.range(of: #"(?i)\b(?:subtotaal|subtotal)\b"#, options: .regularExpression) != nil else { return nil }

        let row = lines[rowIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceContainsLinkedRow = normalized(source.quote).contains(normalized(heading + "\n" + row))
        guard sourceContainsFootnote || sourceContainsLinkedRow else { return nil }
        let rowWithoutMarker = row.replacingOccurrences(of: #"\(\s*"# + escapedMarker + #"\s*\)"#,
                                                        with: "", options: .regularExpression)
        let anchor = Insight.Source(page: source.page, quote: heading + "\n" + rowWithoutMarker)
        return continuationContexts(pages: pages, source: anchor)
    }

    private static func continuationPrefixEnd(_ lines: [PageLine]) -> String.Index? {
        guard let firstContent = lines.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              numbers(in: firstContent.text).filter({ !isYear($0.value) }).count >= 2 else { return nil }
        for index in lines.indices {
            let line = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if isLocalYearUnitHeader(lines, at: index) { return lines[index].start }
            if numbers(in: line).filter({ !isYear($0.value) }).count >= 2 { continue }
            if DocumentParagraphs.isHeading(line) {
                let nextContent = lines.dropFirst(index + 1).first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if let nextContent, numbers(in: nextContent.text).filter({ !isYear($0.value) }).count >= 2 {
                    continue // A short subtotal/section label inside the continued table.
                }
                return lines[index].start
            }
        }
        return lines.last?.afterSeparator
    }

    private static func isLocalYearUnitHeader(_ lines: [PageLine], at index: Int) -> Bool {
        let upper = min(lines.count - 1, index + 2)
        guard index <= upper,
              hasExplicitUnit(lines[index].text),
              lines[index...upper].contains(where: { yearTokens(in: $0.text).count >= 2 }) else { return false }
        return true
    }

    private static func containsExactSourceRow(_ values: [NumberAnchor], labels: Set<String>, in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return false }
        for start in lines.indices {
            let end = min(lines.count - 1, start + 2)
            let block = lines[start...end].joined(separator: "\n")
            let lower = block.lowercased()
            guard labels.contains(where: { word in
                lower.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, options: .regularExpression) != nil
            }) else { continue }
            let raw = numbers(in: block).filter { !isYear($0.value) }
            guard raw.count >= values.count else { continue }
            var cursor = 0
            var allMatched = true
            for value in values {
                guard cursor < raw.count,
                      let found = raw[cursor...].firstIndex(where: { equivalentNumber(value.value, $0.value) }) else {
                    allMatched = false
                    break
                }
                cursor = raw.index(after: found)
            }
            if allMatched { return true }
        }
        return false
    }

    private static func previousTableEnd(lines: [PageLine], headerLine: Int) -> Int? {
        guard headerLine + 1 < lines.count else { return nil }
        let dataRows = (headerLine + 1..<lines.count).filter { index in
            numbers(in: lines[index].text).filter({ !isYear($0.value) }).count >= 2
        }
        guard let lastRow = dataRows.last else { return nil }
        for line in lines.dropFirst(lastRow + 1) {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if isPageFooter(text) { continue }
            // Any prose after the last numeric row breaks the continuation chain.
            return nil
        }
        return lastRow
    }

    private static func isPageFooter(_ text: String) -> Bool {
        text.range(of: #"(?i)^Begroting\b.*(?:19|20|21)\d{2}.*\s\d+$"#, options: .regularExpression) != nil
    }

    private static func pageLines(_ page: String) -> [PageLine] {
        var result: [PageLine] = []
        var start = page.startIndex
        while start < page.endIndex {
            let newline = page[start...].firstIndex(of: "\n")
            let end = newline ?? page.endIndex
            let after = newline.map { page.index(after: $0) } ?? page.endIndex
            result.append(PageLine(text: String(page[start..<end]), start: start, afterSeparator: after))
            start = after
        }
        if page.isEmpty { return [] }
        if page.hasSuffix("\n") { result.append(PageLine(text: "", start: page.endIndex, afterSeparator: page.endIndex)) }
        return result
    }

    private static func headerCandidates(_ lines: [String]) -> [HeaderCandidate] {
        var result: [HeaderCandidate] = []
        for index in lines.indices {
            let years = yearTokens(in: lines[index])
            guard years.count >= 2 else { continue }
            let nearby = lines[max(0, index - 2)...min(lines.count - 1, index + 2)].joined(separator: " ")
            guard hasExplicitUnit(nearby) else { continue }
            result.append(HeaderCandidate(line: index))
        }
        return result
    }

    private static func matchingRowDistance(_ values: [NumberAnchor], labelWords: Set<String>, lines: [String], headerLine: Int) -> Int? {
        let lower = headerLine
        let upper = min(lines.count - 1, headerLine + 48)
        guard lower <= upper else { return nil }
        var bestDistance: Int?
        // Keep the row-label/value match local. A label elsewhere on the page
        // plus coincidentally repeated amounts is not enough to bind a table.
        for start in lower...upper {
            let end = min(upper, start + 2)
            let block = lines[start...end].joined(separator: "\n")
            let lowerBlock = block.lowercased()
            let hasLabel = labelWords.contains { word in
                lowerBlock.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, options: .regularExpression) != nil
            }
            guard hasLabel else { continue }
            let raw = numbers(in: block).filter { !isYear($0.value) }
            var nextRaw = 0
            var matched = 0
            for wanted in values {
                guard nextRaw < raw.count,
                      let found = raw[nextRaw...].firstIndex(where: { equivalentNumber(wanted.value, $0.value) }) else { continue }
                matched += 1
                nextRaw = raw.index(after: found)
            }
            if matched >= 2 {
                let rowLine = start + (end - start) / 2
                let distance = rowLine - headerLine
                bestDistance = min(bestDistance ?? distance, distance)
            }
        }
        return bestDistance
    }

    private static func hasExplicitUnit(_ text: String) -> Bool {
        let patterns = [
            #"(?i)x\s*€\s*1[.\s]?000\b"#,
            #"(?i)\bbedragen\s+x\s+€(?:\s|$)"#,
            #"(?i)\b(?:bedragen\s+)?(?:in\s+)?(?:miljoenen?|duizenden?)\s+euro\b"#,
            #"(?i)\b(?:percentage|procent|%)\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static func yearTokens(in text: String) -> [String] {
        matches(#"(?<!\d)(?:19|20|21)\d{2}(?!\d)"#, in: text).map { String(text[$0]) }
    }

    private static func numbers(in text: String) -> [NumberAnchor] {
        let pattern = #"(?<![\p{L}\p{N}])[-−+–]?(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d+)?%?(?![\p{L}\p{N}])"#
        return matches(pattern, in: text).map { NumberAnchor(value: String(text[$0])) }
    }

    private static func matches(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text) }
    }

    private static func isYear(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == 4 && (digits.hasPrefix("19") || digits.hasPrefix("20") || digits.hasPrefix("21"))
    }

    static func equivalentNumber(_ lhs: String, _ rhs: String) -> Bool {
        func canonical(_ value: String) -> (String, Bool)? {
            let negative = value.contains(where: { "−–-".contains($0) })
            let percent = value.contains("%")
            var number = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            if number.contains(",") {
                // Dutch notation uses comma decimals and dots as group marks.
                number = number.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else if number.contains(".") {
                let groups = number.split(separator: ".", omittingEmptySubsequences: false)
                let groupedThousands = groups.count > 1 && groups.dropFirst().allSatisfy { $0.count == 3 }
                if groupedThousands { number = groups.joined() }
            }
            guard let decimal = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let signed = negative ? -decimal : decimal
            return (NSDecimalNumber(decimal: signed).stringValue, percent)
        }
        guard let left = canonical(lhs), let right = canonical(rhs) else { return false }
        return left.0 == right.0 && left.1 == right.1
    }

    private static func labelWords(_ text: String) -> Set<String> {
        let stop = Set(["de", "het", "een", "van", "voor", "met", "bij", "als", "dan", "in", "op", "aan", "is", "zijn", "was", "wordt", "bedraagt", "bedragen", "x", "euro"])
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return Set(words.filter { $0.count >= 5 && !stop.contains($0) })
    }
}
