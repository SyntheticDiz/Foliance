import Foundation
import PDFKit
import CryptoKit

struct LayoutOverride: Codable, Sendable {
    var columns: Int = 0 // 0 = automatic
    var region: CGRect? = nil // normalized PDF coordinates
}
struct PageReading: Codable, Sendable {
    var text: String
    var notice: String = ""
    var columns: Int = 1
    var headings: [String] = []
}
struct LayoutDocument: Sendable {
    var pages: [String]
    var readings: [PageReading]
    var tables: [DocumentTable] = []
    var hasTextLayer = true
    var extractionCache: PageExtractionCache? = nil
}
enum LayoutStore {
    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func url(_ data: Data) -> URL {
        url(fingerprint: fingerprint(data))
    }
    static func url(fingerprint: String) -> URL {
        PersonalGlossary.url.deletingLastPathComponent().appendingPathComponent("pagina-indeling/" + fingerprint + ".json")
    }
    static func read(_ data: Data) throws -> [Int: LayoutOverride] {
        try read(fingerprint: fingerprint(data))
    }
    static func read(fingerprint: String) throws -> [Int: LayoutOverride] {
        let path = url(fingerprint: fingerprint)
        return FileManager.default.fileExists(atPath: path.path) ? try JSONDecoder().decode([Int: LayoutOverride].self, from: Data(contentsOf: path)) : [:]
    }
    static func save(_ values: [Int: LayoutOverride], data: Data) throws {
        try save(values, fingerprint: fingerprint(data))
    }
    static func save(_ values: [Int: LayoutOverride], fingerprint: String) throws {
        let path = url(fingerprint: fingerprint)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: path, options: .atomic)
    }
}

enum PageLayout {
    struct Fragment {
        var text: String
        var rect: CGRect
        var bold = false
    }
    static func extract(
        data: Data,
        overrides: [Int: LayoutOverride],
        progress: (@Sendable (_ completedPages: Int, _ totalPages: Int) -> Void)? = nil
    ) throws -> LayoutDocument {
        guard let pdf = PDFDocument(data: data), !pdf.isLocked else { throw AppError(message: "PDF niet leesbaar.") }
        return try extract(pdf: pdf, overrides: overrides, progress: progress,
                           sourceFingerprint: LayoutStore.fingerprint(data))
    }
    static func extract(pdf: PDFDocument, overrides: [Int: LayoutOverride], includeTables: Bool = false,
                        progress: (@Sendable (Int, Int) -> Void)? = nil,
                        sourceFingerprint: String? = nil,
                        reusing cache: PageExtractionCache? = nil) throws -> LayoutDocument {
        let totalPages = pdf.pageCount
        let reusable = sourceFingerprint.flatMap { fingerprint in
            cache?.isCompatible(sourceFingerprint: fingerprint, pageCount: totalPages,
                                includesTables: includeTables) == true ? cache : nil
        }
        var pageResults = reusable?.pages ?? []
        if reusable == nil { pageResults.reserveCapacity(totalPages) }
        for index in 0..<totalPages {
            try Task.checkCancellation()
            let override = overrides[index + 1] ?? LayoutOverride()
            if let reusable, reusable.pages[index].matches(override) {
                progress?(index + 1, totalPages)
                continue
            }
            let result = try extractPage(pdf.page(at: index), number: index + 1,
                                         override: override, includeTables: includeTables)
            if reusable == nil { pageResults.append(result) }
            else { pageResults[index] = result }
            progress?(index + 1, totalPages)
        }
        let readings = pageResults.map(\.reading)
        let rawTables = pageResults.flatMap(\.rawTables)
        let resultCache = sourceFingerprint.map {
            PageExtractionCache(sourceFingerprint: $0, includesTables: includeTables, pages: pageResults)
        }
        return LayoutDocument(pages: readings.map(\.text), readings: readings,
                              tables: try TableReader.combine(rawTables),
                              hasTextLayer: pageResults.contains(where: \.hasTextLayer),
                              extractionCache: resultCache)
    }

    private static func extractPage(_ page: PDFPage?, number: Int, override: LayoutOverride,
                                    includeTables: Bool) throws -> PageExtractionCache.Page {
        guard let page else {
            return .init(reading: .init(text: "", notice: "Pagina niet leesbaar."), rawTables: [],
                         hasTextLayer: false, appliedOverride: override)
        }
        var reading: PageReading
        var rawTables: [DocumentTable] = []
        let bounds = page.bounds(for: .cropBox)
        let region = override.region.map {
            CGRect(x: bounds.minX + $0.minX * bounds.width, y: bounds.minY + $0.minY * bounds.height,
                   width: $0.width * bounds.width, height: $0.height * bounds.height)
        }
        let hasTextLayer = page.string?.contains(where: { !$0.isWhitespace }) == true
        let allWords = try checkedWords(page)
        var ocrNotice: String?
        if includeTables {
            rawTables += try TableReader.extract(fragments: allWords, page: number)
            do {
                let recognized = try TableOCR.extract(page: page, number: number)
                rawTables += recognized
                if !recognized.isEmpty {
                    ocrNotice = "Afbeeldingstabel met OCR gelezen. Controleer de herkende cellen in Tabellen; deze zijn niet in de AI-analyse opgenomen."
                }
            } catch is CancellationError { throw CancellationError() }
            catch { ocrNotice = "OCR van afbeeldingstabellen niet voltooid. Bekijk de tabel in de bron-PDF." }
        }
        let fragments = allWords.filter {
            region == nil || region!.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY))
        }
        reading = order(fragments, bounds: bounds, columns: override.columns)
        if region == nil && !fragments.isEmpty && fragments.allSatisfy({ $0.rect.maxY < bounds.minY + bounds.height * 0.08 }) {
            reading = .init(text: "", notice: "Alleen een paginavoet herkend; afbeeldingen zijn niet als tekst geanalyseerd.")
        }
        if region != nil { reading.notice = "Alleen het handmatig aangewezen tekstgebied is meegenomen." }
        if let ocrNotice { reading.notice = [reading.notice, ocrNotice].filter { !$0.isEmpty }.joined(separator: " ") }
        return .init(reading: reading, rawTables: rawTables, hasTextLayer: hasTextLayer,
                     appliedOverride: override)
    }
    static func words(_ page: PDFPage) -> [Fragment] {
        (try? words(page, checkingCancellation: false)) ?? []
    }
    static func checkedWords(_ page: PDFPage) throws -> [Fragment] { try words(page, checkingCancellation: true) }
    private static func words(_ page: PDFPage, checkingCancellation: Bool) throws -> [Fragment] {
        guard let raw = page.string else { return [] }
        let text = raw as NSString
        let attributed = page.attributedString
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: text.length))
        var fragments: [Fragment] = []
        fragments.reserveCapacity(matches.count)
        for (index, match) in matches.enumerated() {
            if checkingCancellation && index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard let selection = page.selection(for: match.range) else { continue }
            let rect = selection.bounds(for: page)
            guard !rect.isEmpty, !rect.isInfinite else { continue }
            guard text.substring(with: match.range) != "\u{FFFC}" else { continue }
            let font = attributed.flatMap { match.range.location < $0.length ? $0.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont : nil }
            fragments.append(Fragment(text: text.substring(with: match.range), rect: rect, bold: font?.fontDescriptor.symbolicTraits.contains(.bold) == true))
        }
        if checkingCancellation { try Task.checkCancellation() }
        return fragments
    }
    static func order(_ words: [Fragment], bounds: CGRect, columns: Int = 0) -> PageReading {
        guard !words.isEmpty else { return .init(text: "", notice: "Geen tekstlaag in deze pagina; niet automatisch verwerkt.") }
        let sorted = words.sorted { $0.rect.midY > $1.rect.midY }
        var rows: [[Fragment]] = []
        for word in sorted {
            if let last = rows.indices.last, abs(rows[last][0].rect.midY - word.rect.midY) < max(2, word.rect.height * 0.3) { rows[last].append(word) }
            else { rows.append([word]) }
        }
        rows = rows.map { row in
            var parts: [Fragment] = []
            for word in row.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                if let last = parts.indices.last, word.rect.minX - parts[last].rect.maxX < max(3, word.rect.height * 0.55) {
                    parts[last].text += " " + word.text; parts[last].rect = parts[last].rect.union(word.rect); parts[last].bold = parts[last].bold && word.bold
                } else { parts.append(word) }
            }
            return parts
        }
        let body = rows.flatMap { $0 }
        let extent = body.reduce(CGRect.null) { $0.union($1.rect) }
        let normalHeight = body.map { $0.rect.height }.sorted()[body.count / 2]
        func numeric(_ row: [Fragment]) -> Bool { row.filter { TableReader.number($0.text) != nil }.count >= 2 }
        var cuts: [CGFloat] = []
        if columns > 1 {
            cuts = (1..<columns).map { extent.minX + extent.width * CGFloat($0) / CGFloat(columns) }
        } else if columns == 0 {
            var candidates: [CGFloat] = []
            for row in rows where !numeric(row) && row.count > 1 {
                for pair in zip(row, row.dropFirst()) where pair.0.rect.width > 45 && pair.1.rect.width > 45 {
                    let gap = pair.1.rect.minX - pair.0.rect.maxX
                    if gap > max(6, normalHeight * 0.6) { candidates.append(pair.1.rect.minX - min(3, gap / 2)) }
                }
            }
            // Vote for whitespace gutters; retry at the median of every cluster.
            var clusters: [[CGFloat]] = []
            for candidate in candidates.sorted() {
                if let last = clusters.indices.last, abs(clusters[last].first! - candidate) < 5 { clusters[last].append(candidate) }
                else { clusters.append([candidate]) }
            }
            for cluster in clusters.sorted(by: { $0.count > $1.count }) where cluster.count >= 3 {
                let cut = cluster.sorted()[cluster.count / 2]
                guard cut - extent.minX > extent.width * 0.18, extent.maxX - cut > extent.width * 0.18 else { continue }
                let left = body.filter { $0.rect.maxX < cut && $0.text.count > 12 }.count
                let right = body.filter { $0.rect.minX > cut && $0.text.count > 12 }.count
                if left >= 3 && right >= 3 && !cuts.contains(where: { abs($0 - cut) < extent.width * 0.22 }) { cuts.append(cut) }
                if cuts.count == 2 { break }
            }
            // Independently aligned baselines need not share a row. Repeated left
            // edges plus an unoccupied gutter provide a second, geometric vote.
            let starts = body.filter { $0.rect.width > 45 }.map { $0.rect.minX }.sorted()
            var edges: [[CGFloat]] = []
            for start in starts {
                if let last = edges.indices.last, start - edges[last][0] < 3 { edges[last].append(start) }
                else { edges.append([start]) }
            }
            for edge in edges.sorted(by: { $0.count > $1.count }) where edge.count >= 4 {
                if cuts.count >= 2 { break }
                let cut = edge[edge.count / 2] - 2
                guard cut - extent.minX > extent.width * 0.18, extent.maxX - cut > extent.width * 0.18,
                      !cuts.contains(where: { abs($0 - cut) < extent.width * 0.22 }) else { continue }
                let crossing = body.filter { $0.rect.minX < cut && $0.rect.maxX > cut && $0.rect.height < normalHeight * 1.5 }.count
                let left = body.filter { $0.rect.maxX < cut && $0.rect.width > 45 }.count
                if crossing <= 1 && left >= 4 { cuts.append(cut) }
                if cuts.count == 2 { break }
            }
            cuts.sort()
            // A second detection pass also handles staggered column baselines.
            if cuts.isEmpty {
                let starts = body.filter { $0.rect.width > extent.width * 0.22 && $0.rect.width < extent.width * 0.58 }
                if starts.count >= 8 {
                    let right = starts.filter { $0.rect.minX > extent.midX }
                    let left = starts.filter { $0.rect.maxX < extent.midX + 10 }
                    if right.count >= 4 && left.count >= 4, let r = right.map({ $0.rect.minX }).min(), let l = left.map({ $0.rect.maxX }).max(), r - l > 18 { cuts = [(l + r) / 2] }
                }
            }
        }
        let suspicious = rows.filter { $0.count > 1 && !numeric($0) && $0.filter { $0.text.count > 15 }.count > 1 }.count
        if columns == 0 && cuts.isEmpty && suspicious >= 3 {
            return .init(text: "", notice: "Leesvolgorde blijft onzeker na automatische hercontrole; deze pagina is overgeslagen.")
        }
        var output: [String] = []; var buffer: [Fragment] = []; var footnotes: [Fragment] = []
        var headings: [String] = []
        func render(_ fragments: [Fragment]) -> String {
            DocumentParagraphs.rebuild(fragments.sorted { $0.rect.midY > $1.rect.midY }.map { .init(text: $0.text, bounds: $0.rect, heading: $0.bold && DocumentParagraphs.isHeading($0.text)) })
        }
        func flush() {
            if cuts.isEmpty { if !buffer.isEmpty { output.append(render(buffer)) } }
            else {
                for column in 0...cuts.count {
                    let group = buffer.filter { fragment in cuts.filter { fragment.rect.midX > $0 }.count == column }
                    if !group.isEmpty {
                        let text = render(group)
                        if column > 0, let last = output.last, let end = last.last,
                           !".!?:;".contains(end), text.first?.isLowercase == true {
                            output[output.count - 1] += "\n" + text
                        } else { output.append(text) }
                    }
                }
            }
            buffer = []
        }
        for row in rows {
            let rect = row.reduce(CGRect.null) { $0.union($1.rect) }
            if rect.midY < bounds.minY + bounds.height * 0.12 && rect.height < normalHeight * 0.85 { footnotes += row; continue }
            let text = row.map(\.text).joined(separator: " ")
            if row.count == 1, text.count < 110, rect.height > normalHeight * 1.7,
               rect.midY > bounds.minY + bounds.height * 0.55,
               text.contains(where: \.isLetter) { headings.append(text) }
            let spanning = cuts.contains { cut in row.contains { $0.rect.minX < cut && $0.rect.maxX > cut } }
            if numeric(row) || (!cuts.isEmpty && spanning) {
                flush()
                output.append(text)
            } else { buffer += row }
        }
        flush()
        if !footnotes.isEmpty { output.append(render(footnotes)) }
        return .init(text: output.joined(separator: "\n\n"), columns: cuts.count + 1, headings: headings.isEmpty ? [] : [headings.joined(separator: " ")])
    }
}
