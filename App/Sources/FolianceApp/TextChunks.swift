import Foundation

struct DocumentChunk: Sendable { let page: Int; let text: String }

/// Overlapping text windows for local programme retrieval; page indexes remain zero-based.
enum TextChunks {
    static func chunks(_ pages: [String], maxBytes: Int = 2000) -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        for (page, text) in pages.enumerated() {
            let chars = Array(text)
            var start = 0
            while start < chars.count {
                var end = start
                var bytes = 0
                while end < chars.count && bytes + String(chars[end]).utf8.count <= maxBytes {
                    bytes += String(chars[end]).utf8.count
                    end += 1
                }
                if end == start { end += 1 }
                let fragment = String(chars[start..<end])
                if !fragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(DocumentChunk(page: page, text: fragment))
                }
                if end == chars.count { break }
                start = max(start + 1, end - 100)
            }
        }
        return result
    }

}
