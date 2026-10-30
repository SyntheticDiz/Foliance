import Foundation
import CryptoKit
import FolianceCore

enum LocalCache {
    @TaskLocal static var overrideDirectory: URL? = nil
    static func key(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static var directory: URL { overrideDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Foliance/analysis-v2") }
    static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")),
              let value = try? JSONDecoder().decode(type, from: data) else {
            AnalysisMetrics.current?.cache(AnalysisMetrics.phase, hit: false)
            return nil
        }
        AnalysisMetrics.current?.cache(AnalysisMetrics.phase, hit: true)
        return value
    }
    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
    }
}

enum AnalysisPipeline {
    /// Split on paragraph/sentence boundaries where possible, preserving every character and page.
    static func chunks(_ pages: [String], limit: Int = 1800) -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        for (page, source) in pages.enumerated() {
            var remaining = source[...]
            while !remaining.isEmpty {
                var end = remaining.startIndex
                var bytes = 0
                while end < remaining.endIndex {
                    let next = remaining.index(after: end)
                    let size = remaining[end..<next].utf8.count
                    if bytes + size > limit && end != remaining.startIndex { break }
                    bytes += size; end = next
                }
                if end < remaining.endIndex {
                    let prefix = remaining[..<end]
                    if let paragraph = prefix.range(of: "\n\n", options: .backwards), paragraph.upperBound > prefix.index(prefix.startIndex, offsetBy: prefix.count / 3) {
                        end = paragraph.upperBound
                    } else if let sentence = prefix.range(of: #"[.!?]\s+"#, options: [.regularExpression, .backwards]), sentence.upperBound > prefix.index(prefix.startIndex, offsetBy: prefix.count / 3) {
                        end = sentence.upperBound
                    } else if let space = prefix.lastIndex(where: { $0.isWhitespace }) { end = remaining.index(after: space) }
                }
                let text = String(remaining[..<end])
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.init(page: page, text: text)) }
                remaining = remaining[end...]
            }
        }
        return result
    }
    static func isCandidate(_ text: String, focus: String, hasProgram: Bool) -> Bool {
        let lower = text.lowercased()
        let concrete = lower.range(of: #"\d|€|besluit|voorstel|verhog|verlag|schrap|bezuinig|invest|invoer|afschaf|betaal|kost|budget|subsid|maatregel|regeling|bouwen|vaststell|verplicht|uitvoer"#, options: .regularExpression) != nil
        guard concrete else { return false }
        if hasProgram { return true }
        let details = focus.components(separatedBy: "\n").filter { !$0.hasPrefix("Beperk de selectie tot") && !$0.hasPrefix("Geef deze aandachtspunten voorrang") }.joined(separator: " ")
        var terms = details.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 3 }
        if focus.isEmpty || focus.hasPrefix("Geef deze aandachtspunten voorrang") { terms += Theme.defaults.flatMap(\.keywords) }
        return terms.contains { lower.contains($0.lowercased()) }
    }
    static func normalized(_ text: String) -> String { text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    static func merge(_ points: [Insight]) -> [Insight] {
        var result: [Insight] = []
        for point in points {
            if let index = result.firstIndex(where: {
                normalized($0.quote) == normalized(point.quote) && $0.programSource == point.programSource
            }) {
                var existing = result[index]
                var sources = existing.otherSources ?? []
                if existing.page != point.page && !sources.contains(where: { $0.page == point.page && $0.quote == point.quote }) {
                    sources.append(.init(page: point.page, quote: point.quote))
                }
                existing.otherSources = sources; result[index] = existing
            } else { result.append(point) }
        }
        return result
    }
}
