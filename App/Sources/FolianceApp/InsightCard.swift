import SwiftUI

struct InsightCard: View {
    let point: Insight
    let neutral: Bool
    let model: String
    let focus: String
    let selected: Bool
    var starred: Bool = false
    var toggleStar: () -> Void = {}
    var annotation = PointAnnotation()
    var annotationChanged: (PointAnnotation) -> Void = { _ in }
    var compact = false
    var committeeLabel: String? = nil
    var committeeReason: String? = nil
    var committeeEvidence: String? = nil
    var committeeContextSources: [Insight.Source] = []
    var embedded = false
    var savedQuestions: [PassageQuestion] = []
    var questionsChanged: ([PassageQuestion]) -> Void = { _ in }
    var tutorialExpanded: Bool? = nil
    let showSource: (Int, String) -> Void
    let explain: () -> Void
    private let uiLanguage = "en"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorContrast
    @State private var summaryExpanded = false
    @State private var detailsExpanded = false
    @State private var questions: [PassageQuestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var request: Task<Void, Never>?
    @State private var showingPassageReader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label(UIStrings.text("PDF-pagina \(point.page)"), systemImage: "doc.text")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if selected { Label(UIStrings.text("In beeld"), systemImage: "smallcircle.filled.circle").font(.caption).foregroundStyle(.secondary) }
                if let committeeLabel {
                    Text(UIStrings.text(committeeLabel)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                if committeeLabel == nil, point.relevanceClass == nil, let contentLabel {
                    Text(contentLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if committeeLabel == nil, let classificationLabel {
                    Text(classificationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(point.relevanceClass == "uncertain" ? .orange : .secondary)
                }
                if let partLabel {
                    Text(partLabel).font(.caption).foregroundStyle(.secondary)
                }
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { toggleStar() } } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? .orange : .secondary)
                        .contentTransition(.opacity)
                }
                    .buttonStyle(.plain).help(UIStrings.text(starred ? "Verwijder uit mijn selectie" : "Bewaar in mijn selectie"))
                    .accessibilityLabel(UIStrings.text(starred ? "Verwijder uit mijn selectie" : "Bewaar in mijn selectie"))
                    .tutorialTarget("star")
            }
            Button {
                showSource(point.page, point.quote)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { summaryExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(point.title).font(.system(size: 21, weight: .semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                        FadingPreviewText(text: point.summary, font: .system(size: 14), color: .secondary,
                                          lineSpacing: 4, collapsedLines: compact ? 1 : (isCommitteeCard ? 6 : 4),
                                          showsExpansionControl: false, language: uiLanguage,
                                          isExpanded: $summaryExpanded)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 8) {
                        Image(systemName: "chevron.down").rotationEffect(.degrees(summaryExpanded ? 180 : 0))
                    }.foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel(point.title + ", " + UIStrings.text("PDF-pagina \(point.page)"))
            .accessibilityValue(point.summary + ", " + UIStrings.text(summaryExpanded ? "Uitgeklapt" : "Ingeklapt"))
            .tutorialTarget("source")

            VStack(alignment: .leading, spacing: 0) {
                Divider().padding(.horizontal, -22)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { sourceActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { sourceActions }
                }.controlSize(.regular).padding(.top, 10)
            }.padding(.top, 10)

            if annotation.isChecked(point) || !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 12) {
                    if annotation.isChecked(point) { Label(UIStrings.text("Door mij gecontroleerd"), systemImage: "checkmark.circle.fill") }
                    if !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Label(UIStrings.text("Notitie"), systemImage: "note.text") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if detailsExpanded {
                VStack(alignment: .leading, spacing: 16) { detailsSections }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.font(.body).lineSpacing(4).padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SPTheme.selection : SPTheme.surface, in: RoundedRectangle(cornerRadius: SPTheme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SPTheme.cardRadius)
                    .strokeBorder(colorContrast == .increased ? Color.primary.opacity(selected ? 0.9 : 0.62) : selected ? SPTheme.accent.opacity(0.8) : SPTheme.border.opacity(0.6), lineWidth: colorContrast == .increased ? (selected ? 2.5 : 1.5) : (selected ? 1.5 : 1))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .disclosureGroupStyle(FullRowDisclosureGroupStyle())
            .shadow(color: .black.opacity(colorContrast == .increased ? 0 : selected ? 0.08 : 0.035), radius: selected ? 10 : 6, x: 0, y: selected ? 3 : 2)
            .onAppear {
                if questions.isEmpty { questions = savedQuestions }
                if let tutorialExpanded {
                    summaryExpanded = tutorialExpanded
                    detailsExpanded = tutorialExpanded
                }
            }
            .onChange(of: tutorialExpanded) { _, value in
                if let value {
                    summaryExpanded = value
                    detailsExpanded = value
                }
            }
            .onDisappear { request?.cancel() }
            .sheet(isPresented: $showingPassageReader) {
                CardPassageReaderView(point: point,
                                      sources: .forCard(point, committeeContextSources: committeeContextSources,
                                                        committeeEvidence: committeeEvidence),
                                      showSource: showSource)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }

    @ViewBuilder private var sourceActions: some View {
        if !(point.passageSources ?? []).isEmpty || !point.quote.isEmpty {
            Button(UIStrings.text("Lees passage", language: uiLanguage), systemImage: "text.alignleft") { showingPassageReader = true }
                .buttonStyle(FocusQuietActionStyle())
                .accessibilityHint("Opens the available passage with search and source links")
        } else if !cardSourceCollection.entries.isEmpty {
            Button(UIStrings.text("Lees passage", language: uiLanguage), systemImage: "text.alignleft") { showingPassageReader = true }
                .buttonStyle(FocusQuietActionStyle())
                .accessibilityHint("Opens the available source information")
        }
        Button(UIStrings.text(detailsExpanded ? "Minder details" : "Details")) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { detailsExpanded.toggle() }
        }.buttonStyle(FocusQuietActionStyle())
    }

    private var isCommitteeCard: Bool { committeeLabel != nil }

    private var cardSourceCollection: CardSourceCollection {
        .forCard(point, committeeContextSources: committeeContextSources, committeeEvidence: committeeEvidence)
    }

    @ViewBuilder private var detailsSections: some View {
        if let committeeReason, !committeeReason.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(UIStrings.text("Waarom is dit relevant voor het gekozen leesdoel?")).font(.caption.bold())
                ReadableText(text: committeeReason).font(.callout).foregroundStyle(.secondary)
            }
        }
        if let generalReason, generalReason != committeeReason {
            VStack(alignment: .leading, spacing: 8) {
                Text(UIStrings.text("Waarom dit punt aandacht krijgt")).font(.caption.bold())
                ReadableText(text: generalReason).font(.callout).foregroundStyle(.secondary)
            }
        }
        if !neutral && !point.relevance.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(UIStrings.text("Vergelijking met referentiedocument")).font(.caption.bold())
                ReadableText(text: point.programSource.map { point.relevance.replacingOccurrences(of: "\n\n" + $0, with: "") } ?? point.relevance)
            }
        }
        if !neutral && !point.question.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(UIStrings.text("Vraag om uit te zoeken")).font(.caption.bold())
                Text(point.question).textSelection(.enabled)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Mijn controle en notitie")).font(.headline)
            Toggle(UIStrings.text("Door mij gecontroleerd aan de bron"), isOn: Binding(get: { annotation.isChecked(point) }, set: { checked in
                var updated = annotation; updated.checkedSignature = checked ? PointAnnotation.signature(point) : nil; annotationChanged(updated)
            })).toggleStyle(.checkbox)
            TextField(UIStrings.text("Eigen notitie"), text: Binding(get: { annotation.note }, set: { text in
                var updated = annotation; updated.note = text; annotationChanged(updated)
            }), axis: .vertical).textFieldStyle(FocusInputFieldStyle()).lineLimit(2...6)
            Text(UIStrings.text("Je controlemarkering is een eigen beoordeling; gewijzigde AI-tekst moet opnieuw worden gecontroleerd."))
                .font(.caption).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.text("Vragen")).font(.headline)
            Button(UIStrings.text("Stel een vraag"), systemImage: "bubble.left") { explain() }
                .buttonStyle(FocusQuietActionStyle()).tutorialTarget("ask")
            if questions.count < 5 {
                Button(UIStrings.text(questionActionTitle), systemImage: "questionmark.bubble") { generate() }
                    .buttonStyle(FocusQuietActionStyle()).disabled(loading)
            }
            if loading { HStack { ProgressView().controlSize(.small); Button(UIStrings.text("Stop")) { request?.cancel() } } }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(question.question)").font(.callout.bold()).textSelection(.enabled)
                    Button { showSource(point.page, question.quote) } label: {
                        Text("‘\(question.quote)’").font(.callout).multilineTextAlignment(.leading)
                    }.buttonStyle(FocusQuietActionStyle())
                }
            }
            if !loading && questions.count < 5 {
                Text(UIStrings.text("Alleen vragen met gecontroleerde broncitaten worden getoond.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var generalReason: String? {
        guard let reason = point.relevanceReason, !reason.isEmpty else { return nil }
        return reason
    }

    private var questionActionTitle: String {
        if questions.isEmpty { return error == nil ? "Maak vragen om uit te zoeken" : "Probeer opnieuw" }
        return "Vul ontbrekende vragen aan"
    }

    /// Only show a small category when the point's own wording contains a clear signal.
    private var classificationLabel: String? {
        switch point.relevanceClass {
        case "main": UIStrings.text("Hoofdpunt", language: uiLanguage)
        case "background": UIStrings.text("Achtergrond", language: uiLanguage)
        case "uncertain": UIStrings.text("Onzeker", language: uiLanguage)
        default: nil
        }
    }

    private var partLabel: String? {
        guard let index = point.passagePartIndex, let count = point.passagePartCount, count > 1 else { return nil }
        return UIStrings.text("Alineadeel \(index) van \(count)", language: uiLanguage)
    }

    private var contentLabel: String? {
        let text = (point.title + " " + point.summary).lowercased()
        if matches(#"\b(mits|tenzij|indien|voorwaarde)\b|op\s+voorwaarde\s+dat|alleen\s+als"#, in: text) {
            return "Condition"
        }
        if !matches(#"\bgeen\s+voorstel\b|\bniet\s+voorgesteld\b"#, in: text),
           matches(#"\bvoorstel\b|\bstelt\s+voor\b|\bvoorgesteld\b"#, in: text) {
            return UIStrings.text("Voorstel", language: uiLanguage)
        }
        if !matches(#"\b(?:geen|niet)\b"#, in: text),
           matches(#"\bheeft\s+besloten\b|\bis\s+vastgesteld\b"#, in: text) {
            return "Decision"
        }
        if text.contains("€") || matches(#"\b\d[\d.,]*\s*(?:miljoen|miljard|duizend)?\s*euro\b"#, in: text) {
            return UIStrings.text("Bedragen", language: uiLanguage)
        }
        return nil
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private func generate() {
        guard !loading else { return }
        loading = true; error = nil
        request = Task { @MainActor in
            defer { loading = false }
            do {
                let result = try await PassageQuestions.generate(passage: point.quote, model: model, focus: focus, existing: questions) { confirmed in
                    await MainActor.run { questions = confirmed; questionsChanged(confirmed) }
                }
                try Task.checkCancellation()
                questions = result; questionsChanged(result)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
