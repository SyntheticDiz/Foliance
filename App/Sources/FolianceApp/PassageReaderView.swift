import AppKit
import SwiftUI

struct PassageReaderView: View {
    let showSource: (Int, String) -> Void
    private let content: PassageReaderContent
    @Environment(\.dismiss) private var dismiss
    private let uiLanguage = "en"
    @State private var query = ""
    @State private var matches: [NSRange] = []
    @State private var searchIndex: PassageReaderContent.SearchIndex?
    @State private var searchIndexTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchIndexGeneration = UUID()
    @State private var searchGeneration = UUID()
    @State private var activeMatch = -1
    @State private var activeCue: Int?
    @State private var showsFindings = false
    @State private var cues: [PassageReaderCue]
    @State private var showsSourceAid = false
    @State private var sourceAidResult: SourceReadingAid.Result?
    @State private var sourceAidTask: Task<Void, Never>?
    @State private var enabledAidCategories: Set<SourceAidCategory> = []
    @State private var selectedAnchorID: Int?
    @State private var showsAnchorContext = false

    private var isEnglish: Bool { true }

    init(point: Insight, showSource: @escaping (Int, String) -> Void, showsFindings: Bool = false,
         showsSourceAid: Bool = false, sourceAidCategories: Set<SourceAidCategory> = []) {
        self.showSource = showSource
        let content = PassageReaderContent(point: point)
        self.content = content
        _cues = State(initialValue: PassageReaderContent.cues(in: content.text))
        _showsFindings = State(initialValue: showsFindings)
        _showsSourceAid = State(initialValue: showsSourceAid)
        _enabledAidCategories = State(initialValue: sourceAidCategories)
    }

    init(chosenPassage: ChosenPassage, showSource: @escaping (Int, String) -> Void) {
        self.showSource = showSource
        let content = PassageReaderContent(chosenPassage: chosenPassage)
        self.content = content
        _cues = State(initialValue: PassageReaderContent.cues(in: content.text))
        _showsFindings = State(initialValue: false)
        _showsSourceAid = State(initialValue: false)
        _enabledAidCategories = State(initialValue: [])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 10) {
                TextField(label("Zoek in de tekst…", "Search the passage…"), text: $query)
                    .textFieldStyle(FocusInputFieldStyle())
                    .accessibilityLabel(label("Zoek in de volledige passage", "Search the full passage"))
                    .onChange(of: query) { _, value in
                        activeMatch = -1
                        activeCue = nil
                        clearSourceAidSelection()
                        search(value)
                    }
                    .onSubmit { navigate(1) }
                Button { navigate(-1) } label: { Image(systemName: "chevron.up") }
                    .help(label("Vorige treffer", "Previous match"))
                    .accessibilityLabel(label("Vorige treffer", "Previous match"))
                    .disabled(matches.isEmpty)
                Button { navigate(1) } label: { Image(systemName: "chevron.down") }
                    .help(label("Volgende treffer", "Next match"))
                    .accessibilityLabel(label("Volgende treffer", "Next match"))
                    .disabled(matches.isEmpty)
                Text(matchStatus).font(.caption).foregroundStyle(.secondary).frame(minWidth: 82, alignment: .trailing).monospacedDigit()
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            if !content.isCompletePassage {
                if content.provenance == .legacyQuote {
                    Label(label("Alleen het geselecteerde citaat is beschikbaar; dit is niet de volledige alinea.", "Only the selected excerpt is available; this is not the full paragraph."), systemImage: "quote.opening")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                } else if let note = content.userNote {
                    DisclosureGroup(label("Eigen notitie", "Your note")) {
                        ScrollView {
                            Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }.frame(maxHeight: 120)
                    }
                    .font(.caption)
                    .padding(.horizontal, 18).padding(.vertical, 6)
                }
            }
            HStack(spacing: 0) {
                if showsFindings && !cues.isEmpty { cuePanel.frame(width: 245) }
                PassageTextView(text: content.text, matches: matches, activeMatch: activeMatch, activeCue: selectedCueRange,
                                aidRanges: visibleAnchorRanges, contextRanges: visibleContextRanges, aidTarget: selectedAnchorRange, close: { dismiss() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            }
            Divider()
            HStack {
                Text(content.sources.map { label("PDF-pagina \($0.page)", "PDF page \($0.page)") }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !cues.isEmpty {
                    Button { showsFindings.toggle() } label: {
                        Label(label(showsFindings ? "Verberg vindplaatsen" : "Vindplaatsen", showsFindings ? "Hide findings" : "Findings"), systemImage: "text.magnifyingglass")
                    }.buttonStyle(FocusQuietActionStyle()).accessibilityHint(label("Toont optionele, letterlijke zoekhulp", "Shows optional literal search hints"))
                }
                Button {
                    showsSourceAid.toggle()
                    if showsSourceAid { requestSourceAid() }
                } label: {
                    Label(label("Bronhulp", "Source aid"), systemImage: "text.viewfinder")
                }
                .buttonStyle(FocusQuietActionStyle())
                .popover(isPresented: $showsSourceAid, arrowEdge: .bottom) { sourceAidPanel }
                .accessibilityHint(label("Toont optionele markeringen voor data, bedragen en voorwaarden", "Shows optional highlights for dates, amounts, and conditions"))
                Menu {
                    ForEach(Array(content.sources.enumerated()), id: \.offset) { _, source in
                        Button(label("Open bron op PDF-pagina \(source.page)", "Open source on PDF page \(source.page)")) {
                            dismiss()
                            DispatchQueue.main.async { showSource(source.page, source.quote) }
                        }
                    }
                } label: { Text(label("Bronnen", "Sources")).foregroundStyle(Color.primary) }
                .focusMenu()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content.text, forType: .string)
                } label: {
                    Label(label("Kopieer tekst", "Copy text"), systemImage: "doc.on.doc")
                }
                Button(label("Sluit", "Close")) { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity, minHeight: 420, idealHeight: 700, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: matches.count) { _, count in
            if count == 0 { activeMatch = -1 }
            else if activeMatch >= 0 { activeMatch = min(activeMatch, count - 1) }
        }
        .onChange(of: content.text) { _, newText in
            rebuildSearchIndex(for: newText)
            sourceAidTask?.cancel()
            sourceAidTask = nil
            sourceAidResult = nil
            enabledAidCategories = []
            clearSourceAidSelection()
            query = ""
            matches = []
            activeMatch = -1
            activeCue = nil
            cues = PassageReaderContent.cues(in: newText)
            if showsSourceAid { requestSourceAid() }
        }
        .onDisappear {
            searchIndexTask?.cancel()
            searchIndexTask = nil
            searchTask?.cancel()
            searchTask = nil
            searchIndex = nil
            matches = []
            searchIndexGeneration = UUID()
            searchGeneration = UUID()
            sourceAidTask?.cancel()
            sourceAidTask = nil
        }
        .onAppear {
            rebuildSearchIndex(for: content.text)
            if showsSourceAid { requestSourceAid() }
        }
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title).font(.title2.weight(.semibold)).lineLimit(2)
            Text(provenanceLabel)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var provenanceLabel: String {
        let pages = content.sources.map { String($0.page) }.joined(separator: ", ")
        switch content.provenance {
        case .fullParagraph:
            return label("Volledige alinea · PDF-pagina’s \(pages)", "Full paragraph · PDF pages \(pages)")
        case .legacyQuote:
            return label("Geselecteerd citaat · PDF-pagina \(pages)", "Selected excerpt · PDF page \(pages)")
        case .chosenSelection:
            return label("Zelf gekozen tekst · PDF-pagina’s \(pages)", "Your selected text · PDF pages \(pages)")
        }
    }

    private var cuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label("Vindplaatsen — geen volledige analyse", "Findings — not a full analysis"))
                .font(.callout.weight(.semibold))
            Text(label("Deze letterlijke zoekhulp toont zinnen met herkenbare termen. Een trefwoord kan ook een andere betekenis hebben. Voorwaarden kunnen op meerdere plaatsen staan; deze hulp kan zinnen missen. Lees daarom de hele passage.", "This literal search aid shows sentences with recognizable terms. A term can have another meaning. Conditions may appear in several places, and this aid can miss sentences. Read the whole passage."))
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cues) { cue in
                        Button {
                            activeCue = cue.id
                            activeMatch = -1
                            clearSourceAidSelection()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cueLabel(cue.kind)).font(.caption.bold()).foregroundStyle(.tint)
                                Text(cue.text).font(.callout).multilineTextAlignment(.leading).foregroundStyle(.primary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .background(activeCue == cue.id ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: .infinity)
        }
        .padding(12).background(Color.primary.opacity(0.035))
        .overlay(alignment: .trailing) { Divider() }
    }

    private var sourceAidPanel: some View {
        PassageSourceAidPanel(isEnglish: isEnglish, anchors: sourceAidResult?.anchors ?? [], isLoading: sourceAidResult == nil,
                              enabledCategories: $enabledAidCategories, selectedAnchorID: $selectedAnchorID,
                              showsContext: $showsAnchorContext,
                              onCategoryToggle: setAidCategory,
                              onAnchorSelected: { activeCue = nil; activeMatch = -1 },
                              onContextToggle: {
                                  guard selectedAnchor != nil else { return }
                                  showsAnchorContext.toggle()
                                  if showsAnchorContext { showsSourceAid = false }
                              },
                              onClear: { enabledAidCategories = []; clearSourceAidSelection() })
    }

    private var visibleAnchors: [SourceReadingAid.Anchor] {
        (sourceAidResult?.anchors ?? []).filter { enabledAidCategories.contains($0.category) }
    }

    private var selectedAnchor: SourceReadingAid.Anchor? {
        visibleAnchors.first { $0.id == selectedAnchorID }
    }

    private var visibleAnchorRanges: [NSRange] { visibleAnchors.map(\.range) }
    private var selectedAnchorRange: NSRange? { selectedAnchor?.range }
    private var visibleContextRanges: [NSRange] { showsAnchorContext ? (selectedAnchor?.contextRanges ?? []) : [] }

    private func requestSourceAid() {
        guard sourceAidResult == nil, sourceAidTask == nil else { return }
        let text = content.text
        sourceAidTask = Task {
            let worker = Task.detached(priority: .userInitiated) { SourceReadingAid.analyze(text) }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            sourceAidResult = result
            sourceAidTask = nil
        }
    }

    private func rebuildSearchIndex(for text: String) {
        searchIndexTask?.cancel()
        searchTask?.cancel()
        searchIndex = nil
        matches = []
        activeMatch = -1
        let generation = UUID()
        searchIndexGeneration = generation
        searchIndexTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try PassageReaderContent.SearchIndex.build(text: text, cancellationCheck: { Task.isCancelled })
            }
            do {
                let index = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() })
                guard !Task.isCancelled, searchIndexGeneration == generation, content.text == text else { return }
                searchIndex = index
                searchIndexTask = nil
                search(query)
            } catch {
                if searchIndexGeneration == generation { searchIndexTask = nil }
            }
        }
    }

    private func search(_ value: String) {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        guard let index = searchIndex else {
            matches = []
            return
        }
        let sourceText = content.text
        searchTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try index.matches(query: value, cancellationCheck: { Task.isCancelled })
            }
            do {
                let result = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() })
                guard !Task.isCancelled, searchGeneration == generation,
                      content.text == sourceText, query == value else { return }
                matches = result
                searchTask = nil
            } catch {
                if searchGeneration == generation { searchTask = nil }
            }
        }
    }

    private func setAidCategory(_ category: SourceAidCategory, enabled: Bool) {
        if enabled { enabledAidCategories.insert(category) }
        else {
            let selectedCategory = sourceAidResult?.anchors.first(where: { $0.id == selectedAnchorID })?.category
            enabledAidCategories.remove(category)
            if selectedCategory == category { clearSourceAidSelection() }
        }
        if enabled { requestSourceAid() }
    }

    private func clearSourceAidSelection() {
        selectedAnchorID = nil
        showsAnchorContext = false
    }

    private var selectedCueRange: NSRange? {
        guard let activeCue, cues.indices.contains(activeCue) else { return nil }
        return cues[activeCue].range
    }

    private var matchStatus: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return label("Geen zoekterm", "No search term") }
        if searchIndexTask != nil || searchTask != nil { return label("Zoeken…", "Searching…") }
        guard !matches.isEmpty else { return label("Geen treffers", "No matches") }
        if activeMatch < 0 { return PassageReaderContent.matchCountDescription(matches.count, isEnglish: isEnglish) }
        return "\(min(activeMatch + 1, matches.count)) \(label("van", "of")) \(matches.count)"
    }

    private func navigate(_ delta: Int) {
        guard !matches.isEmpty else { return }
        if activeMatch < 0 { activeMatch = delta < 0 ? matches.count - 1 : 0 }
        else { activeMatch = (activeMatch + delta + matches.count) % matches.count }
        activeCue = nil
        clearSourceAidSelection()
    }

    private func label(_ original: String, _ english: String) -> String { english }
    private func cueLabel(_ dutch: String) -> String {
        guard isEnglish else { return dutch }
        return dutch.replacingOccurrences(of: "Termijn of datum", with: "Deadline or date")
            .replacingOccurrences(of: "Woorden bij voorwaarden", with: "Condition words")
            .replacingOccurrences(of: "Woorden over besluiten", with: "Decision words")
    }
}

struct PassageSourceAidPanel: View {
    let isEnglish: Bool
    let anchors: [SourceReadingAid.Anchor]
    let isLoading: Bool
    @Binding var enabledCategories: Set<SourceAidCategory>
    @Binding var selectedAnchorID: Int?
    @Binding var showsContext: Bool
    let onCategoryToggle: (SourceAidCategory, Bool) -> Void
    let onAnchorSelected: () -> Void
    let onContextToggle: () -> Void
    let onClear: () -> Void

    private var visibleAnchors: [SourceReadingAid.Anchor] {
        anchors.filter { enabledCategories.contains($0.category) }
    }

    private var selectedAnchor: SourceReadingAid.Anchor? {
        visibleAnchors.first { $0.id == selectedAnchorID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label("Bronhulp", "Source aid")).font(.headline)
            Text(label("Optionele markeringen van herkenbare passages. Controleer altijd de volledige brontekst.", "Optional highlights for recognizable passages. Always check the full source text."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(label("De context wordt in de volledige bron gemarkeerd.", "Context is highlighted in the full source."))
                .font(.caption2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(SourceAidCategory.allCases, id: \.self) { category in
                    Toggle(categoryLabel(category), isOn: Binding(
                        get: { enabledCategories.contains(category) },
                        set: { onCategoryToggle(category, $0) }
                    )).toggleStyle(.checkbox)
                }
            }
            Divider()
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(label("Bronhulp wordt geladen…", "Loading source aid…")).font(.caption).foregroundStyle(.secondary)
                }
            } else if enabledCategories.isEmpty {
                Text(label("Schakel een categorie in om markeringen te tonen.", "Enable a category to show highlights."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if visibleAnchors.isEmpty {
                Text(label("Geen herkenbare passages voor deze categorieën.", "No recognizable passages in these categories."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(label("Herkenbare passages", "Recognizable passages")).font(.caption.bold())
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(visibleAnchors, id: \.id) { anchor in
                            Button {
                                selectedAnchorID = anchor.id
                                showsContext = false
                                onAnchorSelected()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(categoryLabel(anchor.category)).font(.caption.bold()).foregroundStyle(.tint)
                                    Text(anchor.text).font(.callout).multilineTextAlignment(.leading).foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(selectedAnchorID == anchor.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 190)
                Button(action: onContextToggle) {
                    Label(label(showsContext ? "Verberg bredere context" : "Toon bredere context",
                                showsContext ? "Hide broader context" : "Show broader context"),
                          systemImage: showsContext ? "text.quote.fill" : "text.quote")
                }
                .disabled(selectedAnchor == nil || selectedAnchor?.contextRanges.isEmpty != false)
                .help(label("Markeert de omringende brontekst zonder tekst te vervangen", "Highlights the surrounding source text without replacing any text"))
            }
            Button(label("Wis markeringen", "Clear highlights"), action: onClear).buttonStyle(FocusQuietActionStyle())
        }
        .padding(14).frame(width: 320, height: 420, alignment: .topLeading)
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }

    private func categoryLabel(_ category: SourceAidCategory) -> String {
        switch category {
        case .dates: return label("Datums en termijnen", "Dates and periods")
        case .amounts: return label("Bedragen", "Amounts")
        case .conditions: return label("Voorwaarden en statuswoorden", "Conditions and status terms")
        }
    }

    private func label(_ original: String, _ english: String) -> String { english }
}

struct PassageTextView: NSViewRepresentable {
    let text: String
    let matches: [NSRange]
    let activeMatch: Int
    let activeCue: NSRange?
    var aidRanges: [NSRange] = []
    var contextRanges: [NSRange] = []
    var aidTarget: NSRange? = nil
    let close: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.drawsBackground = false
        let textView = PassageNSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont(name: "New York", size: 19) ?? NSFont.systemFont(ofSize: 18)
        textView.textColor = .labelColor
        textView.close = close
        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PassageNSTextView else { return }
        let changedText = view.string != text
        if changedText { view.string = text }
        let style = Coordinator.Style(matches: matches, activeMatch: activeMatch, activeCue: activeCue, aidRanges: aidRanges, contextRanges: contextRanges)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        if changedText || context.coordinator.lastStyle != style {
            if fullRange.length > 0 {
                let selectedRanges = view.selectedRanges
                view.textStorage?.beginEditing()
                view.textStorage?.setAttributes([.font: view.font ?? NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.labelColor], range: fullRange)
                for range in contextRanges where range.location >= 0 && NSMaxRange(range) <= fullRange.length {
                    view.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemTeal.withAlphaComponent(0.22), range: range)
                }
                for range in aidRanges where range.location >= 0 && NSMaxRange(range) <= fullRange.length {
                    view.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.20), range: range)
                }
                if let activeCue, activeCue.location >= 0, NSMaxRange(activeCue) <= fullRange.length {
                    view.textStorage?.addAttribute(.backgroundColor, value: NSColor.systemBlue.withAlphaComponent(0.20), range: activeCue)
                }
                for (index, range) in matches.enumerated() where range.location >= 0 && NSMaxRange(range) <= fullRange.length {
                    view.textStorage?.addAttribute(.backgroundColor, value: index == activeMatch ? NSColor.systemOrange.withAlphaComponent(0.55) : NSColor.systemYellow.withAlphaComponent(0.35), range: range)
                }
                view.textStorage?.endEditing()
                view.selectedRanges = selectedRanges
            }
            context.coordinator.lastStyle = style
        }
        let target = activeMatch >= 0 && matches.indices.contains(activeMatch) ? matches[activeMatch] : (activeCue ?? aidTarget)
        guard changedText || context.coordinator.lastTarget != target else { return }
        context.coordinator.lastTarget = target
        if let target { view.scrollRangeToVisible(target) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        struct Style: Equatable {
            let matches: [NSRange]
            let activeMatch: Int
            let activeCue: NSRange?
            let aidRanges: [NSRange]
            let contextRanges: [NSRange]
        }
        weak var textView: PassageNSTextView?
        var lastTarget: NSRange?
        var lastStyle: Style?
    }
}

final class PassageNSTextView: NSTextView {
    var close: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close?(); return }
        super.keyDown(with: event)
    }
}
