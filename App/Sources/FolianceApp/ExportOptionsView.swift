import SwiftUI
import PDFKit

struct ExportOptionsView: View {
    @ObservedObject var workspace: SimpleWorkspace
    @Environment(\.dismiss) private var dismiss
    var onlySelection: Bool
    var tutorialStep: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forward = true
    @State private var step = 0
    private var stepTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .offset(x: forward ? 18 : -18).combined(with: .opacity),
            removal: .offset(x: forward ? -18 : 18).combined(with: .opacity))
    }
    private func changeStep(by delta: Int) {
        forward = delta > 0
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step += delta }
    }
    @State private var title = ""
    @State private var separateName = false
    @State private var fileName = ""
    @State private var choices = ExportConfiguration.read()
    @State private var preset: ExportPreset?
    @State private var customizationExpanded = false
    @State private var validatedCommitteePurposes: Set<String> = []
    @State private var eligibilityGeneration = UUID()
    @State private var eligibilityTask: Task<Void, Never>?
    @State private var glossary: [ExportGlossaryItem] = []
    @State private var glossaryError: String?
    @State private var previewData: Data?
    @State private var previewError: String?
    @State private var previewBusy = false
    @State private var previewTask: Task<Void, Never>?
    @State private var previewGeneration = UUID()
    @State private var glossaryRevision = UUID()
    @State private var capturedSource: ExportPresentationSource?
    @State private var capturedSourceKey: ExportPresentationSourceKey?
    @State private var presentationBase: ExportPresentationBase?
    @State private var presentation: ExportPresentationSnapshot?
    @State private var presentationCache: [ExportPresentationCacheKey: ExportPresentationSnapshot] = [:]
    @State private var presentationGeneration = UUID()
    @State private var presentationBusy = false
    @State private var presentationTask: Task<Void, Never>?
    private var defaultFileName: String {
        let original = (workspace.document?.name as NSString?)?.deletingPathExtension ?? "Foliance"
        return original + "-SAMENVATTING"
    }
    private var selected: [Insight] { currentPresentation?.selectedInsights ?? [] }
    private var currentPresentation: ExportPresentationSnapshot? {
        guard let presentation,
              presentation.sourceKey.documentID == workspace.documentID,
              presentation.sourceKey.revisionToken == workspace.revisionToken,
              presentation.sourceKey.glossaryRevision == glossaryRevision,
              presentation.configurationKey == ExportPresentationConfigurationKey(choices) else { return nil }
        return presentation
    }
    private var presentationConfigurationKey: ExportPresentationConfigurationKey {
        ExportPresentationConfigurationKey(choices)
    }
    private var content: ScopedExportContent {
        currentPresentation?.content ?? ScopedExportContent(insights: [], chosenPassages: [], summary: nil,
                                                            summaryScope: "Hele document", tables: [], glossary: [],
                                                            notice: "", context: "", neutralAnalysis: false)
    }
    private var eligibleCommitteePurposes: [MeetingPurpose] {
        MeetingPurpose.allCases.filter { validatedCommitteePurposes.contains($0.rawValue) }
    }
    private var scopeChoice: ExportScopeChoice {
        if let purpose = choices.committeePurpose { return .committee(purpose.rawValue) }
        return choices.selectedPoints ? .mySelection : .fullDocument
    }
    private var scopeTitle: String {
        switch scopeChoice {
        case .fullDocument: UIStrings.text("Hele document")
        case .mySelection: UIStrings.text("Mijn selectie")
        case .committee(let rawValue): UIStrings.text("Leesprofiel: \(eligibleCommitteePurposes.first { $0.rawValue == rawValue }?.title ?? rawValue)")
        }
    }
    private var committeeScopeUnavailable: Bool {
        choices.committeePurpose.map { !eligibleCommitteePurposes.contains($0) } ?? false
    }
    private var scopeBinding: Binding<ExportScopeChoice> {
        Binding(get: { scopeChoice }, set: { applyScope($0) })
    }
    private var requestedContent: ScopedExportContent { currentPresentation?.requestedContent ?? content }
    private var availableInsights: [Insight] { currentPresentation?.availableInsights ?? [] }
    private var baseInsights: [Insight] { currentPresentation?.baseInsights ?? [] }
    private var points: [Insight] { baseInsights }
    private var questions: [Insight] { currentPresentation?.questions ?? [] }
    private var noteCount: Int { currentPresentation?.noteCount ?? 0 }
    private var effective: ExportConfiguration { currentPresentation?.effective ?? choices }
    private var sections: [String] {
        guard currentPresentation != nil else { return [] }
        let c = effective
        return ExportSectionOrder.confirmation.compactMap { section in
            switch section {
            case .summary: c.summary ? "Documentsamenvatting" : nil
            case .chosenPassages: c.chosenPassages ? "Zelf gekozen en bronpassages (\(content.chosenPassages.count))" : nil
            case .pagePoints: c.pagePoints ? (c.committeePurpose.map { "\($0.title): beoordeelde punten (\(points.count))" } ?? (c.selectedPoints ? "Mijn selectie (\(points.count))" : "Gegroepeerde samenvattingspunten (\(points.count))")) : nil
            case .tables: c.tables ? "Tabellen uitgelegd (\(content.tables.count))" : nil
            case .politics: c.politics ? "Referentievergelijking" : nil
            case .questions: c.questions ? "Vragen om uit te zoeken bij \(questions.count) punten" : nil
            case .notes: c.notes ? "Eigen notities en controlemarkeringen (\(noteCount))" : nil
            case .glossary: c.glossary ? "Afkortingen en definities (\(content.glossary.count))" : nil
            case .sources: c.sources ? "Bronnenbijlage" : nil
            }
        }
    }
    private var scopeDescription: String {
        if let preset { return UIStrings.text(preset.scopeDescription) }
        guard currentPresentation != nil else { return UIStrings.text("Export voorbereiden…") }
        let c = effective
        if let purpose = c.committeePurpose {
            let general = [c.summary ? "documentsamenvatting" : nil,
                           c.tables ? "tabellen" : nil,
                           c.glossary ? "afkortingen en definities" : nil].compactMap { $0 }
            let generalNote = general.isEmpty ? "" : " Algemene onderdelen blijven documentbreed: " + general.joined(separator: ", ") + "."
            return "Leesprofiel: \(purpose.title). De export bevat beschikbare beoordelingen, veilig gekoppelde punten en herkenbaar onzekere of onbeoordeelde passages. Niet veilig gekoppelde punten worden apart gemarkeerd.\(generalNote)"
        }
        let included = ExportSectionOrder.confirmation.compactMap { section -> String? in
            switch section {
            case .summary: c.summary ? UIStrings.text("documentsamenvatting") + " (\(content.summaryScope))" : nil
            case .chosenPassages: c.chosenPassages ? UIStrings.text("zelf gekozen passages") + " (\(content.chosenPassages.count))" : nil
            case .pagePoints: c.pagePoints ? UIStrings.text(c.committeePurpose.map { "Leesprofiel \($0.title): beoordeelde punten" } ?? (c.selectedPoints ? "Mijn selectie in gekozen volgorde" : "alle punten")) + " (\(points.count))" : nil
            case .tables: c.tables ? UIStrings.text("tabellen") + " (\(content.tables.count))" : nil
            case .politics: c.politics ? UIStrings.text("referentievergelijking") : nil
            case .questions: c.questions ? UIStrings.text(c.selectedQuestions ? "vragen bij gemarkeerde punten" : "alle beschikbare vragen") + " (\(questions.count))" : nil
            case .notes: c.notes ? UIStrings.text("notities en controlemarkeringen") + " (\(noteCount))" : nil
            case .glossary: c.glossary ? UIStrings.text("afkortingen en definities") + " (\(content.glossary.count))" : nil
            case .sources: c.sources ? UIStrings.text("bronpassages bij opgenomen punten, duiding en vragen") : nil
            }
        }
        return included.isEmpty ? UIStrings.text("Geen beschikbare onderdelen geselecteerd.") : UIStrings.text("Bereik: ") + included.joined(separator: "; ") + "."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(UIStrings.text("PDF exporteren")).font(.title2.bold())
            FocusMenuPicker(UIStrings.text("Exportbereik"), selection: scopeBinding, selectedTitle: scopeTitle) {
                Text(UIStrings.text("Hele document")).tag(ExportScopeChoice.fullDocument)
                Text(UIStrings.text("Mijn selectie")).tag(ExportScopeChoice.mySelection)
                ForEach(eligibleCommitteePurposes, id: \.self) { purpose in
                    Text(UIStrings.text("Leesprofiel: \(purpose.title)")).tag(ExportScopeChoice.committee(purpose.rawValue))
                }
            }
            HStack {
                ForEach(Array(["Naam en titel", "Inhoud", "Controleren"].enumerated()), id: \.offset) { index, label in
                    Text("\(index + 1). " + UIStrings.text(label)).font(.subheadline.weight(step == index ? .semibold : .regular))
                        .foregroundStyle(step == index ? Color.primary : Color.secondary)
                    if index < 2 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Divider()
            ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if step == 0 {
                        Picker(UIStrings.text("Voorinstelling"), selection: $preset) {
                            Text(UIStrings.text("Aangepast")).tag(ExportPreset?.none)
                            ForEach(ExportPreset.allCases) { option in Text(UIStrings.text(option.title)).tag(Optional(option)) }
                        }.pickerStyle(.radioGroup).onChange(of: preset) { _, value in
                            if let value {
                                choices = value.configuration()
                                customizationExpanded = false
                            } else {
                                // “Aangepast” exposes the saved choices without replacing them.
                                customizationExpanded = true
                            }
                        }
                        Text(UIStrings.text(preset?.scopeDescription ?? "Kies een voorinstelling of stel de exportonderdelen zelf in."))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(UIStrings.text("Deze titel komt bovenaan de export-PDF.")).foregroundStyle(.secondary)
                        TextField(UIStrings.text("Titel"), text: $title).textFieldStyle(FocusInputFieldStyle()).tutorialTarget("exportTitle")
                        Toggle(UIStrings.text("Andere bestandsnaam gebruiken"), isOn: $separateName)
                        if separateName { TextField(UIStrings.text("Bestandsnaam"), text: $fileName).textFieldStyle(FocusInputFieldStyle()) }
                        Text(UIStrings.text("Bestand: ") + ExportConfiguration.fileName(separateName ? fileName : defaultFileName)).font(.caption).foregroundStyle(.secondary)
                    } else if step == 1 {
                        Text(scopeDescription).font(.callout).textSelection(.enabled)
                        if !sections.isEmpty {
                            Text(UIStrings.text("Gekozen onderdelen")).font(.subheadline.weight(.semibold))
                            ForEach(sections, id: \.self) { Label(UIStrings.text($0), systemImage: "checkmark.circle") }
                        }
                        DisclosureGroup(isExpanded: $customizationExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                        section("Zelf gekozen en volledige bronpassages", enabled: !requestedContent.chosenPassages.isEmpty, selection: $choices.chosenPassages,
                                detail: choices.committeePurpose == nil ? "De volledige tekst die je zelf koos, met bronpagina’s en je eigen toelichting. Ook beschikbaar zonder AI-analyse." : "Je gekozen passages en volledige passages van de gerichte beoordeling zonder veilig gekoppeld punt.")
                        section("Documentsamenvatting", enabled: currentPresentation?.requestedContent.summary != nil, selection: $choices.summary, detail: "De algemene samenvatting van het document.")
                        section(choices.selectedPoints ? "Mijn selectie" : "Gegroepeerde samenvattingspunten", enabled: !(choices.selectedPoints ? selected : availableInsights).isEmpty, selection: $choices.pagePoints, detail: choices.selectedPoints ? "In jouw volgorde, met de huidige vergaderstatus en bronverwijzingen." : "Per hoofdstuk of onderwerp, met verwijzingen naar de fysieke PDF-pagina’s.")
                        if choices.pagePoints && !availableInsights.isEmpty && choices.committeePurpose == nil {
                            FocusChoiceTabs(UIStrings.text("Punten"), selection: $choices.selectedPoints, options: [
                                .init(value: false, title: UIStrings.text("Alle punten")),
                                .init(value: true, title: UIStrings.text("Mijn selectie"), count: selected.count)
                            ])
                                .onChange(of: choices.selectedPoints) { _, _ in preset = nil }
                            if choices.selectedPoints && selected.isEmpty { Text(UIStrings.text("Je hebt nog geen punten geselecteerd.")).font(.caption).foregroundStyle(.secondary) }
                        }
                        section("Tabeluitleg", enabled: !(currentPresentation?.requestedContent.tables.isEmpty ?? true), selection: $choices.tables, detail: "Uitleg, berekende verschillen en bronpagina’s van herkende tabellen.")
                        section("Referentievergelijking", enabled: currentPresentation?.hasPoliticalInsights == true, selection: $choices.politics, detail: "Vergelijkingsresultaten met het referentiedocument, met bronverwijzingen.")
                        section("Vragen om uit te zoeken", enabled: currentPresentation?.hasQuestions == true, selection: $choices.questions, detail: "Inclusief vragen die je bij passages hebt laten maken.")
                        if choices.questions && currentPresentation?.hasQuestions == true {
                            FocusChoiceTabs(UIStrings.text("Vragen"), selection: $choices.selectedQuestions, options: [
                                .init(value: false, title: UIStrings.text("Alle vragen")),
                                .init(value: true, title: UIStrings.text("Bij mijn selectie"))
                            ])
                                .onChange(of: choices.selectedQuestions) { _, _ in preset = nil }
                            if choices.selectedQuestions && questions.isEmpty { Text(UIStrings.text("Je selectie bevat geen vragen om uit te zoeken.")).font(.caption).foregroundStyle(.secondary) }
                        }
                        section("Afkortingen en definities", enabled: !glossary.isEmpty, selection: $choices.glossary, detail: "Inclusief eigen definities en herkomst van de betekenis.")
                        if let glossaryError { Text(glossaryError).font(.caption).foregroundStyle(.orange) }
                        section("Eigen notities en controlemarkeringen", enabled: noteCount > 0, selection: $choices.notes, detail: choices.selectedPoints ? "Notities bij gemarkeerde punten." : "Je notities en controlemarkeringen bij punten.")
                        section("Volledige bronpassages als bijlage", enabled: effective.pagePoints || effective.politics || effective.questions, selection: $choices.sources, detail: "Alleen de bronnen bij de gekozen punten, duiding en vragen.")
                        }
                        } label: {
                            Text(UIStrings.text("Inhoud aanpassen")).font(.headline)
                        }
                    } else {
                        Text(title.trimmingCharacters(in: .whitespacesAndNewlines)).font(.title3.bold())
                        Text(ExportConfiguration.fileName(separateName ? fileName : defaultFileName)).foregroundStyle(.secondary)
                        Text(scopeDescription).font(.callout).textSelection(.enabled)
                        ForEach(sections, id: \.self) { Label(UIStrings.text($0), systemImage: "checkmark.circle") }
                        Text(UIStrings.text("Bereik samenvatting: ") + UIStrings.text(content.summaryScope) + "\n" + UIStrings.text(choices.committeePurpose.map { "Leesprofiel \($0.title)" } ?? currentPresentation?.analysisScope ?? "Hele document")).font(.caption).foregroundStyle(.secondary)
                        Text(UIStrings.text("Voorbeeld van de PDF-export. De voorvertoning wordt lokaal gemaakt en slaat niets op.")).font(.caption).foregroundStyle(.secondary)
                        if previewBusy { HStack { ProgressView().controlSize(.small); Text(UIStrings.text("Voorbeeld maken…")) }.frame(maxWidth: .infinity, minHeight: 260) }
                        else if let previewError { Label(UIStrings.text("Voorbeeld niet beschikbaar: ") + previewError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                        else if let previewData { ExportPDFPreview(data: previewData).frame(minHeight: 300).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    }
                    if step > 0 && sections.isEmpty {
                        Label(UIStrings.text("Kies ten minste één beschikbaar onderdeel. Bewaar eerst punten met de ster als je Mijn selectie wilt exporteren."), systemImage: "info.circle").font(.callout)
                    }
                    if choices.committeePurpose != nil && committeeScopeUnavailable {
                        Label(UIStrings.text("Voor dit leesprofiel is geen actuele, bronvalide beoordeling beschikbaar. Kies een andere exportscope."), systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    if !content.notice.isEmpty { Label(UIStrings.text("De analyse is onvolledig. Deze melding wordt ook opgenomen in de export.\n") + content.notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }.id(step).transition(stepTransition)
            }.frame(maxHeight: .infinity, alignment: .topLeading).clipped()
            Divider()
            HStack {
                Button(UIStrings.text("Annuleren")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(UIStrings.text("Terug")) { changeStep(by: -1) }.disabled(step == 0).opacity(step == 0 ? 0 : 1).accessibilityHidden(step == 0)
                Button(UIStrings.text(step == 2 ? "Opslaan als PDF…" : "Volgende")) {
                    if step < 2 { changeStep(by: 1) } else if let currentPresentation {
                        choices.save()
                        let config = currentPresentation.effective, heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = ExportConfiguration.fileName(separateName ? fileName : defaultFileName)
                        dismiss()
                        DispatchQueue.main.async { workspace.export(configuration: config, title: heading, fileName: name, glossary: glossary) }
                    }
                }.buttonStyle(FocusPrimaryButtonStyle()).keyboardShortcut(.defaultAction).tutorialTarget("exportNext")
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (separateName && fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (step > 0 && (sections.isEmpty || currentPresentation == nil || presentationBusy)) || committeeScopeUnavailable)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 620, minHeight: 500, idealHeight: 660)
            .onChange(of: tutorialStep) { _, value in if let value { step = value } }
            .onChange(of: workspace.documentID) { _, _ in
                refreshCommitteeScopeEligibility()
                refreshPresentation()
            }
            .onChange(of: workspace.revisionToken) { _, _ in
                refreshCommitteeScopeEligibility()
                refreshPresentation()
            }
            .onChange(of: presentationConfigurationKey) { _, _ in refreshPresentation() }
            .onChange(of: step) { _, value in
                if value == 2 { makePreview() }
                else { previewTask?.cancel(); previewBusy = false }
            }
            .onDisappear {
                presentationGeneration = UUID()
                eligibilityGeneration = UUID()
                presentationTask?.cancel()
                eligibilityTask?.cancel()
                presentationTask = nil
                eligibilityTask = nil
                previewTask?.cancel()
                previewData = nil
                previewError = nil
                previewBusy = false
                presentationBusy = false
                presentation = nil
                presentationBase = nil
                presentationCache.removeAll(keepingCapacity: false)
                capturedSource = nil
                capturedSourceKey = nil
            }
            .onAppear {
                title = (workspace.document?.name as NSString?)?.deletingPathExtension ?? "Foliance-export"
                fileName = defaultFileName
                if let tutorialStep {
                    step = tutorialStep
                    choices = ExportConfiguration()
                    refreshPresentation()
                    return
                }
                if onlySelection {
                    preset = .selectedWithSources
                    choices = ExportPreset.selectedWithSources.configuration()
                } else if choices.committeePurpose != nil {
                    preset = nil
                } else {
                    preset = ExportPreset.matching(choices)
                }
                customizationExpanded = preset == nil
                if let document = workspace.document {
                    do { glossary = try ExportGlossaryItem.load(document: document) }
                    catch { glossaryError = "De afkortingenlijst kon niet worden geladen: " + error.localizedDescription }
                }
                glossaryRevision = UUID()
                refreshCommitteeScopeEligibility()
                refreshPresentation()
            }
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }
    private func section(_ title: String, enabled: Bool, selection: Binding<Bool>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(UIStrings.text(title), isOn: Binding(get: { enabled && selection.wrappedValue }, set: { selection.wrappedValue = $0; preset = nil })).disabled(!enabled)
                .tutorialTarget(title == "Documentsamenvatting" ? "exportSection" : "section-\(title)")
            Text(UIStrings.text(enabled ? detail : "Niet beschikbaar voor dit document of deze selectie.")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func applyScope(_ scope: ExportScopeChoice) {
        preset = nil
        switch scope {
        case .fullDocument:
            choices = ExportPreset.fullDossier.configuration()
            preset = .fullDossier
        case .mySelection:
            choices = ExportPreset.selectedWithSources.configuration()
        case .committee(let purposeID):
            guard let purpose = MeetingPurpose(rawValue: purposeID) else { return }
            var value = ExportConfiguration()
            value.committeePurpose = purpose
            value.summary = false
            value.tables = false
            value.glossary = false
            value.pagePoints = true
            value.politics = false
            value.questions = false
            value.sources = true
            value.selectedPoints = false
            value.selectedQuestions = false
            value.chosenPassages = true
            value.notes = false
            choices = value
        }
    }

    @MainActor private func refreshPresentation() {
        let generation = UUID()
        presentationGeneration = generation
        presentationTask?.cancel()
        presentationTask = nil
        previewTask?.cancel()
        previewData = nil
        previewError = nil
        let sourceKey = ExportPresentationSourceKey(documentID: workspace.documentID,
                                                   revisionToken: workspace.revisionToken,
                                                   glossaryRevision: glossaryRevision)
        if capturedSourceKey != sourceKey || capturedSource == nil {
            let source = ExportPresentationSource.capture(from: workspace)
            capturedSource = source
            capturedSourceKey = sourceKey
            presentationBase = nil
            presentationCache.removeAll(keepingCapacity: true)
            presentation = nil
        }
        guard let source = capturedSource else {
            presentationBusy = false
            return
        }
        let configurationKey = presentationConfigurationKey
        let key = ExportPresentationCacheKey(source: sourceKey, configuration: configurationKey)
        if let cached = presentationCache[key] {
            presentation = cached
            presentationBusy = false
            if step == 2 { makePreview() }
            return
        }

        presentationBusy = true
        let previousBase = presentationBase
        let currentChoices = choices
        let currentGlossary = glossary
        let currentGlossaryRevision = glossaryRevision
        presentationTask = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let base = try previousBase ?? ExportPresentationBase(source: source, glossaryRevision: currentGlossaryRevision)
                return (base, try base.snapshot(configuration: currentChoices, glossary: currentGlossary))
            }
            do {
                let (base, snapshot) = try await withTaskCancellationHandler(
                    operation: { try await worker.value },
                    onCancel: { worker.cancel() })
                guard !Task.isCancelled, presentationGeneration == generation else { return }
                presentationTask = nil
                guard workspace.documentID == sourceKey.documentID,
                      workspace.revisionToken == sourceKey.revisionToken,
                      glossaryRevision == sourceKey.glossaryRevision,
                      presentationConfigurationKey == configurationKey else {
                    presentationBusy = false
                    return
                }
                presentationBase = base
                presentation = snapshot
                presentationBusy = false
                if presentationCache.count >= 4 { presentationCache.removeAll(keepingCapacity: true) }
                presentationCache[key] = snapshot
                if step == 2 { makePreview() }
            } catch {
                guard !Task.isCancelled, presentationGeneration == generation else { return }
                presentationTask = nil
                presentationBusy = false
            }
        }
    }

    private func refreshCommitteeScopeEligibility() {
        let generation = UUID()
        eligibilityGeneration = generation
        eligibilityTask?.cancel()
        eligibilityTask = nil
        guard let document = workspace.document else { validatedCommitteePurposes = []; return }
        let pages = document.pages
        let reviews = Array(workspace.committeeReviews.values)
        let documentID = workspace.documentID
        let revisionToken = workspace.revisionToken
        eligibilityTask = Task { @MainActor in
            let validator = Task.detached(priority: .userInitiated) { () -> [String]? in
                var purposes: [String] = []
                for review in reviews {
                    guard !Task.isCancelled else { return nil }
                    if review.purpose != .raad,
                       CommitteeAssessmentService.validateSources(review, pages: pages) {
                        guard !Task.isCancelled else { return nil }
                        purposes.append(review.purpose.rawValue)
                    }
                }
                guard !Task.isCancelled else { return nil }
                return purposes
            }
            let result = await withTaskCancellationHandler(
                operation: { await validator.value },
                onCancel: { validator.cancel() })
            guard !Task.isCancelled, let purposes = result,
                  workspace.documentID == documentID,
                  workspace.revisionToken == revisionToken,
                  eligibilityGeneration == generation else { return }
            eligibilityTask = nil
            validatedCommitteePurposes = Set(purposes)
            if let purpose = choices.committeePurpose, !validatedCommitteePurposes.contains(purpose.rawValue) {
                choices.committeePurpose = nil
                choices.selectedPoints = false
                preset = ExportPreset.matching(choices)
            }
        }
    }

    @MainActor private func makePreview() {
        previewTask?.cancel()
        let id = UUID(); previewGeneration = id
        previewData = nil; previewError = nil
        guard let presentation = currentPresentation, let document = presentation.document else {
            previewBusy = false
            if currentPresentation == nil { refreshPresentation() }
            else { previewError = "Geen document beschikbaar." }
            return
        }
        let configuration = presentation.effective
        let content = presentation.content
        let insights = content.insights
        let analyzed = presentation.analyzed
        let focus = content.context
        let neutral = content.neutralAnalysis
        let summary = content.summary
        let summaryScope = content.summaryScope
        let notice = content.notice
        let selectedIDs = presentation.selectedIDs
        let selectedOrder = presentation.selectedOrder
        let selectionStatuses = presentation.selectionStatuses
        let tables = content.tables
        let readings = document.readings
        let annotations = presentation.annotations
        let chosenPassages = content.chosenPassages
        let exportTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let includeSources = configuration.sources
        previewBusy = true
        previewTask = Task { @MainActor in
            defer { if previewGeneration == id { previewBusy = false } }
            do {
                let data = try await BriefingPDF.render(document: document, insights: insights, analyzed: analyzed,
                    focus: focus, neutral: neutral, summary: summary, summaryScope: summaryScope,
                    includeSources: includeSources, notice: notice, configuration: configuration,
                    title: exportTitle, selectedIDs: selectedIDs, selectedOrder: selectedOrder, selectionStatuses: selectionStatuses, glossary: content.glossary, tables: tables,
                    readings: readings, annotations: annotations, chosenPassages: chosenPassages, committeeLabels: content.committeeLabels)
                guard !Task.isCancelled, previewGeneration == id else { return }
                previewData = data
            } catch {
                guard !Task.isCancelled, previewGeneration == id else { return }
                previewError = error.localizedDescription
            }
        }
    }
}

private struct ExportPDFPreview: NSViewRepresentable {
    let data: Data

    final class Coordinator { var renderedData: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(data: data)
        context.coordinator.renderedData = data
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.renderedData != data else { return }
        view.document = PDFDocument(data: data)
        context.coordinator.renderedData = data
    }
}
