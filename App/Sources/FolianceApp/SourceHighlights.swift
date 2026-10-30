import SwiftUI
import Foundation

/// Literal source excerpts, not inferred decisions or inferred deadlines.
enum SourceHighlights {
    enum Kind: String, CaseIterable, Codable, Sendable { case decisions = "Voorstellen & besluiten", amounts = "Geld & gevolgen", dates = "Planning & voorwaarden" }
    struct Item: Identifiable, Codable, Sendable {
        let kind: Kind
        let page: Int
        let quote: String
        var title: String = ""
        var decisionStatus: String = ""
        var importance: Int = 0
        var passageSources: [Insight.Source]? = nil
        var passageID: String? = nil
        var assessmentNotice: String? = nil
        var id: String { passageID.map { "\(kind.rawValue)-\($0)" } ?? "\(kind.rawValue)-\(page)-\(quote)" }

        var readerPoint: Insight {
            Insight(title: title.isEmpty ? "Bronpassage" : title, summary: "", relevance: "", question: "",
                    quote: quote, page: page, passageSources: passageSources)
        }
    }
    private static func isNavigationOnly(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func leader(_ line: String) -> Bool {
            line.count < 200 && line.range(of: #"^.*\.{3,}\s*\d+\s*$"#, options: .regularExpression) != nil
        }
        return lines.contains(where: leader) && lines.allSatisfy { leader($0) || $0.lowercased() == "inhoudsopgave" }
    }

    static func extract(_ pages: [String]) -> [Item] {
        extract(passages: PassageEngine.passages(pages))
    }
    static func extract(passages: [PassageEngine.Passage]) -> [Item] {
        let writtenNumbers = "een|één|twee|drie|vier|vijf|zes|zeven|acht|negen|tien|elf|twaalf|dertien|veertien|vijftien|zestien|zeventien|achttien|negentien|twintig"
        let patterns: [(Kind, String)] = [
            (.decisions, #"(?i)\b(besluit|besluiten|besloten|vaststellen|instemmen|voorgesteld|stelt\s+voor)\b"#),
            (.amounts, #"(?i)(€\s*\d|\b\d[\d.,]*\s*(miljoen|miljard|euro)\b)"#),
            (.dates, #"(?i)\b(uiterlijk|deadline|mits|voorwaarde|onder voorbehoud|vóór|voor\s+\d|vanaf\s+\d|per\s+\d|binnen\s+(\d+|"# + writtenNumbers + #")\s+(werk)?(dag(?:en)?|weken|week|maand(?:en)?|jaren|jaar|uren|uur)|binnen\s+\d|inwerkingtreding)\b"#)
        ].compactMap { kind, pattern in (kind, pattern) }
        var items: [Item] = []
        let regexes = patterns.compactMap { kind, pattern in (try? NSRegularExpression(pattern: pattern)).map { (kind, $0) } }
        for passage in passages {
            let quote = passage.text
            guard !isNavigationOnly(quote), quote.trimmingCharacters(in: .whitespacesAndNewlines).count >= 25,
                  let page = passage.sources.first?.page else { continue }
            for (kind, regex) in regexes {
                if regex.firstMatch(in: quote, range: NSRange(quote.startIndex..., in: quote)) != nil {
                    items.append(.init(kind: kind, page: page, quote: quote,
                                       passageSources: passage.sources, passageID: passage.id))
                }
            }
        }
        return items
    }
}


struct SourceHighlightsView: View {
    @ObservedObject var workspace: SimpleWorkspace
    let showSource: (Int, String) -> Void
    var sourceBound: Bool = false
    var tutorialSelected: SourceHighlights.Kind? = nil
    @State private var selected = SourceHighlights.Kind.decisions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAll = false
    @State private var evidencePresentation: EvidencePresentation?
    private let uiLanguage = "en"

    private enum EvidencePresentation: Identifiable {
        case passage(SourceHighlights.Item)
        case broadContext(SourceHighlights.Item)

        var id: String {
            switch self {
            case .passage(let item): "passage-\(item.id)"
            case .broadContext(let item): "context-\(item.id)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(UIStrings.text(sourceBound ? "Kerngegevens uit de bron" : "Concrete bronpassages")).font(.title2.bold())
            Text(UIStrings.text(workspace.highlightScope)).font(.caption).foregroundStyle(.secondary)
            Text(UIStrings.text("AI selecteerde deze voorbeeldpassages. De selectie is niet volledig en AI-toelichtingen kunnen onjuist zijn. Controleer de letterlijke passage en de volledige bron in de PDF; scans zonder tekstlaag kunnen ontbreken."))
                .font(.callout).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { categoryButtons }
                VStack(alignment: .leading, spacing: 8) { categoryButtons }
            }
            let matches = workspace.keyPoints.filter { $0.kind == selected }
            if matches.isEmpty {
                Text(UIStrings.text(workspace.busy ? "Deze selectie wordt nog verwerkt…" : workspace.keyPointsReady ? "Geen relevante punten in deze categorie gevonden." : "Start de analyse om relevante kernpunten te selecteren.")).foregroundStyle(.secondary)
            }
            ForEach(Array((showAll ? matches : Array(matches.prefix(5))).enumerated()), id: \.element.id) { _, item in
                let evidence = sourceBound ? workspace.document.flatMap { SourceBoundEvidence.validate(item: item, pages: $0.pages) } : nil
                SourceHighlightCard(
                    item: item,
                    quote: sourceBound ? (evidence?.quote ?? "") : item.quote,
                    sourceQuote: sourceBound ? (evidence?.quote ?? item.passageSources?.first?.quote ?? "") : (item.passageSources?.first?.quote ?? item.quote),
                    page: sourceBound ? min(max(1, item.page), max(1, workspace.document?.pages.count ?? 1)) : item.page,
                    warning: sourceBound && evidence == nil ? "Bron niet geverifieerd op de opgegeven PDF-pagina. Controleer de oorspronkelijke pagina." : nil,
                    uiLanguage: uiLanguage,
                    showSource: showSource,
                    readPassage: { evidencePresentation = .passage(item) },
                    broadContext: { evidencePresentation = .broadContext(item) }
                )
            }
            if matches.count > 5 { Button(UIStrings.text(showAll ? "Toon minder" : "Toon meer")) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showAll.toggle() } } }
            if !workspace.keyPointIssues.isEmpty {
                Text(UIStrings.text("De kernselectie is onvolledig. Bekijk de verwerkingsstatus bovenaan.")).font(.caption).foregroundStyle(.orange)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .onChange(of: selected) { _, _ in showAll = false }
            .onAppear { if let tutorialSelected { selected = tutorialSelected } }
            .onChange(of: tutorialSelected) { _, value in if let value { selected = value } }
            // Category changes replace variable-height lists; do not animate the
            // surrounding controls and make their text appear to jump.
            .transaction { $0.animation = nil }
            .sheet(item: $evidencePresentation) { presentation in
                switch presentation {
                case .passage(let item):
                    PassageReaderView(point: item.readerPoint, showSource: showSource)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                case .broadContext(let item):
                    SourceBoundEvidenceView(item: item, pages: workspace.document?.pages ?? [], showSource: showSource)
                }
            }
    }
    private var categoryButtons: some View {
        ForEach(SourceHighlights.Kind.allCases, id: \.self) { kind in
            Button { selected = kind } label: {
                Text(UIStrings.text(kind.rawValue))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    .background(selected == kind ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected == kind ? Color.accentColor.opacity(0.6) : .clear) }
            }.buttonStyle(.plain)
                .accessibilityAddTraits(selected == kind ? .isSelected : [])
                .accessibilityValue(UIStrings.text(selected == kind ? "Geselecteerd" : "Niet geselecteerd"))
                .tutorialTarget(kind == .amounts ? "amounts" : "category-\(kind.rawValue)")
        }
    }
}

struct SourceHighlightCard: View {
    let item: SourceHighlights.Item
    let quote: String
    let sourceQuote: String
    let page: Int
    let warning: String?
    let uiLanguage: String
    let showSource: (Int, String) -> Void
    let readPassage: () -> Void
    let broadContext: () -> Void
    @State private var isExpanded = false
    @State private var explanationExpanded = false

    private var presentation: SourceCardText.Presentation {
        SourceCardText.presentation(quote: quote, fallbackTitle: item.title.count <= 100 ? item.title : "Bronpassage")
    }

    private var explanationTitle: String? {
        let aiTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aiTitle.isEmpty,
              normalizedForDisplayComparison(aiTitle) != normalizedForDisplayComparison(presentation.title) else { return nil }
        return aiTitle
    }

    private func normalizedForDisplayComparison(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .localizedLowercase
    }

    private var hasExplanation: Bool {
        explanationTitle != nil || !item.decisionStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !(item.assessmentNotice ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                Text(presentation.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(UIStrings.text(isExpanded ? "Toont weer een korte tekstweergave" : "Toont de volledige tekst"))

            if !presentation.body.isEmpty {
                FadingPreviewText(text: presentation.body, font: .system(size: 14), lineSpacing: 4.5, collapsedLines: 4,
                                  language: uiLanguage, isExpanded: $isExpanded)
            }

            if let warning {
                Text(UIStrings.text(warning)).font(.callout).foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                footer(horizontal: true)
                footer(horizontal: false)
            }

            if hasExplanation {
                Rectangle().fill(Color.secondary.opacity(0.28)).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        explanationExpanded.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text(UIStrings.text("Waarom dit punt?"))
                            Spacer(minLength: 4)
                            Image(systemName: explanationExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if explanationExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            if let notice = item.assessmentNotice, !notice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(UIStrings.text(notice)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if !item.decisionStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(UIStrings.text(item.decisionStatus)).font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            if let explanationTitle {
                                Text(explanationTitle).font(.callout).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func footer(horizontal: Bool) -> some View {
        let controls = Group {
            Button(UIStrings.text("Bron · p. \(page)"), systemImage: "doc.text.magnifyingglass") {
                showSource(page, sourceQuote)
            }.buttonStyle(FocusQuietActionStyle()).controlSize(.small)
            Button(UIStrings.text("Lees passage"), systemImage: "text.alignleft", action: readPassage)
                .buttonStyle(FocusQuietActionStyle()).controlSize(.small)
            Menu {
                Button(UIStrings.text("Bekijk bredere context"), systemImage: "doc.text", action: broadContext)
            } label: {
                Label(UIStrings.text("Meer"), systemImage: "ellipsis")
            }.focusToolbarMenu().controlSize(.small)
        }
        if horizontal {
            HStack(spacing: 12) { controls }
        } else {
            VStack(alignment: .leading, spacing: 4) { controls }
        }
    }
}
