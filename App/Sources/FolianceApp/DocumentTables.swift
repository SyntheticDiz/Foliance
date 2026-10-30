import Foundation
import PDFKit

struct DocumentTable: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var pages: [Int]
    var headers: [String]
    var rows: [[String]]
    var notes: [String]
    var reliable: Bool
    var recognizedWithOCR: Bool? = nil
    var ocrReview: OCRTableReview? = nil
    /// A readable heading for the UI; the original extracted title remains unchanged.
    var displayTitle: String {
        guard Self.isUnitOnlyTitle(title), let subject = headers.first,
              Self.isRecognizableSubject(subject) else { return title }
        return subject
    }
    var overview: String {
        if recognizedWithOCR == true { return "Met lokale OCR zijn \(rows.count) rijen en \(headers.count) kolommen herkend. Dit kunnen ook tussenkoppen en totaalregels zijn. Controleer de herkende cellen aan de bron." }
        return "Deze tabel bevat \(rows.count) gegevensrijen, inclusief eventuele tussenstanden en totalen. Kolommen: \(headers.dropFirst().joined(separator: ", "))." + (reliable ? " Hieronder staan de belangrijkste leespunten." : " De structuur is niet voldoende zeker voor automatische cijfervergelijkingen.")
    }
    var bullets: [String] {
        guard reliable else { return ["Bekijk de oorspronkelijke tabel om de samenhang tussen de cijfers en kolommen te controleren."] }
        let years = headers.indices.filter { headers[$0].range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil }
        var result: [String] = []
        if years.count >= 2, let first = years.first, let last = years.last, headers[first] < headers[last] {
            if let total = rows.first(where: { $0[0].lowercased().hasPrefix("totaal") }), total.count == headers.count {
                let values = years.compactMap { column in TableReader.number(total[column]).map { (column, $0) } }
                if let highest = values.max(by: { $0.1 < $1.1 }), values.count > 2 {
                    result.append("De hoogste waarde op de totaalregel in de getoonde jaarkolommen is \(total[highest.0]) in \(headers[highest.0]).")
                }
                if let structural = headers.firstIndex(where: { $0.lowercased().hasPrefix("struc") }), !total[structural].isEmpty {
                    result.append("Op de totaalregel staat bij ‘\(headers[structural])’ \(total[structural]). Dit is geen extra jaarbedrag.")
                }
            }
            let ordered = rows.sorted { a, b in
                func priority(_ row: [String]) -> Int { row[0].lowercased().hasPrefix("totaal") ? 0 : (row[0].first?.isNumber == false ? 1 : 2) }
                return priority(a) < priority(b)
            }
            for row in ordered {
                guard row.count == headers.count, let a = TableReader.number(row[first]), let b = TableReader.number(row[last]) else { continue }
                // Never compare unlike units, missing values or footnote-bearing cells.
                guard row[first].contains("%") == row[last].contains("%"), row[first].contains("€") == row[last].contains("€") else { continue }
                let tableContext = ([title] + headers + notes).joined(separator: " ")
                guard !Self.hasConflictingMoneyScales(in: tableContext) else { continue }
                if row[first].contains("€") {
                    let headerScale = Self.moneyScale(in: tableContext)
                    guard !Self.hasUnqualifiedScaleCue(in: tableContext), headerScale == .euros || headerScale == .unknown else { continue }
                }
                let difference = b - a
                let unit: String
                if row[first].contains("%") {
                    unit = " procentpunt"
                } else if row[first].contains("€") {
                    unit = " euro"
                } else {
                    unit = amountUnit
                }
                let change: String
                if difference == 0 { change = "blijft gelijk" }
                else if a < 0 && b < 0 { change = "wordt \(TableReader.format(abs(difference)))\(unit) \(difference > 0 ? "minder negatief" : "negatiever")" }
                else { change = "\(difference > 0 ? "stijgt" : "daalt") met \(TableReader.format(abs(difference)))\(unit)" }
                let percent = a > 0 && b >= 0 && !row[first].contains("%") && difference != 0 && !headers.joined().contains("saldoverslechterend") ? " (\(TableReader.format(abs(difference / a * 100)))%)" : ""
                result.append("\(row[0]): van \(row[first]) in \(headers[first]) naar \(row[last]) in \(headers[last]); \(change)\(percent).")
            }
        }
        if result.isEmpty {
            for row in rows.prefix(5) where row.count == headers.count {
                result.append(row[0] + ": " + headers.indices.dropFirst().filter { !row[$0].isEmpty }.map { headers[$0] + " = " + row[$0] }.joined(separator: "; ") + ".")
            }
        }
        if result.count > 5 { return Array(result.prefix(5)) + ["De tabel bevat meer rijen; bekijk de bron voor het volledige overzicht."] }
        if rows.count > 5 && result.count <= 5 { result.append("De tabel bevat meer rijen; bekijk de bron voor het volledige overzicht.") }
        return result
    }
    private var amountUnit: String {
        switch Self.moneyScale(in: ([title] + headers + notes).joined(separator: " ")) {
        case .thousands: return " × € 1.000"
        case .millions: return " × € 1.000.000"
        case .euros: return " euro"
        case .unknown: return " in de eenheid van de tabel"
        }
    }
    var cautions: [String] {
        var result = notes
        if headers.joined().contains("saldoverslechterend"), amountUnit == " × € 1.000.000" { result.insert("Volgens de tabelkop zijn de bedragen in miljoenen euro en is een positief bedrag saldoverslechterend. ‘Struc.’ staat apart van de jaarkolommen en wordt niet als extra jaar meegerekend.", at: 0) }
        result.append("Lege cellen zijn niet als nul geïnterpreteerd. Bedragen tussen haakjes of met onduidelijke notatie worden niet gebruikt voor berekende verschillen.")
        if !reliable { result.insert("Onzekere tabelherkenning: samengevoegde cellen, ontbrekende koppen of een afwijkende uitlijning kunnen de betekenis veranderen.", at: 0) }
        if amountUnit == " in de eenheid van de tabel" {
            result.append("Controleer de eenheid in de bron, bijvoorbeeld euro’s, duizenden euro’s, aantallen of percentages. Er worden geen eenheden omgerekend.")
        }
        result.append("Verschillen verklaren geen oorzaak. Controleer ook of bedragen begroot of gerealiseerd zijn en welke voetnoten gelden.")
        return result
    }

    private enum MoneyScale: Hashable { case euros, thousands, millions, unknown }

    /// Returns a scale only when the wording identifies currency and an explicit
    /// table scale. A bare money amount in notes falls back to euros, not a scale.
    private static func moneyScale(in source: String) -> MoneyScale {
        let text = source.lowercased()
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var scales = Set<MoneyScale>()
        let thousandPatterns = [
            #"(?i)(?:x|×)\s*(?:€\s*1[. ]?000\b(?![. ]?000\b)|1[. ]?000\b(?![. ]?000\b)\s*(?:euro|€))"#,
            #"(?i)€\s*(?:x|×)\s*1[. ]?000\b(?![. ]?000\b)"#,
            #"(?i)(?:in\s+|bedragen\s+(?:in\s+)?|eenheid\s+in\s+)duizend(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)bedragen\s*\(?\s*duizend(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)duizenden\s+euro(?:'s|s)?\b"#,
            #"(?i)€\s*(?:x|×)\s*duizend(?:en)?\b"#
        ]
        let millionPatterns = [
            #"(?i)(?:x|×)\s*(?:€\s*1[. ]?000[. ]?000\b|1[. ]?000[. ]?000\b\s*(?:euro|€))"#,
            #"(?i)€\s*(?:x|×)\s*1[. ]?000[. ]?000\b"#,
            #"(?i)(?:in\s+|bedragen\s+(?:in\s+)?|eenheid\s+in\s+)miljoen(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)bedragen\s*\(?\s*miljoen(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)(?:x|×)\s*€\s*mln\b"#,
            #"(?i)€\s*(?:x|×)\s*mln\b"#,
            #"(?i)miljoenen\s+euro(?:'s|s)?\b"#
        ]
        if thousandPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { scales.insert(.thousands) }
        if millionPatterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { scales.insert(.millions) }
        if scales.isEmpty && (text.contains("€") || text.range(of: #"\beuro(?:'s|s)?\b"#, options: .regularExpression) != nil) {
            scales.insert(.euros)
        }
        return scales.count == 1 ? scales.first! : .unknown
    }

    private static func hasConflictingMoneyScales(in source: String) -> Bool {
        let thousandPatterns = [
            #"(?i)(?:x|×)\s*(?:€\s*1[. ]?000\b(?![. ]?000\b)|1[. ]?000\b(?![. ]?000\b)\s*(?:euro|€))"#,
            #"(?i)€\s*(?:x|×)\s*1[. ]?000\b(?![. ]?000\b)"#,
            #"(?i)(?:in\s+|bedragen\s+(?:in\s+)?|eenheid\s+in\s+)duizend(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)bedragen\s*\(?\s*duizend(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)duizenden\s+euro(?:'s|s)?\b"#,
            #"(?i)€\s*(?:x|×)\s*duizend(?:en)?\b"#
        ]
        let millionPatterns = [
            #"(?i)(?:x|×)\s*(?:€\s*1[. ]?000[. ]?000\b|1[. ]?000[. ]?000\b\s*(?:euro|€))"#,
            #"(?i)€\s*(?:x|×)\s*1[. ]?000[. ]?000\b"#,
            #"(?i)(?:in\s+|bedragen\s+(?:in\s+)?|eenheid\s+in\s+)miljoen(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)bedragen\s*\(?\s*miljoen(?:en)?\s+(?:euro|€)\b"#,
            #"(?i)(?:x|×)\s*€\s*mln\b"#,
            #"(?i)€\s*(?:x|×)\s*mln\b"#,
            #"(?i)miljoenen\s+euro(?:'s|s)?\b"#
        ]
        let text = source.lowercased()
        let hasThousands = thousandPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        let hasMillions = millionPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        return hasThousands && hasMillions
    }

    private static func hasUnqualifiedScaleCue(in source: String) -> Bool {
        source.range(of: #"(?i)(?:x|×)\s*1[. ]?000\b(?![. ]?000\b)|(?:x|×)\s*1[. ]?000[. ]?000\b"#, options: .regularExpression) != nil
    }

    private static func isUnitOnlyTitle(_ title: String) -> Bool {
        let text = title.lowercased()
        let hasScale = moneyScale(in: title) == .thousands || moneyScale(in: title) == .millions
        guard hasScale || text.contains("euro") || text.contains("€") else { return false }
        let remainder = text
            .replacingOccurrences(of: #"(?i)bedragen|bedrag|in|duizend(?:en)?|miljoen(?:en)?|euro|x|×|€|1[. ]?000(?:[. ]?000)?|mln|nadelig|voordelig"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s\p{P}\p{S}\d]"#, with: "", options: .regularExpression)
        return remainder.isEmpty
    }

    private static func isRecognizableSubject(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) == nil else { return false }
        let generic = ["onderwerp", "kolom", "jaar", "bedragen", "bedrag"]
        return !generic.contains(text.lowercased()) && text.count >= 3
    }
}

enum TableReader {
    struct Cell { var text: String; var bounds: CGRect }
    struct Row { var cells: [Cell]; var y: CGFloat; var height: CGFloat }
    static func number(_ source: String) -> Double? {
        let s = source.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "−", with: "-").trimmingCharacters(in: .whitespaces)
        guard s.range(of: #"^-?(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d+)?$"#, options: .regularExpression) != nil else { return nil }
        guard let value = Double(s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }
    static func format(_ value: Double) -> String {
        if value != 0 && abs(value) < 0.01 { return value.formatted(.number.locale(Locale(identifier: "nl_NL")).precision(.significantDigits(1...3))) }
        return value.formatted(.number.locale(Locale(identifier: "nl_NL")).precision(.fractionLength(0...2)))
    }

    static func extract(data: Data) -> [DocumentTable] {
        guard let pdf = PDFDocument(data: data) else { return [] }
        do {
            var tables: [DocumentTable] = []
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index) else { continue }
                tables += try extract(fragments: PageLayout.checkedWords(page), page: index + 1)
            }
            return try combine(tables)
        } catch { return [] }
    }

    /// Reuses the geometry already extracted for reading order.
    static func extract(fragments: [PageLayout.Fragment], page: Int) throws -> [DocumentTable] {
        try Task.checkCancellation()
        let cells = fragments.filter { $0.rect.width > 0 && $0.rect.height > 0 && $0.rect.height < 50 && !$0.rect.isInfinite }
            .map { Cell(text: $0.text, bounds: $0.rect) }.sorted { $0.bounds.midY > $1.bounds.midY }
        var rows: [Row] = []
        for (index, cell) in cells.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            if let last = rows.indices.last, abs(rows[last].y - cell.bounds.midY) < max(2, cell.bounds.height * 0.3) {
                rows[last].cells.append(cell)
            } else { rows.append(Row(cells: [cell], y: cell.bounds.midY, height: cell.bounds.height)) }
        }
        for i in rows.indices {
            if i.isMultiple(of: 64) { try Task.checkCancellation() }
            let sorted = rows[i].cells.sorted { $0.bounds.minX < $1.bounds.minX }
            var merged: [Cell] = []
            for (index, cell) in sorted.enumerated() {
                if index.isMultiple(of: 64) { try Task.checkCancellation() }
                if let last = merged.indices.last, cell.bounds.minX - merged[last].bounds.maxX < max(12, rows[i].height * 1.2) {
                    merged[last].text += " " + cell.text; merged[last].bounds = merged[last].bounds.union(cell.bounds)
                } else { merged.append(cell) }
            }
            rows[i].cells = merged
        }
        try Task.checkCancellation()
        return detect(rows: rows, page: page)
    }

    static func combine(_ tables: [DocumentTable]) throws -> [DocumentTable] {
        // Merge only explicitly labelled continuations with identical column headings.
        var combined: [DocumentTable] = []
        for table in tables {
            try Task.checkCancellation()
            func rowNumber(_ row: [String]) -> Int? { row.first?.split(separator: " ").first.flatMap { Int($0) } }
            let continuous = combined.last.flatMap { $0.rows.compactMap(rowNumber).last }.flatMap { last in table.rows.compactMap(rowNumber).first.map { $0 == last + 1 } } ?? false
            if let last = combined.indices.last, (table.title.lowercased().contains("vervolg") || continuous),
               combined[last].pages.last == table.pages[0] - 1, combined[last].headers == table.headers,
               table.title.replacingOccurrences(of: "(?i)\\s*\\(?vervolg\\)?", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) == combined[last].title {
                combined[last].pages += table.pages; combined[last].rows += table.rows; combined[last].notes += table.notes
                combined[last].reliable = combined[last].reliable && table.reliable
            } else { combined.append(table) }
        }
        return combined
    }

    private static func anchored(rows: [Row], anchors: [Int], page: Int) -> [DocumentTable] {
        var result: [DocumentTable] = []
        for (position, start) in anchors.enumerated() {
            let header = rows[start].cells
            let end = position + 1 < anchors.count ? anchors[position + 1] : rows.count
            var body: [[String]] = []; var notes: [String] = []; var reliable = true
            var previousY = rows[start].y
            var footnote = false
            for row in rows[(start + 1)..<end] {
                if previousY - row.y > 60 { break }
                previousY = row.y
                let text = row.cells.map(\.text).joined(separator: " ")
                if text.hasPrefix("*") || text.lowercased().hasPrefix("bron:") { footnote = true }
                if footnote {
                    if text.hasPrefix("*") || text.lowercased().hasPrefix("bron:") || notes.isEmpty { notes.append(text) }
                    else { notes[notes.count - 1] += " " + text }
                    continue
                }
                if row.cells.count == 1 { continue } // Section labels do not become data rows.
                var values = Array(repeating: "", count: header.count)
                for cell in row.cells {
                    if cell.bounds.maxX < header[1].bounds.minX - 12 {
                        values[0] += (values[0].isEmpty ? "" : " ") + cell.text
                        continue
                    }
                    let column = header.indices.dropFirst().min { abs(header[$0].bounds.maxX - cell.bounds.maxX) < abs(header[$1].bounds.maxX - cell.bounds.maxX) }!
                    let spacing = column > 1 ? header[column].bounds.midX - header[column - 1].bounds.midX : header[2].bounds.midX - header[1].bounds.midX
                    if abs(header[column].bounds.maxX - cell.bounds.maxX) > max(10, spacing * 0.42) || !values[column].isEmpty { reliable = false }
                    values[column] += cell.text
                }
                guard !values[0].isEmpty, values.dropFirst().contains(where: { !$0.isEmpty }) else { reliable = false; continue }
                body.append(values)
            }
            guard body.count >= 2 else { continue }
            let preceding = start > 0 && rows[start - 1].cells.count == 1 && rows[start - 1].y - rows[start].y < 45 ? rows[start - 1].cells[0].text : nil
            let title = preceding ?? (header[0].text.lowercased().contains("bedragen") ? header[0].text.replacingOccurrences(of: "# ", with: "") : "Tabel op pagina \(page)")
            result.append(DocumentTable(id: "table-\(page)-\(start)", title: title, pages: [page], headers: header.map(\.text), rows: body, notes: notes, reliable: reliable))
        }
        return result
    }

    static func detect(rows: [Row], page: Int) -> [DocumentTable] {
        let anchors = rows.indices.filter { index in
            rows[index].cells.dropFirst().filter { $0.text.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil }.count >= 2
        }
        if !anchors.isEmpty { return anchored(rows: rows, anchors: anchors, page: page) }
        var result: [DocumentTable] = []; var i = 0
        while i < rows.count {
            let start = i
            guard rows[i].cells.count >= 2, rows[i].cells.count <= 10 else { i += 1; continue }
            var group = [rows[i]]; i += 1
            while i < rows.count, rows[i].cells.count >= 2,
                  group.last!.y - rows[i].y < max(35, rows[i].height * 3) {
                group.append(rows[i]); i += 1
            }
            guard group.count >= 3 else { continue }
            let header = group[0].cells
            // Require multiple numeric body rows to avoid mistaking multi-column prose for a table.
            let numericRows = group.dropFirst().filter { $0.cells.dropFirst().contains { number($0.text) != nil } }
            guard numericRows.count >= 2 else { continue }
            let hasHeader = header.dropFirst().allSatisfy { number($0.text) == nil || $0.text.range(of: #"^(?:19|20)\d{2}$"#, options: .regularExpression) != nil }
            let aligned = group.dropFirst().allSatisfy { row in
                row.cells.count == header.count && zip(row.cells, header).allSatisfy { cell, head in
                    cell.bounds.minX <= head.bounds.maxX + 10 && cell.bounds.maxX >= head.bounds.minX - 10
                }
            }
            let title = start > 0 && rows[start - 1].cells.count == 1 && rows[start - 1].y - rows[start].y < 45 && rows[start - 1].cells[0].text.count < 140 ? rows[start - 1].cells[0].text : "Tabel op pagina \(page)"
            var notes: [String] = []
            var after = i
            while after < rows.count && after < i + 3, rows[after].cells.count == 1,
                  rows[after - 1].y - rows[after].y < 35 {
                let text = rows[after].cells[0].text
                if text.range(of: #"(?i)^(?:\*|\d+[).]|bron\b|toelichting\b|bedragen\b|in duizenden\b|x\s*(?:€|1[. ]?000))"#, options: .regularExpression) != nil { notes.append(text) } else { break }
                after += 1
            }
            let headers = hasHeader ? header.map(\.text) : header.indices.map { $0 == 0 ? "Onderwerp" : "Kolom \($0 + 1) (kop onzeker)" }
            let dataRows = (hasHeader ? Array(group.dropFirst()) : group).map { $0.cells.map(\.text) }
            result.append(DocumentTable(id: "table-\(page)-\(start)", title: title, pages: [page], headers: headers, rows: dataRows, notes: notes, reliable: hasHeader && aligned))
        }
        return result
    }
}
