import SwiftUI

/// Card-specific wrapper that keeps the established passage reader intact and
/// makes every source role available in the same sheet.
struct CardPassageReaderView: View {
    let point: Insight
    let sources: CardSourceCollection
    let showSource: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let uiLanguage = "en"
    @State private var selection = 0

    init(point: Insight, sources: CardSourceCollection, showSource: @escaping (Int, String) -> Void) {
        self.point = point
        self.sources = sources
        self.showSource = showSource
        let hasPassage = !point.quote.isEmpty || !(point.passageSources ?? []).isEmpty
        _selection = State(initialValue: hasPassage ? 0 : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            FocusChoiceTabs(label("Leesweergave", "Reading view"), selection: $selection, options: [
                FocusChoiceOption(value: 0, title: label("Passage", "Passage")),
                FocusChoiceOption(value: 1, title: label("Bronnen", "Sources"))
            ])
            .frame(maxWidth: 320)
            .padding(.vertical, 10)
            Divider()
            ZStack {
                PassageReaderView(point: point, showSource: showSource)
                    .opacity(selection == 0 ? 1 : 0)
                    .allowsHitTesting(selection == 0)
                    .disabled(selection != 0)
                    .accessibilityHidden(selection != 0)
                    .zIndex(selection == 0 ? 1 : 0)
                sourceList
            }
        }
        .frame(minWidth: 600, idealWidth: 900, maxWidth: .infinity,
               minHeight: 420, idealHeight: 700, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(sources.entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.roles.map { UIStrings.text($0, language: uiLanguage) }.joined(separator: " · "))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if let page = entry.page {
                                Button(UIStrings.text("Toon in PDF · p. \(page)", language: uiLanguage)) {
                                    openSource(page, entry.text)
                                }.buttonStyle(FocusQuietActionStyle())
                            }
                            SourceQuoteView(text: entry.text)
                        }
                    }
                    if sources.entries.isEmpty {
                        Text(label("Geen aanvullende bronnen beschikbaar.", "No additional sources are available."))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                Button(label("Sluit", "Close")) { dismiss() }
                    .buttonStyle(FocusSecondaryButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .opacity(selection == 1 ? 1 : 0)
        .allowsHitTesting(selection == 1)
        .disabled(selection != 1)
        .accessibilityHidden(selection != 1)
        .zIndex(selection == 1 ? 1 : 0)
    }

    private func openSource(_ page: Int, _ quote: String) {
        dismiss()
        DispatchQueue.main.async { showSource(page, quote) }
    }

    private func label(_ original: String, _ english: String) -> String { english }
}
