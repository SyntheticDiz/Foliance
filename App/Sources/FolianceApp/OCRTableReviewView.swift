import SwiftUI
import PDFKit

struct OCRTableReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DocumentTable
    @State private var selectedRow = 0
    @State private var selectedColumn = 0
    @State private var image: NSImage?
    @State private var confirmsSource = false
    let data: Data?
    let save: (DocumentTable) -> Void

    init(table: DocumentTable, data: Data?, save: @escaping (DocumentTable) -> Void) {
        _draft = State(initialValue: table); self.data = data; self.save = save
    }

    private var report: OCRTableValidation.Report { OCRTableValidation.report(draft) }
    private var value: Binding<String> {
        Binding(get: {
            selectedRow < 0 ? draft.headers[selectedColumn] : draft.rows[selectedRow][selectedColumn]
        }, set: { new in
            if selectedRow < 0 { draft.headers[selectedColumn] = new } else { draft.rows[selectedRow][selectedColumn] = new }
            confirmsSource = false
            var review = draft.ocrReview ?? OCRTableReview()
            review.confirmedSignature = nil; review.summary = nil; review.summaryModel = nil
            draft.ocrReview = review
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.text("Controleer tabel aan de bron")).font(.title2.bold())
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(draft.title + " · " + UIStrings.text("PDF-pagina \(draft.pages.map(String.init).joined(separator: ", "))"))
                                .font(.callout)
                            Text(UIStrings.text("Kies een cel of kolomkop, vergelijk de uitsnede en pas zo nodig de tekst aan. Vul een ontbrekende waarde nooit in op basis van een totaal. Een lege cel blijft leeg; een afgedrukte nul wordt 0."))
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                            if geometry.size.width >= 820 {
                                HStack(alignment: .top, spacing: 18) {
                                    editorPane.frame(maxWidth: .infinity, alignment: .leading)
                                    sourcePane.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 12) { editorPane; sourcePane }
                            }
                            tableGrid
                            DisclosureGroup(UIStrings.text("Rekencontroles · \(report.checks.filter { $0.state == .matched }.count) sluiten aan · \(report.checks.filter { $0.state == .mismatch }.count) afwijkingen")) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(report.checks.indices, id: \.self) { i in
                                            let item = report.checks[i]
                                            Text(item.label + ": " + UIStrings.text(item.detail)).font(.caption)
                                                .foregroundStyle(item.state == .mismatch ? Color.orange : Color.secondary)
                                        }
                                    }
                                }.frame(maxHeight: 110)
                            }
                            if !report.unresolvedCells.isEmpty {
                                Text(UIStrings.text("Nog \(report.unresolvedCells.count) onzekere cellen. Een cel kiezen laat de bronuitsnede zien."))
                                    .foregroundStyle(.orange)
                            }
                            ForEach(Array(report.issues.prefix(3).enumerated()), id: \.offset) { _, issue in
                                Text(UIStrings.text(issue)).font(.caption).foregroundStyle(.orange)
                            }
                            Toggle(UIStrings.text("Ik heb de kolomkoppen, waarden en lege cellen met de oorspronkelijke PDF vergeleken."), isOn: $confirmsSource)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button(UIStrings.text("Annuleren")) { dismiss() }.keyboardShortcut(.cancelAction)
                            Spacer(minLength: 6)
                            Button(UIStrings.text("Correcties bewaren")) { store(confirmed: false) }
                            confirmButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            confirmButton
                            HStack {
                                Button(UIStrings.text("Annuleren")) { dismiss() }.keyboardShortcut(.cancelAction)
                                Spacer()
                                Button(UIStrings.text("Correcties bewaren")) { store(confirmed: false) }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(minWidth: 420, idealWidth: 1000, minHeight: 360, idealHeight: 850)
        .onAppear { selectFirstUncertain() }
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((selectedRow < 0 ? UIStrings.text("Kolomkop \(selectedColumn + 1)") : UIStrings.text("Rij \(selectedRow + 1)")) +
                 (selectedRow < 0 ? "" : " · " + draft.headers[selectedColumn]))
                .font(.headline).lineLimit(2)
            TextField(UIStrings.text("Waarde zoals in de bron"), text: value).textFieldStyle(FocusInputFieldStyle())
            Text(UIStrings.text("Gebruik de Nederlandse getalnotatie: bijvoorbeeld -1.250 of 1.234,50."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Originele uitsnede")).font(.headline)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 330, maxHeight: 135).background(Color.white)
            } else {
                Text(UIStrings.text("Geen celuitsnede bewaard. Bekijk deze cel via de bronknop in de PDF."))
                    .frame(maxWidth: 330, minHeight: 72, alignment: .leading)
            }
        }
    }

    private var confirmButton: some View {
        Button(UIStrings.text("Broncontrole bevestigen")) { store(confirmed: true) }
            .buttonStyle(FocusPrimaryButtonStyle())
            .disabled(!confirmsSource || !report.canConfirm).keyboardShortcut(.defaultAction)
    }

    private var tableGrid: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    ForEach(draft.headers.indices, id: \.self) { c in cell(draft.headers[c], row: -1, column: c) }
                }
                ForEach(draft.rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(draft.headers.indices, id: \.self) { c in cell(draft.rows[r][c], row: r, column: c) }
                    }
                }
            }.padding(8)
        }
        .frame(minHeight: 110, maxHeight: 250)
        .accessibilityLabel(UIStrings.text("Tabelcellen: kies een kop of cel om de bronuitsnede te bekijken"))
    }

    private func cell(_ text: String, row: Int, column: Int) -> some View {
        Button { selectedRow = row; selectedColumn = column; refreshImage() } label: {
            Text(text.isEmpty ? UIStrings.text("[leeg]") : text).font(row < 0 ? .caption.bold() : .caption)
                .frame(width: column == 0 ? 220 : 140, alignment: .leading).frame(minHeight: 35).padding(6)
                .background(selectedRow == row && selectedColumn == column ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel((row < 0 ? UIStrings.text("Kolomkop") : UIStrings.text("Rij \(row + 1)")) +
                            ", " + UIStrings.text("kolom") + " \(column + 1): " +
                            (text.isEmpty ? UIStrings.text("leeg") : text))
    }

    private func selectFirstUncertain() {
        if let key = report.unresolvedCells.first {
            let indices = key.split(separator: ":").compactMap { Int($0) }
            if indices.count == 2 { selectedRow = indices[0]; selectedColumn = indices[1] }
        }
        refreshImage()
    }

    private func refreshImage() {
        image = nil
        guard let data, let pdf = PDFDocument(data: data), let pageNumber = draft.pages.first,
              let page = pdf.page(at: pageNumber - 1) else { return }
        let region: CGRect?
        if selectedRow < 0 { region = draft.ocrReview?.headerRegions.indices.contains(selectedColumn) == true ? draft.ocrReview?.headerRegions[selectedColumn] : nil }
        else if let regions = draft.ocrReview?.cellRegions, regions.indices.contains(selectedRow), regions[selectedRow].indices.contains(selectedColumn) { region = regions[selectedRow][selectedColumn] }
        else { region = nil }
        guard let region else { return }
        let bounds = page.bounds(for: .cropBox)
        let crop = CGRect(x: bounds.minX + region.minX * bounds.width, y: bounds.minY + region.minY * bounds.height, width: region.width * bounds.width, height: region.height * bounds.height)
        if let cg = TableCellImage.render(page: page, region: crop.insetBy(dx: -2, dy: -2)) { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
    }

    private func store(confirmed: Bool) {
        var review = draft.ocrReview ?? OCRTableReview()
        review.confirmedSignature = confirmed ? draft.reviewSignature : nil
        review.summary = nil; review.summaryModel = nil
        draft.ocrReview = review; save(draft); dismiss()
    }
}

enum TableCellImage {
    static func render(page: PDFPage, region: CGRect) -> CGImage? {
        let crop = region.standardized.intersection(page.bounds(for: .cropBox))
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        let scale = min(6, 4096 / max(crop.width, crop.height))
        let w = Int(ceil(crop.width * scale)), h = Int(ceil(crop.height * scale))
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.scaleBy(x: scale, y: scale); context.translateBy(x: -crop.minX, y: -crop.minY)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}
