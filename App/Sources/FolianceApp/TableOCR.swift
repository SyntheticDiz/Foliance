import AppKit
import Foundation
import PDFKit
import Vision

/// Local-only OCR for tables embedded as page images. OCR output is always
/// marked uncertain; it is never a substitute for checking the source PDF.
enum TableOCR {
    private struct Grid {
        var x: [Int]
        var y: [Int]
        var width: Int
        var height: Int
        var pixels: [UInt8]
        var image: CGImage
    }

    private struct RecognizedText {
        var text: String
        var x: CGFloat
        var y: CGFloat
    }

    private static let maximumRenderDimension = 4096
    private static let darkThreshold: UInt8 = 145

    static func extract(page: PDFPage, number: Int) throws -> [DocumentTable] {
        try Task.checkCancellation()
        guard page.rotation % 360 == 0 else { return [] }
        let pageBounds = page.bounds(for: .cropBox).standardized
        guard !pageBounds.isEmpty, pageBounds.width > 0, pageBounds.height > 0 else { return [] }

        let imageRegions = try imageRegions(on: page, pageBounds: pageBounds)
        guard !imageRegions.isEmpty else { return [] }

        let scale = CGFloat(maximumRenderDimension) / max(pageBounds.width, pageBounds.height)
        let targetSize = NSSize(width: max(1, (pageBounds.width * scale).rounded()),
                                height: max(1, (pageBounds.height * scale).rounded()))
        guard let rendered = page.thumbnail(of: targetSize, for: .cropBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        var tables: [DocumentTable] = []
        for (regionIndex, pdfRect) in imageRegions.enumerated() {
            try Task.checkCancellation()
            guard let crop = cropImage(rendered, pageBounds: pageBounds, pdfRect: pdfRect) else { continue }
            guard let grid = try detectGrid(in: crop), grid.x.count >= 3, grid.y.count >= 3 else { continue }
            let texts = try recognize(crop)
            try Task.checkCancellation()
            guard let table = try makeTable(texts: texts, grid: grid, page: number, regionIndex: regionIndex,
                                            imageRegion: pdfRect, pageBounds: pageBounds) else { continue }
            tables.append(table)
        }
        return tables
    }

    private static func imageRegions(on page: PDFPage, pageBounds: CGRect) throws -> [CGRect] {
        let raw = page.string ?? ""
        let nsRaw = raw as NSString
        var regions: [CGRect] = []
        var searchRange = NSRange(location: 0, length: nsRaw.length)
        var index = 0
        while searchRange.location < nsRaw.length {
            if index.isMultiple(of: 16) { try Task.checkCancellation() }
            let match = nsRaw.range(of: "\u{FFFC}", options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            if let selection = page.selection(for: match) {
                let bounds = selection.bounds(for: page).standardized.intersection(pageBounds)
                if !bounds.isNull, !bounds.isEmpty, bounds.width > 8, bounds.height > 8 { regions.append(bounds) }
            }
            index += 1
            searchRange = NSRange(location: NSMaxRange(match), length: nsRaw.length - NSMaxRange(match))
        }

        // A textless scan is itself an image region. Pages with ordinary text
        // are deliberately restricted to PDFKit's explicit image-object bounds.
        if regions.isEmpty, !raw.contains(where: { !$0.isWhitespace }) {
            regions = [pageBounds]
        }
        return regions
    }

    private static func cropImage(_ image: CGImage, pageBounds: CGRect, pdfRect: CGRect) -> CGImage? {
        let xScale = CGFloat(image.width) / pageBounds.width
        let yScale = CGFloat(image.height) / pageBounds.height
        let x = (pdfRect.minX - pageBounds.minX) * xScale
        let y = (pageBounds.maxY - pdfRect.maxY) * yScale
        let rect = CGRect(x: x, y: y, width: pdfRect.width * xScale, height: pdfRect.height * yScale)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isNull, rect.width >= 32, rect.height >= 32 else { return nil }
        return image.cropping(to: rect)
    }

    private static func recognize(_ image: CGImage, fast: Bool = false) throws -> [RecognizedText] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.recognitionLanguages = ["nl-NL", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        var words: [RecognizedText] = []
        let wordExpression = try NSRegularExpression(pattern: #"\S+"#)
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first else { continue }
            let matches = wordExpression.matches(in: candidate.string,
                                                  range: NSRange(candidate.string.startIndex..., in: candidate.string))
            for match in matches {
                guard let range = Range(match.range, in: candidate.string) else { continue }
                let box: CGRect
                if let tokenBox = try? candidate.boundingBox(for: range) {
                    box = tokenBox.boundingBox
                } else {
                    box = observation.boundingBox
                }
                words.append(RecognizedText(text: String(candidate.string[range]),
                                            x: box.midX * CGFloat(image.width),
                                            y: (1 - box.midY) * CGFloat(image.height)))
            }
        }
        return words
    }

    private static func detectGrid(in image: CGImage) throws -> Grid? {
        guard let pixels = OCRNumericVariants.grayscalePixels(image) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 24, height > 24 else { return nil }

        // Long, near-continuous dark runs distinguish table rules from text.
        var horizontalCandidates: [Int] = []
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            var count = 0
            let start = max(0, width / 40)
            let end = min(width, width - width / 40)
            for x in start..<end where pixels[y * width + x] < darkThreshold { count += 1 }
            if Double(count) / Double(max(1, end - start)) >= 0.48 { horizontalCandidates.append(y) }
        }
        var verticalCandidates: [Int] = []
        for x in 0..<width {
            if x.isMultiple(of: 64) { try Task.checkCancellation() }
            var count = 0
            let start = max(0, height / 40)
            let end = min(height, height - height / 40)
            for y in start..<end where pixels[y * width + x] < darkThreshold { count += 1 }
            if Double(count) / Double(max(1, end - start)) >= 0.48 { verticalCandidates.append(x) }
        }
        try Task.checkCancellation()
        let horizontal = clustered(horizontalCandidates, tolerance: max(2, height / 1200))
        let vertical = clustered(verticalCandidates, tolerance: max(2, width / 1200))
        guard horizontal.count >= 3, vertical.count >= 3 else { return nil }
        return Grid(x: vertical, y: horizontal, width: width, height: height, pixels: pixels, image: image)
    }

    private static func clustered(_ positions: [Int], tolerance: Int) -> [Int] {
        guard !positions.isEmpty else { return [] }
        var groups: [[Int]] = [[positions[0]]]
        for position in positions.dropFirst() {
            if position - groups[groups.count - 1].last! <= tolerance + 1 {
                groups[groups.count - 1].append(position)
            } else {
                groups.append([position])
            }
        }
        return groups.map { Int((Double($0.reduce(0, +)) / Double($0.count)).rounded()) }
    }

    private static func makeTable(texts: [RecognizedText], grid: Grid, page: Int, regionIndex: Int,
                                  imageRegion: CGRect, pageBounds: CGRect) throws -> DocumentTable? {
        let columnCount = grid.x.count - 1
        let rowCount = grid.y.count - 1
        guard columnCount >= 2, rowCount >= 2, columnCount <= 32, rowCount <= 200 else { return nil }
        var cells = Array(repeating: Array(repeating: [RecognizedText](), count: columnCount), count: rowCount)
        for (index, text) in texts.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard let row = interval(containing: text.y, boundaries: grid.y),
                  let column = interval(containing: text.x, boundaries: grid.x) else { continue }
            cells[row][column].append(text)
        }
        var values = cells.map { row in
            row.map { cell in
                cell.sorted { abs($0.y - $1.y) < 0.012 * CGFloat(grid.height) ? $0.x < $1.x : $0.y < $1.y }
                    .map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let headerStart = values.indices.first(where: { index in
            let occupied = values[index].filter { !$0.isEmpty }.count
            return occupied >= min(3, columnCount) && !containsAmount(values[index])
                && hasFullColumnPartition(row: index, grid: grid)
        }) else { return nil }

        var headerEnd = headerStart
        if headerStart + 1 < rowCount {
            for index in (headerStart + 1)..<rowCount {
                let occupied = values[index].filter { !$0.isEmpty }.count
                guard occupied >= 2, !containsAmount(values[index]) else { break }
                headerEnd = index
            }
        }

        var agreedGridCells = Set<String>()
        for row in (headerEnd + 1)..<rowCount {
            try Task.checkCancellation()
            for column in 1..<columnCount {
                let cell = cellInterior(row: row, column: column, grid: grid)
                guard cellHasPhysicalBorders(row: row, column: column, grid: grid), containsInk(cell, grid: grid) else { continue }
                let hasMinus = hasLeadingMinusMark(cell, grid: grid)
                let current = values[row][column].trimmingCharacters(in: .whitespacesAndNewlines)
                // Vision can label a printed zero as a letter. Keep it visible
                // for review unless the independent numeric variants agree.
                let ambiguousZeroGlyph = current == "o" || current == "O"
                guard current.isEmpty || hasMinus || ambiguousZeroGlyph else { continue }
                let consensus = try OCRNumericVariants.consensus(in: grid.image, cell: cell,
                                                                  expectedNegative: hasMinus,
                                                                  sourcePixels: grid.pixels)
                if current.isEmpty {
                    if let consensus {
                        values[row][column] = consensus
                        agreedGridCells.insert("\(row):\(column)")
                    } else {
                        values[row][column] = "[onleesbaar]"
                    }
                } else if ambiguousZeroGlyph {
                    if let consensus {
                        values[row][column] = consensus
                        agreedGridCells.insert("\(row):\(column)")
                    } else {
                        values[row][column] = "[onleesbaar]"
                    }
                } else if hasMinus {
                    if let consensus, normalizedNumeric(consensus) == normalizedNumeric(current) {
                        agreedGridCells.insert("\(row):\(column)")
                    } else if !current.replacingOccurrences(of: "−", with: "-").hasPrefix("-") || consensus != nil {
                        // A visible sign with a conflicting or unresolved OCR result
                        // is safer to expose for review than silently keep as positive.
                        values[row][column] = "[onleesbaar]"
                    }
                }
            }
        }
        var headers = Array(repeating: "", count: columnCount)
        for row in headerStart...headerEnd {
            for column in 0..<columnCount where !values[row][column].isEmpty {
                headers[column] = [headers[column], values[row][column]].filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        guard headers.contains(where: { !$0.isEmpty }) else { return nil }

        let title = (0..<headerStart).reversed().first(where: { values[$0].filter { !$0.isEmpty }.count <= 2 })
            .map { values[$0].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Tabel op pagina \(page)"
        var rows: [[String]] = []
        var cellRegions: [[CGRect?]] = []
        var agreedCells = Set<String>()
        for index in (headerEnd + 1)..<rowCount {
            let row = values[index]
            guard row.contains(where: { !$0.isEmpty }) else { continue }
            let bodyRow = rows.count
            rows.append(row)
            cellRegions.append((0..<columnCount).map { column in
                normalizedRegion(gridCell(row: index, column: column, grid: grid), grid: grid,
                                 imageRegion: imageRegion, pageBounds: pageBounds)
            })
            for column in 0..<columnCount where agreedGridCells.contains("\(index):\(column)") {
                agreedCells.insert("\(bodyRow):\(column)")
            }
        }
        guard !rows.isEmpty else { return nil }
        let headerRegions = (0..<columnCount).map { column -> CGRect? in
            let first = gridCell(row: headerStart, column: column, grid: grid)
            let last = gridCell(row: headerEnd, column: column, grid: grid)
            return normalizedRegion(first.union(last), grid: grid, imageRegion: imageRegion, pageBounds: pageBounds)
        }
        let review = OCRTableReview(cellRegions: cellRegions, headerRegions: headerRegions,
                                    agreedCells: agreedCells, confirmedSignature: nil)
        return DocumentTable(id: "image-ocr-\(page)-\(regionIndex + 1)", title: title,
                             pages: [page], headers: headers, rows: rows,
                             notes: ["Lokaal OCR uit een PDF-afbeelding. Controleer alle koppen, waarden en lege cellen op bronpagina \(page); deze herkenning is niet geschikt voor automatische cijfervergelijkingen."],
                             reliable: false, recognizedWithOCR: true, ocrReview: review)
    }

    private static func interval(containing value: CGFloat, boundaries: [Int]) -> Int? {
        guard boundaries.count >= 2, value >= CGFloat(boundaries[0]), value <= CGFloat(boundaries[boundaries.count - 1]) else { return nil }
        for index in 0..<(boundaries.count - 1) where value >= CGFloat(boundaries[index]) && value <= CGFloat(boundaries[index + 1]) {
            return index
        }
        return nil
    }

    private static func cellInterior(row: Int, column: Int, grid: Grid) -> CGRect {
        let x0 = grid.x[column], x1 = grid.x[column + 1]
        let y0 = grid.y[row], y1 = grid.y[row + 1]
        let inset = max(3, min(7, min(x1 - x0, y1 - y0) / 14))
        return CGRect(x: x0 + inset, y: y0 + inset,
                      width: max(1, x1 - x0 - inset * 2), height: max(1, y1 - y0 - inset * 2))
    }

    private static func gridCell(row: Int, column: Int, grid: Grid) -> CGRect {
        CGRect(x: grid.x[column], y: grid.y[row],
               width: grid.x[column + 1] - grid.x[column], height: grid.y[row + 1] - grid.y[row])
    }

    private static func normalizedNumeric(_ value: String) -> String {
        value.replacingOccurrences(of: "−", with: "-").filter { !$0.isWhitespace }
    }

    private static func normalizedRegion(_ cell: CGRect, grid: Grid, imageRegion: CGRect, pageBounds: CGRect) -> CGRect? {
        guard !cell.isNull, !cell.isEmpty, imageRegion.width > 0, imageRegion.height > 0,
              pageBounds.width > 0, pageBounds.height > 0, grid.width > 0, grid.height > 0 else { return nil }
        let pdfX = imageRegion.minX + cell.minX * imageRegion.width / CGFloat(grid.width)
        let pdfY = imageRegion.maxY - cell.maxY * imageRegion.height / CGFloat(grid.height)
        let width = cell.width * imageRegion.width / CGFloat(grid.width)
        let height = cell.height * imageRegion.height / CGFloat(grid.height)
        return CGRect(x: (pdfX - pageBounds.minX) / pageBounds.width,
                      y: (pdfY - pageBounds.minY) / pageBounds.height,
                      width: width / pageBounds.width, height: height / pageBounds.height)
    }

    private static func hasLeadingMinusMark(_ cell: CGRect, grid: Grid) -> Bool {
        let bounds = cell.integral.intersection(CGRect(x: 0, y: 0, width: grid.width, height: grid.height))
        guard !bounds.isNull, !bounds.isEmpty else { return false }
        let x0 = Int(bounds.minX), x1 = Int(bounds.maxX), y0 = Int(bounds.minY), y1 = Int(bounds.maxY)
        let width = x1 - x0, height = y1 - y0
        guard width > 0, height > 0 else { return false }
        var inkMinX = width, inkMaxX = 0, inkMinY = height, inkMaxY = 0
        var dark: [Int] = []
        for y in 0..<height {
            for x in 0..<width where grid.pixels[(y0 + y) * grid.width + x0 + x] < darkThreshold {
                dark.append(y * width + x)
                inkMinX = min(inkMinX, x); inkMaxX = max(inkMaxX, x + 1)
                inkMinY = min(inkMinY, y); inkMaxY = max(inkMaxY, y + 1)
            }
        }
        guard !dark.isEmpty else { return false }
        var seen = Array(repeating: false, count: width * height)
        for start in dark where !seen[start] {
            var queue = [start], cursor = 0
            seen[start] = true
            var minX = start % width, maxX = start % width + 1
            var minY = start / width, maxY = start / width + 1
            while cursor < queue.count {
                let index = queue[cursor]; cursor += 1
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x + 1)
                minY = min(minY, y); maxY = max(maxY, y + 1)
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    if !seen[next], grid.pixels[(y0 + ny) * grid.width + x0 + nx] < darkThreshold {
                        seen[next] = true; queue.append(next)
                    }
                } }
            }
            let componentWidth = maxX - minX, componentHeight = maxY - minY
            let beginsAtInkEdge = minX <= inkMinX + max(2, componentHeight)
            if beginsAtInkEdge, componentWidth >= 6, componentHeight <= max(4, height / 8),
               Double(componentWidth) / Double(max(1, componentHeight)) >= 2.5,
               minX - inkMinX <= max(2, Int(Double(inkMaxX - inkMinX) * 0.22)),
               minY >= inkMinY - 2, maxY <= inkMaxY + 2 { return true }
        }
        return false
    }

    private static func containsInk(_ rect: CGRect, grid: Grid) -> Bool {
        let x0 = max(0, Int(rect.minX)), x1 = min(grid.width, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(grid.height, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return false }
        var darkPixels = 0
        for y in y0..<y1 {
            for x in x0..<x1 where grid.pixels[y * grid.width + x] < darkThreshold {
                darkPixels += 1
                if darkPixels >= 2 { return true }
            }
        }
        return false
    }

    private static func cellHasPhysicalBorders(row: Int, column: Int, grid: Grid) -> Bool {
        hasVerticalRule(at: grid.x[column], row: row, grid: grid)
            && hasVerticalRule(at: grid.x[column + 1], row: row, grid: grid)
    }

    private static func hasVerticalRule(at x: Int, row: Int, grid: Grid) -> Bool {
        let start = max(grid.y[row], 0), end = min(grid.y[row + 1], grid.height)
        guard end > start else { return false }
        var dark = 0
        for y in start..<end {
            for offset in -1...1 where x + offset >= 0 && x + offset < grid.width {
                if grid.pixels[y * grid.width + x + offset] < darkThreshold { dark += 1; break }
            }
        }
        return Double(dark) / Double(end - start) >= 0.3
    }

    private static func hasFullColumnPartition(row: Int, grid: Grid) -> Bool {
        let columnCount = grid.x.count - 1
        let internalRules = (1..<columnCount).filter { hasVerticalRule(at: grid.x[$0], row: row, grid: grid) }.count
        return internalRules >= max(1, columnCount - 2)
    }

    private static func containsAmount(_ row: [String]) -> Bool {
        let expression = try? NSRegularExpression(pattern: #"^[−-]?(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d+)?$"#)
        return row.contains { cell in
            guard let expression else { return false }
            let normalized = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil { return false }
            return expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil
        }
    }
}
