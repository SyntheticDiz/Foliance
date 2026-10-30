import Foundation

/// Literal retrieval cues over the exact stored source text. This is a reading aid,
/// not a legal or factual assessment. All locations use NSString/NSRegularExpression
/// UTF-16 offsets so they can be applied directly to SwiftUI text selections.
enum SourceAidCategory: String, CaseIterable, Hashable, Sendable {
    case dates
    case amounts
    case conditions
}

enum SourceReadingAid {
    struct Anchor: Identifiable, Hashable, Sendable {
        let id: Int
        let category: SourceAidCategory
        let range: NSRange
        let text: String
        let contextRanges: [NSRange]
    }

    struct Result: Sendable {
        /// The exact input string, retained verbatim for callers that need source text.
        let fullText: String
        let anchors: [Anchor]
    }

    private struct Hit: Hashable {
        let range: NSRange
        let category: SourceAidCategory
    }

    private static let months = "januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december|january|february|march|april|may|june|july|august|september|october|november|december"
    private static let number = #"(?:\d{1,3}(?:[., ]\d{3})+|\d+)(?:[,.]\d+)?"#
    private static let numericDate = #"\d{1,2}[-/.]\d{1,2}(?:[-/.](?:\d{2}|\d{4}))?"#
    private static let regexCache = NSCache<NSString, NSRegularExpression>()

    private static func regex(_ pattern: String) -> NSRegularExpression {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) { return cached }
        // Every pattern is built from fixed lexical expressions and validated by focused tests.
        let compiled = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) ?? (try! NSRegularExpression(pattern: #"(?!)"#))
        regexCache.setObject(compiled, forKey: key)
        return compiled
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        regex(pattern).matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard range.location != NSNotFound, NSMaxRange(range) <= (text as NSString).length else { return "" }
        return (text as NSString).substring(with: range)
    }

    private static func trim(_ text: String, _ range: NSRange) -> NSRange {
        let ns = text as NSString
        var start = range.location, end = NSMaxRange(range)
        while start < end {
            guard let scalar = UnicodeScalar(ns.character(at: start)), CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            start += 1
        }
        while end > start {
            guard let scalar = UnicodeScalar(ns.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    static func analyze(_ text: String) -> Result {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var hits: Set<Hit> = []
        let currencyPattern = #"(?<!\w)(?:€\s*"# + number + #"|"# + number + #"\s*(?:€|euro(?:'s)?|eur)|(?:EUR|USD|GBP|\$|£|dollar(?:s)?|pond(?:en)?)\s*"# + number + #"|"# + number + #"\s*(?:EUR|USD|GBP|\$|£|dollar(?:s)?|pond(?:en)?))(?!\w)"#
        let currency = regex(currencyPattern).matches(in: text, range: full).map(\.range)
        let datePattern = #"(?<!\w)(?:\d{1,2}[-/.]\d{1,2}(?:[-/.](?:\d{2}|\d{4}))?|\d{1,2}\s+(?:"# + months + #")(?:\s+\d{4})?|(?:"# + months + #")\s+\d{1,2}(?:,\s+\d{4})?|(?:"# + months + #")\s+\d{4})(?!\w)"#
        var dateRanges: [NSRange] = []
        for m in matches(datePattern, in: text) {
            let r = m.range, value = substring(text, r)
            if matches("^" + numericDate + "$", in: value).isEmpty == false {
                let parts = value.split(whereSeparator: { "-/.".contains($0) })
                guard parts.count >= 2, let day = Int(parts[0]), let month = Int(parts[1]), (1...31).contains(day), (1...12).contains(month),
                      !currency.contains(where: { NSIntersectionRange($0, r).length > 0 }),
                      matches(#"(?i)\b(?:art(?:ikel)?\.?|versie)\s*$"#, in: substring(text, NSRange(location: max(0, r.location - 32), length: min(32, r.location)))).isEmpty else { continue }
            }
            dateRanges.append(r); hits.insert(Hit(range: r, category: .dates))
        }
        let periodPattern = #"(?<!\w)(?:binnen\s+(?:de\s+)?\d+\s+(?:werk)?dagen?|binnen\s+\d+\s+(?:weken?|maanden?|ja(?:ar|ren))|(?:binnen|uiterlijk|no\s+later\s+than)\s+(?:een|twee|drie|vier|vijf|zes|acht|tien|dertig|negentig|\d+)\s+(?:werk)?(?:dagen?|weken?|maanden?|ja(?:ar|ren))|\d+\s*(?:werk)?dagen?|\d+\s*(?:kalender)?weken?|\d+\s*(?:kalender)?maanden?|\d+\s*(?:kalender)?ja(?:ar|ren)|\d+\s+jaar\s+(?:eerder|later)|\d+\s*(?:werk)?uren?|na\s+die\s+datum|(?:een|twee|drie|vier|vijf|zes|acht|tien|dertig|negentig)\s+(?:dagen?|weken?|maanden?|ja(?:ar|ren))|(?:eerste|tweede|derde|laatste)\s+helft\s+van\s+(?:19|20|21)\d{2}|periode\s+(?:19|20|21)\d{2}(?:\s+en\s+(?:19|20|21)\d{2})?|(?:per|vanaf|sinds|in|met\s+ingang\s+van)\s+(?:"# + months + #")\s+(?:19|20|21)\d{2}|(?:uiterlijk|voor|vóór|tot(?:\s+en\s+met)?|vanaf|sinds|per|over|until|not\s+before|no\s+later\s+than|by|before|after|on\s+or\s+before|starting\s+on|beginning\s+on)\s+(?:"# + numericDate + #"|\d{4}|\d{1,2}\s+(?:"# + months + #")(?:,?\s+\d{4})?)|(?!\w)tot\s+(?:en\s+met\s+)?\d{1,2}\s+(?:"# + months + #")\s+\d{4})(?!\w)"#
        var periodRanges: [NSRange] = []
        for m in matches(periodPattern, in: text) {
            let range = m.range
            if let numeric = regex(numericDate).firstMatch(in: substring(text, range), range: NSRange(location: 0, length: range.length)) {
                let value = substring(text, NSRange(location: range.location + numeric.range.location, length: numeric.range.length))
                if !isPlausibleNumericDate(value) { continue }
            }
            periodRanges.append(range); hits.insert(Hit(range: range, category: .dates))
        }
        let yearPattern = #"(?<!\w)(?:19|20|21)\d{2}(?!\w)"#
        let yearCue = regex(#"(?i)\b(?:in|van|tot|vanaf|sinds|voor|per|gedurende|tussen|meetjaar|peiljaar|boekjaar|begrotingsjaar|schooljaar|monitor|peiling|cijfers|vorig|afgelopen|laatste|periode|uitvoering|overeenkomst|during|from|since|until|before|after|by|reporting\s+year|fiscal\s+year|calendar\s+year|school\s+year|survey|delivery|agreement|\d{1,2}[-/.])\b"#)
        for m in matches(yearPattern, in: text) {
            let r = m.range
            if (dateRanges + periodRanges).contains(where: { $0.location <= r.location && NSMaxRange($0) >= NSMaxRange(r) }) { continue }
            let around = NSRange(location: max(0, r.location - 48), length: min(ns.length - max(0, r.location - 48), r.length + 96))
            guard !yearCue.matches(in: text, range: around).isEmpty else { continue }
            hits.insert(Hit(range: expandedYear(text, r), category: .dates))
        }
        let temporal = #"(?i)(?:\b(?:vorig|afgelopen|dit|volgend|last|previous|this|next|current)\s+jaar\b|\b(?:laatste|huidige|eerdere|nieuwe|latest|current|previous|new)\s+(?:\w+\s+){0,2}(?:peiling|monitor|cijfers|begrotingsjaar|schooljaar|survey|report|results|data)\b|\b(?:eerste|tweede|derde|laatste|first|second|third|last)\s+helft\s+van\s+(?:19|20|21)\d{2}\b|\b(?:periode|period)\s+(?:19|20|21)\d{2}(?:\s+en\s+(?:19|20|21)\d{2})?\b|\bmeerjarenovereenkomst\b.{0,100}?\b(?:19|20|21)\d{2}\s+en\s+(?:19|20|21)\d{2}\b)"#
        for m in matches(temporal, in: text) { hits.insert(Hit(range: m.range, category: .dates)) }
        for r in currency { hits.insert(Hit(range: r, category: .amounts)) }
        let condition = #"(?i)(?<!\w)(?:niet\s+meer\s+(?:is|ligt)\s+dan|niet\s+later\s+dan|lager\s+(?:is|ligt)\s+dan|minder\s+dan|meer\s+dan|ten\s+minste|maximaal|hoogstens|ten\s+hoogste|precies|geen\s+minimum(?:\s+aan\s+\w+)?|vrijwillige\s+keuze|blijven\s+bestaan|met\s+de\s+vaststelling|met\s+uitzondering\s+van|als\s+gevolg\s+van|op\s+voorwaarde\s+dat|onder\s+voorwaarde\s+dat|voor\s+zover|ingeval(?:\s+van)?|aangezien|omdat|vanwege|doordat|wegens|want|indien|mits|tenzij|behoudens|als(?=\s+(?:de|het|een|er|dit|dat|hij|zij|zijne|inwoners|aanvrager)\b)|wanneer|zodra|zolang|uitsluitend|alleen|enkel|behalve|uitgezonderd|exclusief|beschikbaarheid|beschikbaar|vrijwillig|voorstel|voorgesteld|besloten|besluit|geadviseerd|advies|voornemen|beoogd|vastgesteld|wordt\s+vastgesteld|kan|moet|niet|geen|zonder|minimaal|lager|minder|if|unless|only|except|exception|no|not|without|proposal|proposed|decide|decision|approved|approval|confirmed|confirmation|commitment|committed|intends?|plans?\s+to|owner|action\s+owner|task\s+lead|assigned\s+to|responsible\s+(?:for|party)|eigenaar|verantwoordelijke|toegewezen\s+aan|uitvoerder)(?!\w)"#
        for m in matches(condition, in: text) { hits.insert(Hit(range: m.range, category: .conditions)) }

        let paragraphs = paragraphRanges(text)
        let special = specialRanges(text)
        let sortedHits = hits.sorted { $0.range.location == $1.range.location ? $0.range.length < $1.range.length : $0.range.location < $1.range.location }
        var paragraphIndex = 0
        var paragraphForHit: [Int] = []
        for hit in sortedHits {
            while paragraphIndex + 1 < paragraphs.count, NSMaxRange(paragraphs[paragraphIndex]) <= hit.range.location { paragraphIndex += 1 }
            paragraphForHit.append(paragraphIndex)
        }
        var hitsByParagraph: [Int: [Hit]] = [:]
        for (index, hit) in sortedHits.enumerated() { hitsByParagraph[paragraphForHit[index], default: []].append(hit) }
        let conditionalParagraphs = Set(hitsByParagraph.compactMap { index, paragraphHits in
            paragraphHits.contains(where: { $0.category == .conditions }) ? index : nil
        })
        let sentencesByParagraph = Dictionary(uniqueKeysWithValues: paragraphs.enumerated().map { ($0.offset, sentenceRanges(text, $0.element)) })
        let anchors = sortedHits.enumerated().map { index, hit in
            let context = contexts(for: hit, paragraphIndex: paragraphForHit[index], text: text, paragraphs: paragraphs,
                                   conditionalParagraphs: conditionalParagraphs, special: special,
                                   sentences: sentencesByParagraph[paragraphForHit[index]] ?? [])
            return Anchor(id: index, category: hit.category, range: hit.range, text: substring(text, hit.range), contextRanges: context)
        }
        return Result(fullText: text, anchors: anchors)
    }

    private static func expandedYear(_ text: String, _ range: NSRange) -> NSRange {
        let left = substring(text, NSRange(location: max(0, range.location - 130), length: min(130, range.location)))
        let cue = matches(#"(?i)(?:\b(?:cijfers\s+zijn\s+van\s+|peiling\s+van\s+|monitor\s+van\s+|begrotingsjaar\s+|schooljaar\s+|boekjaar\s+|kalenderjaar\s+|meetjaar\s+|periode\s+))$|\b(?:in|over|van|per|vanaf|sinds|tot(?:\s+en\s+met)?|op)\s+$"#, in: left).last
        guard let cue else { return range }
        return NSRange(location: range.location - cue.range.length, length: range.length + cue.range.length)
    }

    private static func isPlausibleNumericDate(_ value: String) -> Bool {
        let parts = value.split(whereSeparator: { "-/.".contains($0) })
        guard parts.count >= 2, let day = Int(parts[0]), let month = Int(parts[1]) else { return false }
        return (1...31).contains(day) && (1...12).contains(month)
    }

    private static func paragraphRanges(_ text: String) -> [NSRange] {
        matches(#"(?s)\S(?:.*?\S)?(?=\r?\n[ \t]*\r?\n|\z)"#, in: text).map(\.range)
    }

    private static func contexts(for hit: Hit, paragraphIndex: Int, text: String, paragraphs: [NSRange],
                                 conditionalParagraphs: Set<Int>, special: [NSRange], sentences: [NSRange]) -> [NSRange] {
        guard paragraphs.indices.contains(paragraphIndex) else { return [hit.range] }
        let paragraph = paragraphs[paragraphIndex]
        let touchedSpecial = special.filter { $0.location <= hit.range.location && NSMaxRange($0) >= NSMaxRange(hit.range) }
        if conditionalParagraphs.contains(paragraphIndex) {
            var ranges = [paragraph] + touchedSpecial
            let leading = substring(text, trim(text, paragraph))
            if paragraphIndex > 0,
               !matches(#"(?i)^(?:vanwege|omdat|doordat|aangezien|want|hierdoor|daardoor|dit maakt|als gevolg daarvan)\b"#, in: leading).isEmpty {
                ranges.append(paragraphs[paragraphIndex - 1])
            }
            return union(ranges)
        }
        if let block = touchedSpecial.first { return [block] }
        guard let startIndex = sentences.firstIndex(where: { $0.location <= hit.range.location && NSMaxRange($0) >= NSMaxRange(hit.range) }) else { return [paragraph] }
        var selected: Set<Int> = [startIndex]
        let dependency = regex(#"(?i)^\s*(?:hierdoor|daardoor|daarom|dit|deze|die|dat|daarmee|als gevolg daarvan|om die reden|vervolgens|tegelijkertijd|desondanks|echter|maar|wel|alleen|uitsluitend|mits|tenzij|behoudens|uitgezonderd|met uitzondering van|niettemin)\b"#)
        var changed = true
        while changed {
            changed = false
            for i in Array(selected) {
                if i > 0, !dependency.matches(in: text, range: sentences[i]).isEmpty, selected.insert(i - 1).inserted { changed = true }
                if i + 1 < sentences.count, !dependency.matches(in: text, range: sentences[i + 1]).isEmpty, selected.insert(i + 1).inserted { changed = true }
            }
        }
        let chosen = selected.sorted().map { sentences[$0] }
        var merged: [NSRange] = []
        for r in chosen {
            if let last = merged.last, NSMaxRange(last) == r.location { merged[merged.count - 1] = NSUnionRange(last, r) }
            else { merged.append(r) }
        }
        return merged
    }

    private static func union(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location == $1.location ? $0.length < $1.length : $0.location < $1.location }
        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, range.location <= NSMaxRange(last) { result[result.count - 1] = NSUnionRange(last, range) }
            else { result.append(range) }
        }
        return result
    }

    private static func sentenceRanges(_ text: String, _ paragraph: NSRange) -> [NSRange] {
        let piece = substring(text, paragraph), base = paragraph.location
        let boundary = regex(#"[.!?](?=(?:[\"'’”)]*)\s+(?:[A-ZÀ-ÖØ-Þ0-9(\"'“]))"#)
        var ends = boundary.matches(in: piece, range: NSRange(location: 0, length: (piece as NSString).length)).compactMap { result -> Int? in
            let pos = result.range.location
            let chars = piece as NSString
            if chars.character(at: pos) == 46, pos > 0, pos + 1 < chars.length,
               (48...57).contains(chars.character(at: pos - 1)), (48...57).contains(chars.character(at: pos + 1)) { return nil }
            return NSMaxRange(result.range)
        }
        ends.append((piece as NSString).length)
        var ranges: [NSRange] = [], cursor = 0
        for end in ends where end > cursor {
            let local = trim(piece, NSRange(location: cursor, length: end - cursor))
            if local.length > 0 { ranges.append(NSRange(location: base + local.location, length: local.length)) }
            cursor = end
        }
        return ranges.isEmpty ? [paragraph] : ranges
    }

    /// Keep list introductions and table headings with the matching source rows.
    private static func specialRanges(_ text: String) -> [NSRange] {
        var lines: [(Int, Int, String)] = [], position = 0
        let ns = text as NSString
        while position < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: position, length: 0))
            var contentEnd = NSMaxRange(lineRange)
            while contentEnd > lineRange.location {
                guard let scalar = UnicodeScalar(ns.character(at: contentEnd - 1)), CharacterSet.newlines.contains(scalar) else { break }
                contentEnd -= 1
            }
            lines.append((lineRange.location, contentEnd, ns.substring(with: NSRange(location: lineRange.location, length: contentEnd - lineRange.location))))
            position = NSMaxRange(lineRange)
        }
        let marker = regex(#"^\s*(?:(?:[-*•‣▪]|–|—)\s+|(?:\(?\d{1,3}\)?[.)]|[a-zA-Z][.)])\s+)"#)
        let table = regex(#"\||\t| {3,}"#)
        var ranges: [NSRange] = []
        let marked = lines.enumerated().filter { !$0.element.2.trimmingCharacters(in: .whitespaces).isEmpty && marker.firstMatch(in: $0.element.2, range: NSRange(location: 0, length: ($0.element.2 as NSString).length)) != nil }
        var listGroups: [[(offset: Int, element: (Int, Int, String))]] = []
        for item in marked {
            guard let previous = listGroups.last?.last else { listGroups.append([item]); continue }
            let between = lines[(previous.offset + 1)..<item.offset]
            let nonempty = between.filter { !$0.2.trimmingCharacters(in: .whitespaces).isEmpty }
            let blanks = between.count - nonempty.count
            let wrapped = nonempty.count <= 3 && nonempty.allSatisfy { $0.2.first?.isWhitespace == true }
            if (nonempty.isEmpty && blanks <= 2) || (blanks == 0 && wrapped) { listGroups[listGroups.count - 1].append(item) }
            else { listGroups.append([item]) }
        }
        for group in listGroups {
            guard let first = group.first, let last = group.last else { continue }
            var start = first.element.0, end = last.element.1
            // Preserve a nearby title and lead-in, even when the PDF separates them with blank lines.
            if let leadIndex = lines[..<first.offset].lastIndex(where: { !$0.2.trimmingCharacters(in: .whitespaces).isEmpty }) {
                let lead = lines[leadIndex]
                if lead.2.count <= 260 { start = lead.0 }
                if leadIndex > 0,
                   let titleIndex = lines[..<leadIndex].lastIndex(where: { !$0.2.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    let title = lines[titleIndex].2.trimmingCharacters(in: .whitespaces)
                    if title.count <= 120 && title.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:")) == nil { start = lines[titleIndex].0 }
                }
            }
            var i = last.offset + 1
            while i < lines.count, !lines[i].2.trimmingCharacters(in: .whitespaces).isEmpty,
                  marker.firstMatch(in: lines[i].2, range: NSRange(location: 0, length: (lines[i].2 as NSString).length)) == nil {
                end = lines[i].1; i += 1
            }
            ranges.append(NSRange(location: start, length: max(0, end - start)))
        }
        let tableLines = lines.enumerated().filter { !$0.element.2.trimmingCharacters(in: .whitespaces).isEmpty && table.firstMatch(in: $0.element.2, range: NSRange(location: 0, length: ($0.element.2 as NSString).length)) != nil }
        if tableLines.count >= 2, let first = tableLines.first, let last = tableLines.last {
            let before = lines[..<first.offset].last(where: { !$0.2.trimmingCharacters(in: .whitespaces).isEmpty })
            let after = lines.dropFirst(last.offset + 1).first(where: { !$0.2.trimmingCharacters(in: .whitespaces).isEmpty })
            let start = before?.0 ?? first.element.0, end = after?.1 ?? last.element.1
            ranges.append(NSRange(location: start, length: max(0, end - start)))
        }
        return ranges
    }
}
