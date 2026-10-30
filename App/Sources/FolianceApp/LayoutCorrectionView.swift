import SwiftUI
import PDFKit

struct LayoutCorrectionView: View {
    @ObservedObject var workspace: SimpleWorkspace
    let model: String
    let compareProgram: Bool
    let visiblePage: Int
    @Environment(\.dismiss) private var dismiss
    @State private var page = 1
    @State private var columns = 0
    @State private var region: CGRect?
    @State private var image: NSImage?
    @State private var imageSize = CGSize(width: 400, height: 520)
    @State private var preview = ""
    @State private var error: String?
    @State private var saving = false

    static func clampedPage(_ requested: Int, count: Int) -> Int {
        min(max(1, requested), max(1, count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIStrings.text("Tekstindeling controleren")).font(.title2.bold())
            Text(UIStrings.text("Dit is een optioneel vangnet. De app bepaalt de leesvolgorde normaal automatisch en slaat onzekere pagina’s over."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geometry in
                VStack(spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Stepper(UIStrings.text("PDF-pagina \(page)"), value: $page,
                                        in: 1...max(1, workspace.document?.pages.count ?? 1)).disabled(saving)
                                FocusMenuPicker(UIStrings.text("Indeling"), selection: $columns,
                                                selectedTitle: UIStrings.text([0: "Automatisch", 1: "Eén kolom", 2: "Twee kolommen", 3: "Drie kolommen"][columns] ?? "Automatisch")) {
                                    Text(UIStrings.text("Automatisch")).tag(0)
                                    Text(UIStrings.text("Eén kolom")).tag(1)
                                    Text(UIStrings.text("Twee kolommen")).tag(2)
                                    Text(UIStrings.text("Drie kolommen")).tag(3)
                                }
                                .frame(maxWidth: 280).disabled(saving)
                            }
                            if geometry.size.width >= 760 {
                                HStack(alignment: .top, spacing: 18) {
                                    pagePreview.frame(maxWidth: .infinity, alignment: .leading)
                                    readingPreview.frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    pagePreview
                                    readingPreview
                                }
                            }
                            Text(UIStrings.text("Opslaan vervangt de tekstindeling. Eerdere analyseresultaten worden ongeldig en de analyse wordt opnieuw gestart."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error { Text(UIStrings.text(error)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button(UIStrings.text("Annuleren")) { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                            Spacer()
                            if saving { ProgressView().controlSize(.small) }
                            saveButton
                        }
                        VStack(alignment: .trailing, spacing: 8) {
                            if saving { ProgressView().controlSize(.small) }
                            saveButton
                            Button(UIStrings.text("Annuleren")) { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 940, minHeight: 420, idealHeight: 760)
        .onAppear {
            page = Self.clampedPage(visiblePage, count: workspace.document?.pages.count ?? 1)
            loadPage()
        }
        .onChange(of: page) { _, _ in loadPage() }
        .onChange(of: columns) { _, _ in updatePreview() }
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private var saveButton: some View {
        Button(UIStrings.text("Bewaren en opnieuw analyseren")) {
                            saving = true
                            Task { @MainActor in
                                do {
                                    try await workspace.correctLayout(page: page, override: .init(columns: columns, region: region))
                                    workspace.analyze(model: model, context: workspace.focus, compareProgram: compareProgram)
                                    dismiss()
                                } catch { self.error = error.localizedDescription; saving = false }
                            }
        }.buttonStyle(FocusPrimaryButtonStyle()).disabled(saving || workspace.busy || preview.isEmpty)
            .keyboardShortcut(.defaultAction)
    }

    private var pagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Sleep optioneel een kader om alleen dat tekstgebied te verwerken.")).font(.caption)
            if let image {
                GeometryReader { container in
                    let scale = min(container.size.width / max(1, imageSize.width),
                                    container.size.height / max(1, imageSize.height))
                    let displaySize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: displaySize.width, height: displaySize.height)
                        ZStack(alignment: .topLeading) {
                            if let region {
                                Rectangle().fill(Color.accentColor.opacity(0.12))
                                    .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 2))
                                    .frame(width: region.width * displaySize.width, height: region.height * displaySize.height)
                                    .offset(x: region.minX * displaySize.width, y: (1 - region.maxY) * displaySize.height)
                                    .allowsHitTesting(false)
                            }
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                                    let width = max(1, displaySize.width), height = max(1, displaySize.height)
                                    let a = value.startLocation, b = value.location
                                    let x1 = max(0, min(width, min(a.x, b.x))), x2 = max(0, min(width, max(a.x, b.x)))
                                    let y1 = max(0, min(height, min(a.y, b.y))), y2 = max(0, min(height, max(a.y, b.y)))
                                    region = CGRect(x: x1 / width, y: 1 - y2 / height,
                                                    width: (x2-x1) / width, height: (y2-y1) / height)
                                }.onEnded { _ in
                                    if let region, region.width < 0.03 || region.height < 0.03 { self.region = nil }
                                    updatePreview()
                                })
                                .allowsHitTesting(!saving)
                        }
                        .frame(width: displaySize.width, height: displaySize.height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(height: min(imageSize.height, 420))
                    .accessibilityLabel(UIStrings.text("PDF-pagina \(page) — sleep een kader rond het tekstgebied"))
            }
            Button(UIStrings.text("Hele pagina gebruiken")) { region = nil; updatePreview() }
                .disabled(region == nil || saving)
        }
    }

    private var readingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Herkende leesvolgorde")).font(.headline)
            ScrollView {
                Text(preview).font(.body).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180, maxHeight: 420)
            .accessibilityLabel(UIStrings.text("Voorbeeld van de herkende leesvolgorde"))
        }
    }

    private func loadPage() {
        guard let document = workspace.document, let pdf = PDFDocument(data: document.data), let source = pdf.page(at: page - 1) else { return }
        let bounds = source.bounds(for: .cropBox)
        let scale = min(500 / bounds.height, 500 / bounds.width)
        imageSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        image = source.thumbnail(of: CGSize(width: imageSize.width * 2, height: imageSize.height * 2), for: .cropBox)
        do { let saved = try LayoutStore.read(document.data)[page] ?? LayoutOverride(); columns = saved.columns; region = saved.region; error = nil }
        catch { self.error = error.localizedDescription }
        updatePreview()
    }

    private func updatePreview() {
        guard let document = workspace.document, let source = PDFDocument(data: document.data)?.page(at: page - 1) else { return }
        let bounds = source.bounds(for: .cropBox)
        let area = region.map { CGRect(x: bounds.minX + $0.minX * bounds.width, y: bounds.minY + $0.minY * bounds.height, width: $0.width * bounds.width, height: $0.height * bounds.height) }
        let words = PageLayout.words(source).filter { area == nil || area!.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
        let reading = PageLayout.order(words, bounds: bounds, columns: columns)
        preview = reading.text; if !reading.notice.isEmpty { error = reading.notice } else { error = nil }
    }
}
