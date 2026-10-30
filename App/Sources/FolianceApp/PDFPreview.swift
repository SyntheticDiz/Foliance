import SwiftUI
import PDFKit

struct PassageTarget: Equatable {
    let id: String
    let page: Int
    let quote: String
}

enum PDFPassageLocator {
    static func selection(in document: PDFDocument, page number: Int, quote: String) -> PDFSelection? {
        guard number >= 1, number <= document.pageCount, let page = document.page(at: number - 1), let text = page.string else { return nil }
        let words = quote.split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }
        if !words.isEmpty, let regex = try? NSRegularExpression(pattern: words.joined(separator: "\\s+"), options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) { return page.selection(for: match.range) }
        // A column-aware quote can be interrupted by the other column in PDFKit's
        // raw stream. Highlight its exact physical lines as a composite selection.
        let lines = quote.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count > 1 else { return nil }
        let combined = PDFSelection(document: document)
        var offset = 0
        for line in lines {
            let pattern = line.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(location: offset, length: (text as NSString).length - offset)),
                  let selection = page.selection(for: match.range) else { return nil }
            combined.add(selection); offset = NSMaxRange(match.range)
        }
        return combined
    }
}

@MainActor final class PDFControls: ObservableObject {
    @Published var selectedText: SelectedPDFText?
    @Published var selectionAnchor: CGPoint?
    private var selectionReleaseTask: Task<Void, Never>?
    func selectionChanged() {
        selectionReleaseTask?.cancel()
        // PDFKit publishes intermediate selections while dragging. Do not put an
        // action under the pointer until the left button has actually been released.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            selectedText = nil; selectionAnchor = nil
            selectionReleaseTask = Task { @MainActor [weak self] in
                while NSEvent.pressedMouseButtons & 1 != 0 {
                    do { try await Task.sleep(nanoseconds: 30_000_000) }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                self?.updateSelection()
            }
        } else { updateSelection() }
    }
    func updateSelection() {
        guard let view, let document = view.document, let selected = view.currentSelection,
              let text = selected.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            selectedText = nil; selectionAnchor = nil; return
        }
        let pages = selected.pages.map { document.index(for: $0) + 1 }.filter { $0 > 0 && $0 <= document.pageCount }
        selectedText = SelectedPDFText(text: text, pages: pages, sources: Self.pageSources(for: selected, in: document, pages: pages))
        let mouse = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        selectionAnchor = CGPoint(x: mouse.x, y: view.isFlipped ? mouse.y : view.bounds.height - mouse.y)
    }
    /// Keeps the complete PDFKit selection as `text`; these are separate literal
    /// per-page excerpts only for source navigation and page-level attribution.
    static func pageSources(for selection: PDFSelection, in document: PDFDocument, pages: [Int]) -> [ChosenPassage.Source] {
        var quotesByPage: [Int: [String]] = [:]
        for line in selection.selectionsByLine() {
            guard let quote = line.string, !quote.isEmpty else { continue }
            for page in line.pages {
                let number = document.index(for: page) + 1
                guard pages.contains(number), number > 0, number <= document.pageCount else { continue }
                quotesByPage[number, default: []].append(quote)
            }
        }
        if pages.count == 1, quotesByPage[pages[0]] == nil, let quote = selection.string, !quote.isEmpty {
            quotesByPage[pages[0]] = [quote]
        }
        return pages.compactMap { page in
            guard let quotes = quotesByPage[page], !quotes.isEmpty else { return nil }
            return ChosenPassage.Source(page: page, quote: quotes.joined(separator: "\n"))
        }
    }
    @Published var page = 1
    @Published var count = 0
    @Published var scale = 1.0
    weak var view: PDFView?
    @Published var pinned: PassageTarget?
    @Published var hovered: PassageTarget?
    @Published var highlightNotice = ""
    private var hoverTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    var active: PassageTarget? { hovered ?? pinned }
    func resetHighlight() {
        highlightTask?.cancel(); highlightTask = nil
        hoverTask?.cancel(); hovered = nil; pinned = nil; highlightNotice = ""; view?.highlightedSelections = nil
    }
    func hover(_ target: PassageTarget, inside: Bool) {
        hoverTask?.cancel()
        if inside {
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                hovered = target; applyHighlight()
            }
        } else if hovered?.id == target.id {
            hovered = nil; applyHighlight()
        }
    }
    func pin(_ target: PassageTarget) {
        hoverTask?.cancel(); hovered = nil; pinned = target; applyHighlight(emphasize: true)
    }
    func applyHighlight(emphasize: Bool = false) {
        highlightTask?.cancel(); highlightTask = nil
        guard let view else { return }
        view.highlightedSelections = nil; highlightNotice = ""
        guard let target = active, let document = view.document else { return }
        guard let selection = PDFPassageLocator.selection(in: document, page: target.page, quote: target.quote) else {
            highlightNotice = "Passage niet exact lokaliseerbaar; de bronpagina wordt getoond."
            if let page = document.page(at: target.page - 1) { view.go(to: page) }
            return
        }
        let animate = emphasize && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        selection.color = NSColor.systemYellow.withAlphaComponent(animate ? 0.65 : 0.32)
        view.highlightedSelections = [selection]
        view.go(to: selection)
        update()
        if animate {
            highlightTask = Task { @MainActor [weak self, weak view] in
                // One brief emphasis, then a persistent quiet source mark.
                for frame in 1...12 {
                    do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
                    guard !Task.isCancelled, let view, view.document === document, self?.active == target else { return }
                    let remaining = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1 - CGFloat(frame) / 12
                    selection.color = NSColor.systemYellow.withAlphaComponent(0.32 + 0.33 * remaining * remaining)
                    view.highlightedSelections = [selection]
                    if remaining == 0 { return }
                }
            }
        }
    }
    func update() {
        guard let view, let document = view.document else { return }
        if count != document.pageCount { count = document.pageCount }
        if let current = view.currentPage { let number = document.index(for: current) + 1; if page != number { page = number } }
        if scale != view.scaleFactor { scale = view.scaleFactor }
    }
    func move(_ delta: Int) {
        guard let view, let target = view.document?.page(at: page - 1 + delta) else { return }
        view.go(to: target); update()
    }
    func zoom(_ factor: Double) {
        guard let view else { return }
        view.autoScales = false
        view.scaleFactor = min(5, max(0.25, view.scaleFactor * factor)); update()
    }
    func fit() { view?.autoScales = true; update() }
}

struct PDFControlsBar: View {
    private let uiLanguage = "en"
    @ObservedObject var controls: PDFControls
    var body: some View {
        HStack(spacing: 12) {
            Button(UIStrings.text("Vorige pagina"), systemImage: "chevron.left") { controls.move(-1) }
                .disabled(controls.page <= 1).labelStyle(.iconOnly).help(UIStrings.text("Vorige pagina"))
            Text("\(controls.page) / \(controls.count)").monospacedDigit().frame(minWidth: 55)
            Button(UIStrings.text("Volgende pagina"), systemImage: "chevron.right") { controls.move(1) }
                .disabled(controls.page >= controls.count).labelStyle(.iconOnly).help(UIStrings.text("Volgende pagina"))
            Divider().frame(height: 20)
            Button(UIStrings.text("Uitzoomen"), systemImage: "minus.magnifyingglass") { controls.zoom(1 / 1.2) }
                .labelStyle(.iconOnly).help(UIStrings.text("Uitzoomen"))
            Button(UIStrings.text("Passend"), systemImage: "arrow.up.left.and.arrow.down.right") { controls.fit() }.help(UIStrings.text("Pagina passend maken"))
            Button(UIStrings.text("Inzoomen"), systemImage: "plus.magnifyingglass") { controls.zoom(1.2) }
                .labelStyle(.iconOnly).help(UIStrings.text("Inzoomen"))
        }.buttonStyle(FocusToolbarActionStyle()).padding(.horizontal, 18).padding(.vertical, 13).modifier(GlassSurface())
    }
}

final class CardPDFView: PDFView {
    override func layout() {
        super.layout()
        configureScrollbars(in: self)
    }
    private func configureScrollbars(in view: NSView) {
        for child in view.subviews {
            if let scroll = child as? NSScrollView {
                if scroll.scrollerStyle != .legacy || scroll.autohidesScrollers || !scroll.hasVerticalScroller || !(scroll.verticalScroller is RoundedScroller) {
                    PersistentScrollbars.apply(to: scroll)
                }
            } else { configureScrollbars(in: child) }
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    let data: Data
    let page: Int
    let navigationID: UUID
    var controls: PDFControls
    final class Coordinator {
        var data: Data?
        var page: Int?
        var navigationID: UUID?
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView {
        let view = CardPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor(SPTheme.surface)
        controls.view = view
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
            context.coordinator.observers.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak controls] _ in
                Task { @MainActor in controls?.update() }
            })
        }
        context.coordinator.observers.append(NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak controls] _ in
            Task { @MainActor in controls?.selectionChanged() }
        })
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.data != data {
            controls.selectedText = nil; controls.selectionAnchor = nil
            view.document = PDFDocument(data: data)
            view.autoScales = true
            context.coordinator.data = data
            context.coordinator.page = nil
        }
        if context.coordinator.page != page || context.coordinator.navigationID != navigationID, let target = view.document?.page(at: page - 1) {
            view.go(to: target)
            context.coordinator.page = page
            context.coordinator.navigationID = navigationID
        }
        Task { @MainActor in
            controls.update()
            if controls.pinned != nil && view.highlightedSelections == nil { controls.applyHighlight() }
        }
    }
}
