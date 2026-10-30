import Foundation

struct WorkspaceSourceIssue: Identifiable {
    enum Kind { case unreadable, limitedRegion, ocr }
    let page: Int
    let kind: Kind
    let notice: String
    var id: String { "\(page)-\(kind)" }
    var title: String {
        switch kind {
        case .unreadable: "Not included · PDF page \(page)"
        case .limitedRegion: "Selected text region · PDF page \(page)"
        case .ocr: "Check image table · PDF page \(page)"
        }
    }
    static func make(readings: [PageReading]) -> [Self] {
        readings.enumerated().compactMap { offset, reading in
            guard !reading.notice.isEmpty else { return nil }
            let kind: Kind
            if reading.text.isEmpty { kind = .unreadable }
            else if isLimitedRegionNotice(reading.notice) { kind = .limitedRegion }
            else if isOCRNotice(reading.notice) { kind = .ocr }
            else { return nil }
            return Self(page: offset + 1, kind: kind, notice: englishNotice(reading.notice))
        }
    }

    private static func isLimitedRegionNotice(_ notice: String) -> Bool {
        notice.localizedCaseInsensitiveContains("handmatig aangewezen tekstgebied") ||
        notice.localizedCaseInsensitiveContains("manually selected text region")
    }

    private static func isOCRNotice(_ notice: String) -> Bool {
        notice.localizedCaseInsensitiveContains("Afbeeldingstabel met OCR gelezen") ||
        notice.localizedCaseInsensitiveContains("Image table was read with OCR")
    }

    /// Page-reading notices are app-generated. Translate known legacy values for
    /// display while leaving unknown notice text intact.
    static func englishNotice(_ notice: String) -> String {
        let exact: [String: String] = [
            "Pagina niet leesbaar.": "This PDF page could not be read.",
            "Alleen een paginavoet herkend; afbeeldingen zijn niet als tekst geanalyseerd.": "Only a page footer was detected; images were not analyzed as text.",
            "Geen tekstlaag in deze pagina; niet automatisch verwerkt.": "This page has no text layer and was not processed automatically.",
            "Leesvolgorde blijft onzeker na automatische hercontrole; deze pagina is overgeslagen.": "Reading order remains uncertain after automatic review; this page was skipped.",
            "Alleen het handmatig aangewezen tekstgebied is meegenomen.": "Only the manually selected text region was included.",
            "Afbeeldingstabel met OCR gelezen. Controleer de herkende cellen in Tabellen; deze zijn niet in de AI-analyse opgenomen.": "An image table was read with OCR. Check the recognized cells in Tables; it was not included in AI analysis.",
            "OCR van afbeeldingstabellen niet voltooid. Bekijk de tabel in de bron-PDF.": "OCR for image tables could not be completed. Review the table in the source PDF."
        ]
        if let translated = exact[notice] { return translated }
        let fragments = [
            "Alleen het handmatig aangewezen tekstgebied is meegenomen.": "Only the manually selected text region was included.",
            "Afbeeldingstabel met OCR gelezen.": "An image table was read with OCR.",
            "Controleer de herkende cellen in Tabellen;": "Check the recognized cells in Tables;",
            "Controleer de cellen.": "Check the cells.",
            "deze zijn niet in de AI-analyse opgenomen.": "it was not included in AI analysis."
        ]
        return fragments.reduce(notice) { text, fragment in
            text.replacingOccurrences(of: fragment.key, with: fragment.value)
        }
    }
}

enum PointDisplayFilter {
    static func pages(for point: Insight) -> Set<Int> {
        Set([point.page] + (point.otherSources ?? []).map(\.page) + (point.passageSources ?? []).map(\.page))
    }
    static func matches(_ point: Insight, pages: Set<Int>?, reviewFilter: Int, annotation: PointAnnotation) -> Bool {
        if let pages, self.pages(for: point).isDisjoint(with: pages) { return false }
        if reviewFilter == 1 && annotation.isChecked(point) { return false }
        if reviewFilter == 2 && !annotation.isChecked(point) { return false }
        return true
    }
    static func matches(_ row: CommitteePointPresentation.Row, pages: Set<Int>?, reviewFilter: Int,
                        annotation: (Insight) -> PointAnnotation) -> Bool {
        if let pages, Set(row.assessment.sources.map(\.page)).isDisjoint(with: pages) { return false }
        if reviewFilter == 0 { return true }
        if row.points.isEmpty { return reviewFilter == 1 }
        return row.points.contains { matches($0, pages: nil, reviewFilter: reviewFilter, annotation: annotation($0)) }
    }
}
