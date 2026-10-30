import Foundation

struct WorkspaceSourceIssue: Identifiable {
    enum Kind { case unreadable, limitedRegion, ocr }
    let page: Int
    let kind: Kind
    let notice: String
    var id: String { "\(page)-\(kind)" }
    var title: String {
        switch kind {
        case .unreadable: "Niet meegenomen · PDF-pagina \(page)"
        case .limitedRegion: "Geselecteerd tekstgebied · PDF-pagina \(page)"
        case .ocr: "Afbeeldingstabel controleren · PDF-pagina \(page)"
        }
    }
    static func make(readings: [PageReading]) -> [Self] {
        readings.enumerated().compactMap { offset, reading in
            guard !reading.notice.isEmpty else { return nil }
            let kind: Kind
            if reading.text.isEmpty { kind = .unreadable }
            else if reading.notice.contains("handmatig aangewezen tekstgebied") { kind = .limitedRegion }
            else if reading.notice.contains("Afbeeldingstabel met OCR gelezen") { kind = .ocr }
            else { return nil }
            return Self(page: offset + 1, kind: kind, notice: reading.notice)
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
