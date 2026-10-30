import Foundation
import SnowballDutch
import RapidFuzzNative

/// Optional, additive search assistance. The exact UnifiedSearch path remains authoritative.
struct SearchAssistanceResponse: Sendable {
    /// Contiguous token matches with equal Dutch Snowball stems. The UI must label these separately.
    let wordFormHits: [SearchHit]
    /// Explanatory candidates only; selecting one should replace the query and run ordinary exact search.
    let suggestions: [String]
}

/// Immutable vocabulary and token snapshot for one records revision.
struct SearchAssistanceIndex: Sendable {
    private struct Token: Sendable {
        let original: String
        let folded: String
        let stem: String
        let start: String.Index
        let end: String.Index
    }

    private struct TokenSlice: Sendable {
        let value: String
        let start: String.Index
        let end: String.Index
    }

    private struct IndexedRecord: Sendable {
        let record: SearchRecord
        let tokens: [Token]
    }

    private struct VocabularyEntry: Sendable {
        let folded: String
        let display: String
        let stem: String
        let frequency: Int
        let allUppercase: Bool
    }

    private let records: [IndexedRecord]
    private let vocabulary: [String: VocabularyEntry]

    private init(records: [IndexedRecord], vocabulary: [String: VocabularyEntry]) {
        self.records = records
        self.vocabulary = vocabulary
    }

    static func build(
        records sourceRecords: [SearchRecord],
        cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> SearchAssistanceIndex {
        let stemmer = try DutchStemmer()
        var indexedRecords: [IndexedRecord] = []
        indexedRecords.reserveCapacity(sourceRecords.count)
        var mutableVocabulary: [String: (display: String, stem: String, frequency: Int, allUppercase: Bool)] = [:]

        for (recordIndex, record) in sourceRecords.enumerated() {
            if recordIndex & 31 == 0, cancellationCheck() { throw CancellationError() }
            let slices = try tokenSlices(in: record.searchable, cancellationCheck: cancellationCheck)
            var tokens: [Token] = []
            tokens.reserveCapacity(slices.count)
            for (tokenIndex, item) in slices.enumerated() {
                if tokenIndex & 255 == 0, cancellationCheck() { throw CancellationError() }
                let lower = item.value.lowercased(with: dutchLocale)
                let stem = try stemmer.stem(lower)
                tokens.append(Token(original: item.value, folded: fold(item.value), stem: stem,
                                    start: item.start, end: item.end))
            }
            for (tokenIndex, token) in tokens.enumerated() {
                if tokenIndex & 255 == 0, cancellationCheck() { throw CancellationError() }
                if let existing = mutableVocabulary[token.folded] {
                    mutableVocabulary[token.folded] = (
                        display: existing.display,
                        stem: existing.stem,
                        frequency: existing.frequency + 1,
                        allUppercase: existing.allUppercase && isUppercaseAcronym(token.original)
                    )
                } else {
                    mutableVocabulary[token.folded] = (
                        display: token.original,
                        stem: token.stem,
                        frequency: 1,
                        allUppercase: isUppercaseAcronym(token.original)
                    )
                }
            }
            indexedRecords.append(IndexedRecord(record: record, tokens: tokens))
        }
        if cancellationCheck() { throw CancellationError() }
        let vocabulary = Dictionary(uniqueKeysWithValues: mutableVocabulary.map { key, value in
            (key, VocabularyEntry(folded: key, display: value.display, stem: value.stem,
                                  frequency: value.frequency, allUppercase: value.allUppercase))
        })
        return SearchAssistanceIndex(records: indexedRecords, vocabulary: vocabulary)
    }

    func search(
        query: String,
        includeWordForms: Bool,
        cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> SearchAssistanceResponse {
        if cancellationCheck() { throw CancellationError() }
        let suggestions = try typoSuggestions(for: query, cancellationCheck: cancellationCheck)
        guard includeWordForms, Self.expansionAllowed(query) else {
            return SearchAssistanceResponse(wordFormHits: [], suggestions: suggestions)
        }

        let queryTokens = Self.wordTokens(in: UnifiedSearch.normalized(query)).map(\.value)
        guard !queryTokens.isEmpty else { return SearchAssistanceResponse(wordFormHits: [], suggestions: suggestions) }
        let stemmer = try DutchStemmer()
        let queryStems = try queryTokens.map { try stemmer.stem($0.lowercased(with: Self.dutchLocale)) }
        var hits: [SearchHit] = []
        hits.reserveCapacity(min(records.count, 64))

        for (recordIndex, indexed) in records.enumerated() {
            if recordIndex & 31 == 0, cancellationCheck() { throw CancellationError() }
            let width = queryStems.count
            guard indexed.tokens.count >= width else { continue }
            for startIndex in 0...(indexed.tokens.count - width) {
                if startIndex & 63 == 0, cancellationCheck() { throw CancellationError() }
                var matches = true
                for tokenIndex in 0..<width {
                    if tokenIndex & 255 == 0, cancellationCheck() { throw CancellationError() }
                    if indexed.tokens[startIndex + tokenIndex].stem != queryStems[tokenIndex] {
                        matches = false
                        break
                    }
                }
                guard matches else { continue }
                let first = indexed.tokens[startIndex]
                let last = indexed.tokens[startIndex + width - 1]
                guard try Self.gapIsOnlyWhitespace(in: indexed.record.searchable, tokens: indexed.tokens,
                                                   from: startIndex, through: startIndex + width - 1,
                                                   cancellationCheck: cancellationCheck) else { continue }
                hits.append(SearchHit(record: indexed.record,
                                      excerpt: Self.excerpt(in: indexed.record.searchable, around: first.start..<last.end)))
                break // One literal source passage per record, in record order.
            }
        }
        if cancellationCheck() { throw CancellationError() }
        return SearchAssistanceResponse(wordFormHits: hits, suggestions: suggestions)
    }

    /// Matches the frozen method's hard boundary for both word-form and typo assistance.
    static func expansionAllowed(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    /// Whether this query can produce any optional assistance and should pay index-build cost.
    static func needsIndex(query: String, includeWordForms: Bool) -> Bool {
        guard expansionAllowed(query) else { return false }
        if includeWordForms { return true }
        let tokens = wordTokens(in: UnifiedSearch.normalized(query))
        guard tokens.count == 1 else { return false }
        return tokens[0].value.unicodeScalars.count >= 5 && !isUppercaseAcronym(tokens[0].value)
    }

    private func typoSuggestions(for query: String,
                                 cancellationCheck: @Sendable () -> Bool) throws -> [String] {
        guard Self.expansionAllowed(query) else { return [] }
        let queryTokens = Self.wordTokens(in: UnifiedSearch.normalized(query))
        guard queryTokens.count == 1 else { return [] }
        let token = queryTokens[0].value
        let foldedQuery = Self.fold(token)
        guard foldedQuery.unicodeScalars.count >= 5, !Self.isUppercaseAcronym(token),
              !vocabulary.keys.contains(foldedQuery) else { return [] }

        let stemmer = try DutchStemmer()
        let queryStem = try stemmer.stem(token.lowercased(with: Self.dutchLocale))
        let queryScalars = foldedQuery.unicodeScalars.map(\.value)
        var candidates: [(value: String, display: String, distance: Int, frequency: Int)] = []
        candidates.reserveCapacity(8)
        for (index, entry) in vocabulary.values.enumerated() {
            if index & 127 == 0, cancellationCheck() { throw CancellationError() }
            let folded = entry.folded
            guard folded.unicodeScalars.count >= 5,
                  !entry.allUppercase,
                  entry.stem != queryStem else { continue }
            let candidateScalars = folded.unicodeScalars.map(\.value)
            let distance = Self.distance(queryScalars, candidateScalars, cutoff: 1)
            guard distance <= 1 else { continue }
            candidates.append((folded, entry.display, Int(distance), entry.frequency))
        }
        candidates.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.value < $1.value
        }
        return Array(candidates.prefix(5).map(\.display))
    }

    private static func distance(_ left: [UInt32], _ right: [UInt32], cutoff: Int) -> Int {
        left.withUnsafeBufferPointer { lhs in
            right.withUnsafeBufferPointer { rhs in
                Int(foliance_levenshtein_scalars(lhs.baseAddress, lhs.count, rhs.baseAddress, rhs.count, cutoff))
            }
        }
    }

    private static func wordTokens(in text: String) -> [(value: String, start: String.Index, end: String.Index)] {
        (try? tokenSlices(in: text, cancellationCheck: { false }).map { ($0.value, $0.start, $0.end) }) ?? []
    }

    private static func tokenSlices(in text: String,
                                    cancellationCheck: @Sendable () -> Bool) throws -> [TokenSlice] {
        let scalars = text.unicodeScalars
        var result: [TokenSlice] = []
        var cursor = scalars.startIndex
        var scannedScalars = 0
        while cursor < scalars.endIndex {
            if scannedScalars & 255 == 0, cancellationCheck() { throw CancellationError() }
            if !CharacterSet.letters.contains(scalars[cursor]) {
                cursor = scalars.index(after: cursor)
                scannedScalars += 1
                continue
            }
            let start = cursor
            cursor = scalars.index(after: cursor)
            scannedScalars += 1
            while cursor < scalars.endIndex {
                if scannedScalars & 255 == 0, cancellationCheck() { throw CancellationError() }
                if !CharacterSet.letters.contains(scalars[cursor]) { break }
                cursor = scalars.index(after: cursor)
                scannedScalars += 1
            }
            let end = cursor
            let value = String(String.UnicodeScalarView(scalars[start..<end]))
            result.append(TokenSlice(value: value, start: start, end: end))
        }
        return result
    }

    private static func gapIsOnlyWhitespace(in text: String, tokens: [Token], from first: Int, through last: Int,
                                            cancellationCheck: @Sendable () -> Bool) throws -> Bool {
        guard last > first else { return true }
        for index in first..<last {
            if index & 255 == 0, cancellationCheck() { throw CancellationError() }
            let gap = text[tokens[index].end..<tokens[index + 1].start]
            if !gap.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { return false }
        }
        return true
    }

    private static func excerpt(in text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -55, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: dutchLocale)
    }

    private static func isUppercaseAcronym(_ value: String) -> Bool {
        value == value.uppercased(with: dutchLocale) && value != value.lowercased(with: dutchLocale)
    }

    private static let dutchLocale = Locale(identifier: "nl_NL")
}

private final class DutchStemmer {
    private let handle: OpaquePointer

    init() throws {
        guard let handle = foliance_dutch_stemmer_create() else { throw SearchAssistanceError.stemmerUnavailable }
        self.handle = handle
    }

    deinit { foliance_dutch_stemmer_destroy(handle) }

    func stem(_ value: String) throws -> String {
        let input = Array(value.utf8)
        var output = [CChar](repeating: 0, count: max(input.count * 2 + 16, 16))
        func runStemmer() -> Int {
            input.withUnsafeBufferPointer { source in
                guard let sourceBase = source.baseAddress else { return Int.max }
                return output.withUnsafeMutableBufferPointer { destination in
                    foliance_dutch_stemmer_stem(handle, UnsafeRawPointer(sourceBase).assumingMemoryBound(to: CChar.self),
                                            source.count, destination.baseAddress, destination.count)
                }
            }
        }
        var length = runStemmer()
        // Clang imports size_t as Int on this platform; SIZE_MAX may arrive as -1.
        guard length >= 0, length != Int.max else { throw SearchAssistanceError.stemmingFailed }
        if length > output.count {
            output = [CChar](repeating: 0, count: length)
            length = runStemmer()
        }
        guard length >= 0, length != Int.max, length <= output.count else { throw SearchAssistanceError.stemmingFailed }
        return String(decoding: output.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

private enum SearchAssistanceError: Error {
    case stemmerUnavailable
    case stemmingFailed
}
