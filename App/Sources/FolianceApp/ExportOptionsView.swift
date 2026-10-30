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
        return original + "-OVERVIEW"
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
                                                            summaryScope: "Entire document", tables: [], glossary: [],
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
        case .fullDocument: UIStrings.text("Entire document")
        case .mySelection: UIStrings.text("My selection")
        case .committee(let rawValue): "Profile: \(eligibleCommitteePurposes.first { $0.rawValue == rawValue }?.title ?? rawValue)"
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
            case .summary: c.summary ? "Document overview" : nil
            case .chosenPassages: c.chosenPassages ? "Selected passages and sources (\(content.chosenPassages.count))" : nil
            case .pagePoints: c.pagePoints ? (c.committeePurpose.map { "\($0.title): assessed findings (\(points.count))" } ?? (c.selectedPoints ? "My selection (\(points.count))" : "Grouped findings (\(points.count))")) : nil
            case .tables: c.tables ? "Table explanations (\(content.tables.count))" : nil
            case .politics: c.politics ? "Reference comparison" : nil
            case .questions: c.questions ? "Follow-up questions for \(questions.count) findings" : nil
            case .notes: c.notes ? "Your notes and review marks (\(noteCount))" : nil
            case .glossary: c.glossary ? "Abbreviations and definitions (\(content.glossary.count))" : nil
            case .sources: c.sources ? "Source appendix" : nil
            }
        }
    }
    private var scopeDescription: String {
        if let preset { return presetDescription(preset) }
        guard currentPresentation != nil else { return "Preparing export…" }
        let c = effective
        if let purpose = c.committeePurpose {
            let general = [c.summary ? "document overview" : nil,
                           c.tables ? "tables" : nil,
                           c.glossary ? "abbreviations and definitions" : nil].compactMap { $0 }
            let generalNote = general.isEmpty ? "" : " General sections apply to the whole document: " + general.joined(separator: ", ") + "."
            return "Profile: \(purpose.title). The export includes available assessments, safely linked findings, and clearly marked uncertain or unassessed passages. Findings that cannot be linked safely are marked separately.\(generalNote)"
        }
        let included = ExportSectionOrder.confirmation.compactMap { section -> String? in
            switch section {
            case .summary: c.summary ? UIStrings.text("document summary") + " (\(content.summaryScope))" : nil
            case .chosenPassages: c.chosenPassages ? UIStrings.text("passages chosen by you") + " (\(content.chosenPassages.count))" : nil
            case .pagePoints: c.pagePoints ? (c.committeePurpose.map { "\($0.title): assessed findings" } ?? (c.selectedPoints ? "My selection in chosen order" : "All findings")) + " (\(points.count))" : nil
            case .tables: c.tables ? UIStrings.text("tables") + " (\(content.tables.count))" : nil
            case .politics: c.politics ? "Reference comparison" : nil
            case .questions: c.questions ? (c.selectedQuestions ? "Questions for selected findings" : "All available questions") + " (\(questions.count))" : nil
            case .notes: c.notes ? UIStrings.text("notes and review marks") + " (\(noteCount))" : nil
            case .glossary: c.glossary ? UIStrings.text("abbreviations and definitions") + " (\(content.glossary.count))" : nil
            case .sources: c.sources ? UIStrings.text("source excerpts for included findings, analysis, and questions") : nil
            }
        }
        return included.isEmpty ? "No available sections selected." : "Scope: " + included.joined(separator: "; ") + "."
    }
    private func presetTitle(_ preset: ExportPreset) -> String {
        switch preset {
        case .shortOverview: "Brief overview"
        case .selectedWithSources: "My selection with sources"
        case .fullDossier: "Full report"
        }
    }
    private func presetDescription(_ preset: ExportPreset) -> String {
        switch preset {
        case .shortOverview:
            "The document overview and passages you selected. Excludes findings, questions, tables, finding notes, and the source appendix."
        case .selectedWithSources:
            "Your selected findings and their available questions, with source passages, plus the passages you selected. Excludes the document overview, tables, reference comparison, abbreviations, and notes."
        case .fullDossier:
            "All available results within their stated page ranges, including findings, comparison, and questions. Your selected passages, tables, abbreviations, and notes cover the whole document; available source passages are included."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(UIStrings.text("Export PDF")).font(.title2.bold())
            FocusMenuPicker(UIStrings.text("Export scope"), selection: scopeBinding, selectedTitle: scopeTitle) {
                Text(UIStrings.text("Entire document")).tag(ExportScopeChoice.fullDocument)
                Text(UIStrings.text("My selection")).tag(ExportScopeChoice.mySelection)
                ForEach(eligibleCommitteePurposes, id: \.self) { purpose in
                    Text("Profile: \(purpose.title)").tag(ExportScopeChoice.committee(purpose.rawValue))
                }
            }
            HStack {
                ForEach(Array(["Title", "Content", "Review"].enumerated()), id: \.offset) { index, label in
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
                        Picker("Preset", selection: $preset) {
                            Text(UIStrings.text("Custom")).tag(ExportPreset?.none)
                            ForEach(ExportPreset.allCases) { option in Text(presetTitle(option)).tag(Optional(option)) }
                        }.pickerStyle(.radioGroup).onChange(of: preset) { _, value in
                            if let value {
                                choices = value.configuration()
                                customizationExpanded = false
                            } else {
                                // Custom exposes the saved choices without replacing them.
                                customizationExpanded = true
                            }
                        }
                        Text(preset.map(presetDescription) ?? "Choose a preset or customize the export sections.")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(UIStrings.text("This title appears at the top of the exported PDF.")).foregroundStyle(.secondary)
                        TextField(UIStrings.text("Title"), text: $title).textFieldStyle(FocusInputFieldStyle()).tutorialTarget("exportTitle")
                        Toggle(UIStrings.text("Use a different filename"), isOn: $separateName)
                        if separateName { TextField(UIStrings.text("Filename"), text: $fileName).textFieldStyle(FocusInputFieldStyle()) }
                        Text(UIStrings.text("File: ") + ExportConfiguration.fileName(separateName ? fileName : defaultFileName)).font(.caption).foregroundStyle(.secondary)
                    } else if step == 1 {
                        Text(scopeDescription).font(.callout).textSelection(.enabled)
                        if !sections.isEmpty {
                            Text(UIStrings.text("Selected sections")).font(.subheadline.weight(.semibold))
                            ForEach(sections, id: \.self) { Label(UIStrings.text($0), systemImage: "checkmark.circle") }
                        }
                        DisclosureGroup(isExpanded: $customizationExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                        section("Selected passages and full source text", enabled: !requestedContent.chosenPassages.isEmpty, selection: $choices.chosenPassages,
                                detail: choices.committeePurpose == nil ? "The full text you selected, with source pages and your notes. Available without AI analysis." : "Your selected passages and full passages from the profile review that could not be safely linked to a finding.")
                        section("Document overview", enabled: currentPresentation?.requestedContent.summary != nil, selection: $choices.summary, detail: "The general overview of the document.")
                        section(choices.selectedPoints ? "My selection" : "Grouped findings", enabled: !(choices.selectedPoints ? selected : availableInsights).isEmpty, selection: $choices.pagePoints, detail: choices.selectedPoints ? "In your chosen order, with review status and source references." : "Grouped by section or topic, with physical PDF page references.")
                        if choices.pagePoints && !availableInsights.isEmpty && choices.committeePurpose == nil {
                            FocusChoiceTabs(UIStrings.text("Points"), selection: $choices.selectedPoints, options: [
                                .init(value: false, title: UIStrings.text("All points")),
                                .init(value: true, title: UIStrings.text("My selection"), count: selected.count)
                            ])
                                .onChange(of: choices.selectedPoints) { _, _ in preset = nil }
                            if choices.selectedPoints && selected.isEmpty { Text(UIStrings.text("You have not selected any findings yet.")).font(.caption).foregroundStyle(.secondary) }
                        }
                        section("Table explanations", enabled: !(currentPresentation?.requestedContent.tables.isEmpty ?? true), selection: $choices.tables, detail: "Explanations, calculated differences, and source pages for recognized tables.")
                        section("Reference comparison", enabled: currentPresentation?.hasPoliticalInsights == true, selection: $choices.politics, detail: "Comparison findings linked to the reference document, with source references.")
                        section("Questions to resolve", enabled: currentPresentation?.hasQuestions == true, selection: $choices.questions, detail: "Includes questions created for passages.")
                        if choices.questions && currentPresentation?.hasQuestions == true {
                            FocusChoiceTabs(UIStrings.text("Questions"), selection: $choices.selectedQuestions, options: [
                                .init(value: false, title: UIStrings.text("All questions")),
                                .init(value: true, title: UIStrings.text("For my selection"))
                            ])
                                .onChange(of: choices.selectedQuestions) { _, _ in preset = nil }
                            if choices.selectedQuestions && questions.isEmpty { Text(UIStrings.text("Your selection contains no questions to resolve.")).font(.caption).foregroundStyle(.secondary) }
                        }
                        section("Abbreviations and definitions", enabled: !glossary.isEmpty, selection: $choices.glossary, detail: "Includes your definitions and the source of each meaning.")
                        if let glossaryError { Text(glossaryError).font(.caption).foregroundStyle(.orange) }
                        section("Your notes and review marks", enabled: noteCount > 0, selection: $choices.notes, detail: choices.selectedPoints ? "Notes on selected findings." : "Your notes and review marks on findings.")
                        section("Full source passages as an appendix", enabled: effective.pagePoints || effective.politics || effective.questions, selection: $choices.sources, detail: "Only sources for the included findings, comparison, and questions.")
                        }
                        } label: {
                            Text(UIStrings.text("Customize contents")).font(.headline)
                        }
                    } else {
                        Text(title.trimmingCharacters(in: .whitespacesAndNewlines)).font(.title3.bold())
                        Text(ExportConfiguration.fileName(separateName ? fileName : defaultFileName)).foregroundStyle(.secondary)
                        Text(scopeDescription).font(.callout).textSelection(.enabled)
                        ForEach(sections, id: \.self) { Label(UIStrings.text($0), systemImage: "checkmark.circle") }
                        Text("Summary scope: " + content.summaryScope + "\n" + (choices.committeePurpose.map { "Profile: \($0.title)" } ?? currentPresentation?.analysisScope ?? "Entire document")).font(.caption).foregroundStyle(.secondary)
                        Text(UIStrings.text("PDF export preview. The preview is created locally and does not save anything.")).font(.caption).foregroundStyle(.secondary)
                        if previewBusy { HStack { ProgressView().controlSize(.small); Text(UIStrings.text("Creating preview…")) }.frame(maxWidth: .infinity, minHeight: 260) }
                        else if let previewError { Label(UIStrings.text("Preview unavailable: ") + previewError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                        else if let previewData { ExportPDFPreview(data: previewData).frame(minHeight: 300).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    }
                    if step > 0 && sections.isEmpty {
                        Label(UIStrings.text("Choose at least one available section. Save findings with the star before exporting My selection."), systemImage: "info.circle").font(.callout)
                    }
                    if choices.committeePurpose != nil && committeeScopeUnavailable {
                        Label(UIStrings.text("No current, source-validated review is available for this reading profile. Choose another export scope."), systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    if !content.notice.isEmpty { Label(UIStrings.text("Analysis is incomplete. This notice is also included in the export.\n") + content.notice, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }.id(step).transition(stepTransition)
            }.frame(maxHeight: .infinity, alignment: .topLeading).clipped()
            Divider()
            HStack {
                Button(UIStrings.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(UIStrings.text("Back")) { changeStep(by: -1) }.disabled(step == 0).opacity(step == 0 ? 0 : 1).accessibilityHidden(step == 0)
                Button(step == 2 ? "Save as PDF…" : "Next") {
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
                    catch { glossaryError = "Could not load the abbreviation list: " + error.localizedDescription }
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
                .tutorialTarget(title == "Document overview" ? "exportSection" : "section-\(title)")
            Text(enabled ? detail : "Not available for this document or selection.").font(.caption).foregroundStyle(.secondary)
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
            else { previewError = "No document is available." }
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
