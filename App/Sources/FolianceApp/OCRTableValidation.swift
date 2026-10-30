import Foundation

struct OCRTableReview: Codable, Sendable {
    var cellRegions: [[CGRect?]] = []
    var headerRegions: [CGRect?] = []
    var agreedCells: Set<String> = []
    var confirmedSignature: String?
    var summary: DocumentDigest?
    var summaryModel: String?
}

extension DocumentTable {
    var reviewSignature: String { LocalCache.key([title] + pages.map(String.init) + headers + rows.flatMap { $0 }) }
    var isOCRConfirmed: Bool { recognizedWithOCR == true && ocrReview?.confirmedSignature == reviewSignature }
}

enum OCRTableValidation {
    enum State: String, Sendable { case matched, mismatch, unavailable }
    struct Check: Sendable { let label: String; let state: State; let detail: String }
    struct Report: Sendable {
        var checks: [Check] = []
        var issues: [String] = []
        var unresolvedCells: [String] = []
        var canConfirm: Bool { issues.isEmpty && unresolvedCells.isEmpty }
    }
    static func decimal(_ value: String) -> Decimal? {
        guard TableReader.number(value) != nil else { return nil }
        let text = value.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "−", with: "-").trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    static func report(_ table: DocumentTable) -> Report {
        var result = Report()
        guard table.headers.count >= 2, table.rows.allSatisfy({ $0.count == table.headers.count }) else {
            result.issues = ["De rij- en kolomstructuur is onvolledig."]; return result
        }
        if table.headers.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.contains("[onleesbaar]") }) {
            result.issues.append("Controleer en vul de ontbrekende kolomkoppen aan.")
        }
        for (r, row) in table.rows.enumerated() {
            for (c, cell) in row.enumerated() where !cell.isEmpty {
                if cell.contains("[onleesbaar]") || (c > 0 && decimal(cell) == nil && !["-", "PM", "n.v.t."].contains(cell)) {
                    result.unresolvedCells.append("\(r):\(c)")
                }
            }
            if row[0].isEmpty && row.dropFirst().contains(where: { !$0.isEmpty }) { result.issues.append("Rij \(r + 1) heeft geen omschrijving.") }
        }
        func check(_ label: String, _ inputs: [String], _ expected: String) {
            let values = inputs.compactMap(decimal)
            guard values.count == inputs.count, !values.isEmpty, let target = decimal(expected) else {
                result.checks.append(Check(label: label, state: .unavailable, detail: "Niet berekend: een waarde ontbreekt of is niet numeriek. Lege cellen gelden niet als nul.")); return
            }
            let sum = values.reduce(Decimal.zero, +)
            let matches = abs(NSDecimalNumber(decimal: sum - target).doubleValue) <= 0.005
            let detail = matches ? "De getoonde waarden sluiten aan." : "De som \(NSDecimalNumber(decimal: sum).stringValue) wijkt af van de bronwaarde \(expected). Controleer de bron; er is niets aangepast."
            result.checks.append(Check(label: label, state: matches ? .matched : .mismatch, detail: detail))
            if !matches { result.issues.append(label + ": " + detail) }
        }
        let headers = table.headers.map { $0.lowercased() }
        if let primary = headers.firstIndex(where: { $0.contains("primaire begroting") }),
           let mutation = headers.firstIndex(where: { $0.contains("totale mutatie") }),
           let final = headers.lastIndex(where: { $0.hasPrefix("begroting") }), final != primary {
            let changes = headers.indices.filter { headers[$0].hasPrefix("aanpassingen") }
            for row in table.rows where row.first?.first?.isNumber == true {
                if !changes.isEmpty { check(row[0] + " · mutatie", changes.map { row[$0] }, row[mutation]) }
                check(row[0] + " · eindbedrag", [row[primary], row[mutation]], row[final])
            }
        }
        if let totalIndex = table.rows.firstIndex(where: { $0[0].lowercased() == "totaal lasten" }),
           let start = table.rows[..<totalIndex].lastIndex(where: { $0[0].uppercased() == "LASTEN" }) {
            let body = table.rows[(start + 1)..<totalIndex].filter { $0[0].first?.isNumber == true }
            if !body.isEmpty {
                for c in table.headers.indices.dropFirst() { check("Totaal lasten · " + table.headers[c], body.map { $0[c] }, table.rows[totalIndex][c]) }
            }
        }
        if let costs = table.rows.first(where: { $0[0].lowercased() == "totaal lasten" }),
           let contributions = table.rows.first(where: { $0[0].lowercased() == "totaal bijdragen" }) {
            for c in table.headers.indices.dropFirst() where !headers[c].hasPrefix("aanpassingen") { check("Lasten en bijdragen · " + table.headers[c], [costs[c]], contributions[c]) }
        }
        if let participantsIndex = table.rows.firstIndex(where: { $0[0].lowercased() == "totaal deelnemers" }),
           let start = table.rows[..<participantsIndex].lastIndex(where: { $0[0].uppercased() == "BIJDRAGEN" }) {
            let body = Array(table.rows[(start + 1)..<participantsIndex])
            if !body.isEmpty {
                for c in table.headers.indices.dropFirst() { check("Som deelnemers · " + table.headers[c], body.map { $0[c] }, table.rows[participantsIndex][c]) }
            }
        }
        if let participants = table.rows.first(where: { $0[0].lowercased() == "totaal deelnemers" }),
           let other = table.rows.first(where: { $0[0].lowercased() == "totaal overige opbrengsten" }),
           let contributions = table.rows.first(where: { $0[0].lowercased() == "totaal bijdragen" }) {
            for c in table.headers.indices.dropFirst() { check("Deelnemers en overige opbrengsten · " + table.headers[c], [participants[c], other[c]], contributions[c]) }
        }
        if let balance = table.rows.first(where: { $0[0].uppercased() == "RESULTAAT" }),
           let costs = table.rows.first(where: { $0[0].lowercased() == "totaal lasten" }),
           let contributions = table.rows.first(where: { $0[0].lowercased() == "totaal bijdragen" }) {
            for c in table.headers.indices.dropFirst() {
                if let a = decimal(contributions[c]), let b = decimal(costs[c]) {
                    check("Resultaat · " + table.headers[c], [TableReader.format(NSDecimalNumber(decimal: a - b).doubleValue)], balance[c])
                } else { check("Resultaat · " + table.headers[c], [""], balance[c]) }
            }
        }
        return result
    }
}
