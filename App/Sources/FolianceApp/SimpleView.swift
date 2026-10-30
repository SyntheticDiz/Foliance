import SwiftUI
import AppKit
import FolianceCore

private enum WorkbenchSection: String, CaseIterable {
    case overview = "Overzicht", points = "Punten", tables = "Tabellen", selection = "Mijn selectie", search = "Zoeken"
}

private enum PointsViewMode: String {
    case featured, all, mine
}

private enum PendingWorkspaceAction {
    case choosePDF
    case importPDF([URL])
    case openWorkspace
    case openWorkspaceURL(URL)
    case openRecentWorkspace(RecentWorkspaceDocuments.Entry)
    case relocateRecentWorkspace(RecentWorkspaceDocuments.Entry)
    case returnToImport
    case closeWindow
    case terminate
}

enum TerminationScheduler {
    @MainActor
    static func enqueue(_ action: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated { action() }
        }
    }
}

struct SimpleView: View {
    private let uiLanguage = "en"
    @StateObject private var workspace = SimpleWorkspace()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var pdfControls = PDFControls()
    @StateObject private var selectionSummary = SelectionSummary()
    @StateObject private var closeBridge = WorkspaceWindowCloseBridge()
    @ObservedObject private var recentDocuments = RecentWorkspaceDocuments.shared
    @AppStorage("showPDFPane") private var showPDFPane = true
    @AppStorage("compareProgram") private var compareProgram = false
    private var sourceHighlightsCard: some View {
        SourceHighlightsView(workspace: workspace, showSource: { page, quote in
            showPDFPane = true
            if quote.isEmpty { pdfControls.resetHighlight(); workspace.showPage(page) }
            else { pdfControls.pin(.init(id: "fact-\(page)-\(quote)", page: page, quote: quote)) }
        }, sourceBound: workspace.usesSourceBoundHighlights)
    }

    @State private var section: WorkbenchSection = .overview
    @State private var savedViewState = WorkspaceViewState()
    @State private var showingAnalysisOverview = false
    @State private var pendingScrollID: String?
    @State private var pendingCommitteePassageID: String?
    @AppStorage("chatGPTModel") private var chatGPTModel = "gpt-6.1-sol"
    @AppStorage("chatGPTReasoning") private var chatGPTEffort = "high"
    @AppStorage("chatGPTSubagentModel") private var chatGPTSubagentModel = "gpt-6-luna"
    @AppStorage("chatGPTSubagentReasoning") private var chatGPTSubagentEffort = "high"
    @State private var appleUnavailable: String?
    @State private var importing = false
    @State private var targeted = false
    @State private var search = ""
    @State private var searchFocusRequest = 0
    @State private var searchBase: [SearchRecord] = []
    @State private var searchIndexing = false
    @State private var glossarySearch = ""
    @State private var pointsMode: PointsViewMode = .featured
    @State private var importPurpose: MeetingPurpose = .raad
    @State private var pendingImportPurpose: MeetingPurpose = .raad
    @State private var showingImportPurpose = false
    @State private var committeeShowAll: [String: Bool] = [:]
    @State private var committeeOpenCategories: [String: Set<String>] = [:]
    @State private var openTableIDs: Set<String> = []
    @State private var lastTableID: String?
    @State private var pendingTableID: String?
    @State private var showingExport = false
    @State private var showingSettings = false
    @State private var showingTutorial = false
    @State private var showingChartArea = false
    @State private var selectingChart = false
    @State private var chartDragStart: CGPoint?
    @State private var chartDragEnd: CGPoint?
    @State private var selectedChart: SelectedChart?
    @State private var selectedChartExplanation: ChartExplanation?
    @State private var showingSavedExtras = false
    @State private var pointsExpanded = false
    @State private var showingFocus = false
    @State private var showingGlossary = false
    @State private var showingLayout = false
    @State private var openGroups: Set<String> = []
    @State private var chatPresentation: ChatPresentation?
    @State private var chatQuestion = ""
    @State private var showingAnalysisOptions = false
    @AppStorage("compactReading") private var compactReading = false
    @State private var pointPageFilter = ""
    @State private var reviewFilter = 0
    @State private var showingCoverage = false
    @State private var readingAgendaExpanded = false
    @State private var pendingWorkspaceAction: PendingWorkspaceAction?
    @State private var showingComparison = false
    @State private var pendingActionDialogPresented = false
    @State private var pendingActionSaveInFlight = false
    @State private var restoredNavigationID: UUID?
    @State private var pendingComparisonSource: (id: String, page: Int, quote: String)?
    private var viewState: WorkspaceViewState {
        WorkspaceViewState(section: section.rawValue, pointsMode: pointsMode.rawValue, openGroups: openGroups,
                           pointPageFilter: pointPageFilter, reviewFilter: reviewFilter, pdfVisible: showPDFPane,
                           pointsExpanded: pointsExpanded, compactReading: compactReading, search: search, committeeShowAll: committeeShowAll.isEmpty ? nil : committeeShowAll,
                           committeeOpenCategories: committeeOpenCategories, openTableIDs: openTableIDs, lastTableID: lastTableID)
    }
    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { workspace.error != nil && !workspace.processingPresented }, set: setErrorAlertVisible)
    }
    private var pendingActionDialogBinding: Binding<Bool> {
        Binding(get: { pendingActionDialogPresented }, set: setPendingActionDialogPresented)
    }
    private func setErrorAlertVisible(_ visible: Bool) { if !visible { workspace.error = nil } }
    private func setPendingActionDialogPresented(_ visible: Bool) {
        pendingActionDialogPresented = visible
        if !visible && !pendingActionSaveInFlight && pendingWorkspaceAction != nil { cancelPendingAction() }
    }
    private func matchesPoint(_ point: Insight, pages: Set<Int>?) -> Bool {
        PointDisplayFilter.matches(point, pages: pages, reviewFilter: reviewFilter, annotation: workspace.annotation(for: point))
    }
    private var focus: AnalysisFocus { .init(topics: workspace.focus) }
    private var overviewAnalysisIncomplete: Bool { workspace.baseAnalysisIncomplete }
    @AppStorage("appearance") private var appearance = "system"

    var body: some View { alertContent }

    private var rootContent: some View {
        ZStack {
            if workspace.processingPresented {
                ProcessingSplashView(workspace: workspace, onReturnToImport: { requestWorkspaceAction(.returnToImport) }).transition(.opacity)
            } else {
            VStack(spacing: 0) {
            if workspace.showsWelcome {
                ProcessingModePicker(compareProgram: $compareProgram, disabled: workspace.busy)
                    .padding(.horizontal, 24).padding(.top, 12)
            }
            if compareProgram && workspace.programIdentity == "none" {
                Text(UIStrings.text("Add a reference document in Settings to compare documents."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if workspace.showsWelcome { welcome }
            else { workbench }
            }.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: workspace.processingPresented)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: workspace.showsWelcome)
        .background(SPTheme.background)
        .navigationTitle(workspace.processingPresented ? "Foliance" : workspace.showsWelcome ? "Foliance" : workspace.document?.name ?? "Foliance")
        .toolbar { mainToolbar }
        .toolbarBackground(SPTheme.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .background(WorkspaceWindowCloseGuard(bridge: closeBridge).frame(width: 0, height: 0))
    }

    private var presentedContent: some View {
        rootContent
        .sheet(isPresented: $showingFocus) { FocusEditor(initial: workspace.focus) { updated in workspace.applyFocus(updated) } }
        .sheet(isPresented: $showingLayout) { LayoutCorrectionView(workspace: workspace, model: AIConfiguration.selectedModel, compareProgram: compareProgram, visiblePage: pdfControls.page) }
        .sheet(isPresented: $showingGlossary, onDismiss: { Task { await refreshSearchBase() } }) {
            if let document = workspace.document { GlossaryView(document: document, initialSearch: glossarySearch) { showPDFPage($0) } }
        }
        .sheet(isPresented: $showingSettings, onDismiss: handleSettingsDismiss) { AppSettingsView() }
        .sheet(isPresented: $showingTutorial) { TutorialView() }
        .sheet(isPresented: $showingChartArea) {
            ChartAreaView(page: pdfControls.page) { region in
                guard let view = pdfControls.view, let document = view.document, let page = document.page(at: pdfControls.page - 1) else { return }
                let bounds = page.bounds(for: .cropBox)
                let area = CGRect(x: bounds.minX + region.minX * bounds.width, y: bounds.minY + region.minY * bounds.height,
                                  width: region.width * bounds.width, height: region.height * bounds.height)
                if let image = ChartImageRenderer.render(page: page, region: area) {
                    let selected = SelectedChart(page: pdfControls.page, image: image)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        selectedChartExplanation = nil
                        selectedChart = selected
                    }
                } else { workspace.error = UIStrings.text("The chart area could not be read.") }
            }
        }
        .sheet(item: $selectedChart) { selected in
            let expectedDocumentID = workspace.documentID
            ChartAnalysisView(selected: selected, initialExplanation: selectedChartExplanation) { explanation in
                workspace.rememberChart(selected, explanation: explanation, expectedDocumentID: expectedDocumentID)
            }
        }
        .sheet(isPresented: $showingSavedExtras) {
            SavedWorkspaceExtrasView(threads: workspace.savedChatThreads, charts: workspace.savedChartAnalyses, summaries: workspace.savedSelectionSummaries,
                openSummary: { saved in showingSavedExtras = false; openSavedSelectionSummary(saved) },
                openThread: { thread in showingSavedExtras = false; openSavedChat(thread) },
                openChart: { chart in
                    showingSavedExtras = false
                    let expectedDocumentID = workspace.documentID
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard workspace.documentID == expectedDocumentID else { return }
                        if let image = NSImage(data: chart.imagePNG)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                            selectedChartExplanation = chart.explanation
                            selectedChart = SelectedChart(page: chart.page, image: image)
                        } else { workspace.error = "The saved chart image could not be opened." }
                    }
                })
        }
        .sheet(isPresented: $showingExport) { ExportOptionsView(workspace: workspace, onlySelection: section == .selection) }
        .sheet(isPresented: $showingComparison, onDismiss: openPendingComparisonSource) {
            InsightComparisonSheet(points: workspace.organizedInsights) { point, page, quote in
                pendingComparisonSource = (point.id, page, quote)
                showingComparison = false
            }
        }
        .sheet(isPresented: $showingImportPurpose) {
            VStack(alignment: .leading, spacing: 20) {
                Text(UIStrings.text("Prepare a new PDF")).font(.title2.bold())
                importPurposePicker
                Text(UIStrings.text("Foliance reads the PDF before starting analysis. A selected profile may add a focused review."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(UIStrings.text("Cancel")) { showingImportPurpose = false }
                    Spacer()
                    Button(UIStrings.text("Choose PDF…")) {
                        pendingImportPurpose = importPurpose
                        showingImportPurpose = false
                        Task { @MainActor in await Task.yield(); importing = true }
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(28).frame(width: 480).buttonStyle(FocusSecondaryButtonStyle())
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): requestWorkspaceAction(.importPDF([url]))
            case .failure(let error): if !ImportFailure.isCancellation(error) { workspace.error = error.localizedDescription }
            }
        }
        .focusedSceneValue(\.folianceWorkspaceFileMenuActions,
                           isWorkspaceFileModalPresented ? nil : workspaceFileMenuActions)
    }

    private var stateObservedContent: some View {
        presentedContent
        .onChange(of: workspace.documentID) { _, _ in
            committeeShowAll = [:]; committeeOpenCategories = [:]; openTableIDs = []; lastTableID = nil; pendingTableID = nil; pendingCommitteePassageID = nil
            showingAnalysisOverview = false; search = ""; pointPageFilter = ""; reviewFilter = 0; searchBase = []; section = .overview; pointsMode = .featured; openGroups = []; showingCoverage = false; chatPresentation = nil; pdfControls.resetHighlight()
            selectionSummary.close(); selectingChart = false; chartDragStart = nil; chartDragEnd = nil; selectedChart = nil
            if let restored = workspace.consumeRestoredViewState() {
                section = WorkbenchSection(rawValue: restored.section) ?? .overview
                pointsMode = PointsViewMode(rawValue: restored.pointsMode) ?? .featured
                committeeShowAll = restored.committeeShowAll ?? [:]
                committeeOpenCategories = restored.committeeOpenCategories ?? [:]
                openTableIDs = restored.openTableIDs ?? []; lastTableID = restored.lastTableID
                openGroups = restored.openGroups; pointPageFilter = restored.pointPageFilter
                reviewFilter = min(2, max(0, restored.reviewFilter)); showPDFPane = restored.pdfVisible
                pointsExpanded = restored.pointsExpanded; compactReading = restored.compactReading; search = restored.search
                restoredNavigationID = workspace.navigationID
            } else if workspace.meetingPurpose != .raad {
                section = .points; pointsExpanded = true
            }
            savedViewState = viewState
            workspace.updateTerminationSnapshot(readingPage: workspace.page, viewState: viewState)
        }
        .onChange(of: section) { _, _ in trackViewStateChange() }
        .onChange(of: pointsMode) { _, _ in trackViewStateChange() }
        .onChange(of: committeeShowAll) { _, _ in trackViewStateChange() }
        .onChange(of: committeeOpenCategories) { _, _ in trackViewStateChange() }
        .onChange(of: openTableIDs) { old, updated in
            if let added = updated.subtracting(old).first { lastTableID = added }
            else if let last = lastTableID, !updated.contains(last) { lastTableID = updated.sorted().first }
            trackViewStateChange()
        }
        .onChange(of: openGroups) { _, _ in trackViewStateChange() }
        .onChange(of: pointPageFilter) { _, _ in trackViewStateChange() }
        .onChange(of: reviewFilter) { _, _ in trackViewStateChange() }
        .onChange(of: showPDFPane) { _, _ in trackViewStateChange() }
        .onChange(of: pointsExpanded) { _, _ in trackViewStateChange() }
        .onChange(of: compactReading) { _, _ in trackViewStateChange() }
        .onChange(of: search) { _, _ in trackViewStateChange() }
        .onChange(of: pdfControls.page) { _, page in
            guard workspace.document != nil, page != workspace.page else { return }
            workspace.page = page
            workspace.updateTerminationSnapshot(readingPage: page, viewState: viewState)
            workspace.markDirty()
        }
    }

    private var eventObservedContent: some View {
        stateObservedContent
        .onAppear { handleAppear() }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            if url.pathExtension.lowercased() == "foliance" { requestWorkspaceAction(.openWorkspaceURL(url)) }
            else if url.pathExtension.lowercased() == "pdf" { requestWorkspaceAction(.importPDF([url])) }
        }
        .onReceive(NotificationCenter.default.publisher(for: SavedWork.failure).receive(on: RunLoop.main)) { notice in workspace.error = notice.object as? String }
        .onReceive(NotificationCenter.default.publisher(for: .folianceOpenPDF)) { _ in
            requestWorkspaceAction(.choosePDF)
        }
        .onReceive(NotificationCenter.default.publisher(for: .folianceRequestTermination)) { notice in
            handleTerminationRequest(notice.object)
        }
        .onReceive(NotificationCenter.default.publisher(for: .folianceRequestWindowClose)) { notice in
            handleWindowCloseRequest(notice.object)
        }
        .onReceive(NotificationCenter.default.publisher(for: .folianceFind)) { _ in
            handleFindRequest()
        }
        .task(id: workspace.documentID) { await refreshSearchBase() }
    }

    private var alertContent: some View {
        eventObservedContent
        .alert(UIStrings.text("Notice"), isPresented: errorAlertBinding) {
            Button(UIStrings.text("OK")) { workspace.error = nil }
        } message: { Text(UIStrings.text(workspace.error ?? "")) }
        .confirmationDialog(UIStrings.text("Unsaved changes"), isPresented: pendingActionDialogBinding, titleVisibility: .visible) {
            Button(UIStrings.text("Save and continue")) { saveThenContinue() }
                .disabled(workspace.busy || workspace.committeeReviewBusy || workspace.exporting || workspace.document == nil)
            Button(UIStrings.text("Discard changes"), role: .destructive) { performPendingAction() }
            Button(UIStrings.text("Cancel"), role: .cancel) { cancelPendingAction() }
        } message: {
            Text(UIStrings.text("This action will replace or close the current workspace."))
        }
    }

    private var importPurposePicker: some View {
        FocusMenuPicker(UIStrings.text("Prepare for"), selection: $importPurpose,
                        selectedTitle: UIStrings.text(importPurpose.title)) {
            ForEach(MeetingPurpose.allCases, id: \.self) { purpose in
                Text(UIStrings.text(purpose.title)).tag(purpose)
            }
        }.frame(maxWidth: 340)
    }

    private var welcome: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 20) {
            Image(nsImage: Bundle.main.url(forResource: "Foliance", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSApplication.shared.applicationIconImage).resizable().scaledToFit().frame(width: 64, height: 64)
            Text(UIStrings.text("Welcome to Foliance")).font(.system(size: 30, weight: .semibold))
            Text(UIStrings.text("A clear workspace for reading and reviewing PDFs.")).font(.title3).foregroundStyle(.secondary)
            Text(UIStrings.text(AIConfiguration.label(AIConfiguration.selectedModel)))
                .font(.caption).foregroundStyle(.secondary)
            if let reason = appleUnavailable {
                Label(UIStrings.text(reason), systemImage: "info.circle").font(.callout)
                Text(UIStrings.text("You can open, read and search the PDF locally.")).font(.caption).foregroundStyle(.secondary)
            }
            importPurposePicker
            PDFImportCard(busy: workspace.busy, targeted: targeted,
                          addPDF: { requestWorkspaceAction(.choosePDF) })
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: targeted)
                .dropDestination(for: URL.self) { urls, _ in pendingImportPurpose = importPurpose; requestWorkspaceAction(.importPDF(urls)); return true } isTargeted: { targeted = $0 }
            Button(UIStrings.text("Open workspace…"), systemImage: "folder") { requestWorkspaceAction(.openWorkspace) }
                .buttonStyle(QuietActionStyle()).disabled(workspace.busy || workspace.committeeReviewBusy || workspace.exporting)
            if !recentDocuments.entries.isEmpty { recentWorkspaces }
            if workspace.busy { Text(UIStrings.text("Stop processing…")).font(.callout).foregroundStyle(.secondary) }
            if workspace.document != nil {
                Button(UIStrings.text("Return to current PDF")) { workspace.showsWelcome = false }.disabled(workspace.busy)
            }
        }.frame(maxWidth: 540).padding(32).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
        }
        }
    }

    private var recentWorkspaces: some View {
        RecentWorkspacesList(entries: recentDocuments.entries,
                             disabled: workspace.busy || workspace.committeeReviewBusy || workspace.exporting,
                             open: { requestWorkspaceAction(.openRecentWorkspace($0)) },
                             removeFromList: { try? recentDocuments.remove($0) },
                             relocate: { requestWorkspaceAction(.relocateRecentWorkspace($0)) })
    }

    @ToolbarContentBuilder private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !workspace.processingPresented {
            if !workspace.showsWelcome {
                Button(UIStrings.text("New PDF"), systemImage: "plus") { requestWorkspaceAction(.choosePDF) }
                    .help(UIStrings.text("Open a new PDF")).disabled(workspace.busy || workspace.committeeReviewBusy || workspace.exporting)
                    .buttonStyle(FocusToolbarActionStyle())
                Button(UIStrings.text("Analysis options"), systemImage: "slider.horizontal.3") {
                    chatPresentation = nil; section = .overview; showingAnalysisOptions.toggle()
                    if showingAnalysisOptions { pendingScrollID = "summary-root" }
                }.buttonStyle(FocusToolbarActionStyle())
                Button(UIStrings.text("Document chat"), systemImage: "bubble.left.and.bubble.right") { openChat(pages: Array(1...(workspace.document?.pages.count ?? 1)), wholeDocument: true) }
                    .disabled(workspace.busy).buttonStyle(FocusToolbarActionStyle())
                Button(section == .selection ? "Export My selection" : "Export", systemImage: "square.and.arrow.up") { showingExport = true }
                    .disabled(workspace.busy || workspace.committeeReviewBusy || workspace.exporting || workspace.document == nil).help(UIStrings.text("Choose which sections to export"))
                    .buttonStyle(FocusToolbarActionStyle())
            }
            Menu {
                Button(UIStrings.text("Open workspace…")) { requestWorkspaceAction(.openWorkspace) }
                Button(UIStrings.text("Save workspace…")) { saveWorkspace() }.disabled(workspace.document == nil)
            } label: {
                let dirty = workspace.document != nil && workspace.hasUnsavedChanges
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(UIStrings.text("Work document"))
                    if dirty {
                        Circle().fill(SPTheme.accent).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                }.foregroundStyle(Color.primary)
            }
                .accessibilityLabel(UIStrings.text("Work document"))
                .accessibilityValue(workspace.document != nil && workspace.hasUnsavedChanges ? "Unsaved changes" : "No unsaved changes")
                .help(UIStrings.text("Open or save a work document. ⌘⇧O opens; ⌘S saves."))
                .disabled(workspace.busy || workspace.committeeReviewBusy || workspace.exporting)
                .focusToolbarMenu()
            Menu {
                if !workspace.showsWelcome {
                    Button(UIStrings.text("Compare findings"), systemImage: "rectangle.split.2x1") { showingComparison = true }
                        .disabled(workspace.busy || workspace.organizedInsights.count < 2)
                }
                Button(UIStrings.text("Tour"), systemImage: "questionmark.circle") { showingTutorial = true }
                    .help(UIStrings.text("View the tour"))
            } label: {
                Label(UIStrings.text("Tools"), systemImage: "ellipsis.circle").foregroundStyle(Color.primary)
            }
            .accessibilityLabel(UIStrings.text("Tools"))
            .focusToolbarMenu()
            Button(UIStrings.text("Settings"), systemImage: "gearshape") { showingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
                .buttonStyle(FocusToolbarActionStyle())
            }
        }.sharedBackgroundVisibility(.hidden)
    }

    private func workbenchControls(compact: Bool) -> some View {
        HStack(spacing: 12) {
            ProcessingModePicker(compareProgram: $compareProgram, disabled: workspace.busy)
                .fixedSize(horizontal: true, vertical: false)
            analysisControls
            Spacer(minLength: 12)
            if compact {
                readingControls.labelStyle(.iconOnly)
            } else {
                readingControls.labelStyle(.titleAndIcon)
            }
        }
    }

    private var analysisControls: some View {
        AnalysisControlRow(workspace: workspace, disabled: selectionSummary.busy || (workspace.committeeReviewBusy && !workspace.importCommitteeReviewActive) || workspace.exporting, stopTitle: "Stop and keep results", showsCompletionSummary: false) {
                    if workspace.busy { workspace.cancelAnalysis() }
                    else if workspace.canResume { workspace.resumeMissing() }
                    else { workspace.analyze(model: AIConfiguration.selectedModel, context: focus.prompt, selection: workspace.requestedSelection, compareProgram: compareProgram) }
                }
    }

    private var readingControls: some View {
        HStack(spacing: 6) {
            Button(UIStrings.text("Analysis status"), systemImage: "list.bullet.clipboard") { showingAnalysisOverview.toggle() }
                    .help(UIStrings.text("Show or hide analysis progress and recovery actions"))
                .accessibilityValue(showingAnalysisOverview ? "Expanded" : "Collapsed")
                Button(showPDFPane ? "Hide PDF panel" : "Show PDF panel", systemImage: "sidebar.right") { if showPDFPane { workspace.page = pdfControls.page }; showPDFPane.toggle() }
                    .help(showPDFPane ? "Hide PDF panel" : "Show PDF panel")
                Menu {
                    Button(UIStrings.text("Abbreviations"), systemImage: "character.book.closed") { glossarySearch = ""; showingGlossary = true }
                    if !workspace.savedChatThreads.isEmpty || !workspace.savedChartAnalyses.isEmpty || !workspace.savedSelectionSummaries.isEmpty {
                        Button(UIStrings.text("Saved answers"), systemImage: "clock.arrow.circlepath") { showingSavedExtras = true }
                    }
                    Button(UIStrings.text("Text layout"), systemImage: "rectangle.split.2x1") { showingLayout = true }.disabled(workspace.busy)
                } label: { Label(UIStrings.text("Reading options"), systemImage: "ellipsis").foregroundStyle(Color.primary) }
                    .help(UIStrings.text("Abbreviations and text layout"))
                    .lineLimit(1)
                    .focusToolbarMenu()
        }
        .buttonStyle(FocusToolbarActionStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workbench: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                workbenchControls(compact: false)
                workbenchControls(compact: true)
            }
            .controlSize(.regular)
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 2)
            if showingAnalysisOptions && compareProgram { Button(UIStrings.text("Edit focus"), systemImage: "slider.horizontal.3") { showingFocus = true }.disabled(workspace.busy).padding(.horizontal, 24) }
            if let document = workspace.document {
                WorkspaceStatusBanner(workspace: workspace, showingAnalysisOverview: $showingAnalysisOverview,
                    showPage: { showPDFPage($0) },
                    showSource: { page, quote in
                        showPDFPane = true
                        pdfControls.pin(.init(id: "committee-status-\(page)-\(quote.hashValue)", page: page, quote: quote))
                    },
                    showTable: { openTable($0) }).padding(.horizontal, 24)
                HStack(spacing: 8) {
                    ForEach(WorkbenchSection.allCases, id: \.self) { destination in
                        Button {
                            chatPresentation = nil
                            section = destination
                            if destination == .selection { pointsMode = .mine; pointsExpanded = true }
                            if destination == .points { if pointsMode == .mine { pointsMode = .featured }; pointsExpanded = true; if let first = workspace.featuredInsightGroups.first { openGroups.insert(first.id) } }
                            if destination == .search { searchFocusRequest += 1 }
                            if destination == .tables { pendingTableID = lastTableID }
                        } label: {
                            Text(UIStrings.text(workbenchSectionTitle(destination)) + (destination == .selection ? " (\(workspace.selectedInsightGroups.reduce(0) { $0 + $1.points.count } + workspace.chosenPassages.count))" : destination == .tables ? " (\(workspace.tables.count))" : ""))
                                .font(.callout.weight(section == destination ? .semibold : .regular)).padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(section == destination ? Color.primary : Color.secondary)
                                .background(section == destination ? SPTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    if section == destination {
                                        RoundedRectangle(cornerRadius: 9).strokeBorder(SPTheme.border.opacity(0.55), lineWidth: 1).allowsHitTesting(false)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if section == destination { Capsule().fill(SPTheme.accent).frame(height: 2).padding(.horizontal, 12).padding(.bottom, 1).accessibilityHidden(true) }
                                }
                        }.buttonStyle(.plain).accessibilityAddTraits(section == destination ? .isSelected : [])
                            .accessibilityValue(section == destination ? UIStrings.text("Selected") : UIStrings.text("Not selected"))
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 24).padding(.bottom, 6)
                HSplitView {
                    VStack(spacing: 12) {
                    SelectionSummaryCard(session: selectionSummary)
                    ZStack {
                    ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            if section == .search {
                            UnifiedSearchView(query: $search, focusRequest: searchFocusRequest,
                                              records: workspace.analysisSearchRecords + searchBase,
                                              indexing: searchIndexing, open: openSearchResult)
                            }
                            if section == .overview {
                            if !workspace.savedChatThreads.isEmpty || !workspace.savedChartAnalyses.isEmpty || !workspace.savedSelectionSummaries.isEmpty {
                                Button(UIStrings.text("Saved answers"), systemImage: "clock.arrow.circlepath") { showingSavedExtras = true }
                                    .buttonStyle(FocusSecondaryButtonStyle()).padding(.horizontal, 24)
                            }
                            SummaryCard(workspace: workspace, model: AIConfiguration.selectedModel, showsOptions: showingAnalysisOptions,
                                        chat: { openChat(pages: $0, wholeDocument: false) }, showPage: showPDFPage)
                                .id("summary-root")
                            sourceHighlightsCard
                            if overviewAnalysisIncomplete {
                                Text(UIStrings.text("Analysis is incomplete: available findings may be partial."))
                                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
                            }
                            readingAgendaCard
                            ChosenPassagesOverviewLink(count: workspace.chosenPassages.count) {
                                section = .selection; pointsMode = .mine; pointsExpanded = true
                            }
                            coverageCard
                            ForEach(workspace.tables.filter { $0.isOCRConfirmed && $0.ocrReview?.summary != nil }) { table in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(UIStrings.text("Reviewed table data")).font(.title3.weight(.semibold))
                                    if let digest = table.ocrReview?.summary {
                                        Text(digest.overview).font(.caption).foregroundStyle(.secondary)
                                        ForEach(Array(digest.bullets.enumerated()), id: \.offset) { _, fact in Text("• " + fact).textSelection(.enabled) }
                                    }
                                    ForEach(table.pages, id: \.self) { page in
                                        Button(UIStrings.text("Show in PDF · p. \(page)")) { showPDFPage(page) }.buttonStyle(FocusSecondaryButtonStyle())
                                    }
                                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                                    .readingSurface()
                            }
                            }
                            if section == .tables {
                            if workspace.tables.isEmpty { Text(UIStrings.text("No tables with enough recognizable structure were found. OCR supports image tables with clear grid lines. Check other tables in the PDF.")).padding(24) }
                            TableExplanationView(tables: workspace.tables, showPage: { showPDFPage($0) }, tutorialExpanded: true,
                                sourceData: workspace.document?.data, saveReview: workspace.saveReviewedTable,
                                analyzeReview: { workspace.analyzeReviewedTable(id: $0, model: AIConfiguration.selectedModel) },
                                stopAnalysis: workspace.stopTableAnalysis, reviewDisabled: workspace.busy || workspace.committeeReviewBusy || workspace.exporting,
                                analysisID: workspace.tableAnalysisID, analysisError: workspace.tableAnalysisError,
                                openTableIDs: $openTableIDs, targetTableID: pendingTableID,
                                onTargetTable: { id in pendingScrollID = "table-card-" + id; lastTableID = id; pendingTableID = nil })
                                .id(workspace.documentID)
                            }
                            if section == .points || section == .selection {
                            if section == .selection {
                                ChosenPassagesView(workspace: workspace) { page, quote in
                                    showPDFPane = true
                                    if quote.isEmpty { pdfControls.resetHighlight(); workspace.showPage(page) }
                                    else { pdfControls.pin(.init(id: "chosen-\(page)-\(quote.hashValue)", page: page, quote: quote)) }
                                }
                            }
                            VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { pointsExpanded.toggle() }
                                } label: {
                                    HStack {
                                Text(section == .selection ? "My selection" : (workspace.analyzed ? workspace.neutralAnalysis : !compareProgram) ? "Findings" : "Profile findings").font(.system(size: 26, weight: .semibold))
                                        Spacer()
                                        Image(systemName: "chevron.down").rotationEffect(.degrees(pointsExpanded ? 180 : 0))
                                    }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityValue(pointsExpanded ? "Expanded" : "Collapsed")
                                Spacer(minLength: 0)
                                if compareProgram && showingAnalysisOptions { Button(UIStrings.text("Focus"), systemImage: "slider.horizontal.3") { showingFocus = true }
                                    .help(UIStrings.text("Edit focus")).disabled(workspace.busy) }
                            }
                            if pointsExpanded {
                            if section == .points {
                                FocusMenuPicker(UIStrings.text("Prepare for"),
                                                selection: Binding(get: { workspace.meetingPurpose }, set: { workspace.setMeetingPurpose($0) }),
                                                selectedTitle: UIStrings.text(workspace.meetingPurpose.title)) {
                                    ForEach(MeetingPurpose.allCases, id: \.self) { purpose in
                                        Text(UIStrings.text(purpose.title)).tag(purpose)
                                    }
                                }.frame(maxWidth: 340, alignment: .leading)
                                .disabled(!workspace.canChangeMeetingPurpose)
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack { pointFilters }
                                VStack(alignment: .leading) { pointFilters }
                            }
                            if !pointPageFilter.isEmpty, (try? PageScope.parse(pointPageFilter, count: document.pages.count)) == nil { Text(UIStrings.text("Enter valid pages, for example 3–7, 12.")).font(.caption).foregroundStyle(.orange) }
                            if section == .points && workspace.meetingPurpose != .raad {
                                committeeReviewView(for: workspace.meetingPurpose)
                            } else {
                            let featuredCount = workspace.featuredInsightGroups.reduce(0) { $0 + $1.points.count }
                            let allCount = workspace.organizedInsights.count
                            if section == .points {
                                FocusChoiceTabs(UIStrings.text("Show points"), selection: $pointsMode, options: [
                                    FocusChoiceOption(value: PointsViewMode.featured, title: UIStrings.text("Most important"), count: featuredCount),
                                    FocusChoiceOption(value: PointsViewMode.all, title: UIStrings.text("All points"), count: allCount)
                                ])
                                .frame(maxWidth: 640)
                            }
                            if pointsMode == .featured && allCount > featuredCount {
                                Text(UIStrings.text("Automatically selected key points. Every point remains available under ‘All points’."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if compareProgram && showingAnalysisOptions {
                            Label(workspace.programName, systemImage: "text.book.closed").font(.callout)
                            Text(UIStrings.text("Document sections are compared with selected programme passages. Indirect links may be missed.")).font(.caption).foregroundStyle(.secondary)
                            Text(focus.prompt.isEmpty ? UIStrings.text("No additional focus set.") : focus.prompt)
                                .font(.callout).foregroundStyle(.secondary)
                            }
                            if workspace.analyzed && !workspace.neutralAnalysis && (workspace.analysisContext != focus.prompt || workspace.programChanged) {
                                Text(UIStrings.text("Reading goal or reference document changed. Click Analyze to refresh the results.")).font(.caption).foregroundStyle(.orange)
                            }
                            if workspace.analyzed && workspace.neutralAnalysis == compareProgram {
                            Text("Mode changed. Click Analyze to refresh the findings.").font(.caption).foregroundStyle(.orange)
                            }
                            if workspace.analyzed {
                                Text(UIStrings.text(workspace.analysisScope)).font(.caption.bold())
                                let unfilteredGroups = pointsMode == .featured ? workspace.featuredInsightGroups : pointsMode == .mine ? workspace.selectedInsightGroups : workspace.insightGroups
                                let allowedPages: Set<Int>? = pointPageFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Set((try? PageScope.parse(pointPageFilter, count: document.pages.count)) ?? [])
                                let groupedMatches = unfilteredGroups.compactMap { group -> InsightGroup? in
                                    let points = group.points.filter { matchesPoint($0, pages: allowedPages) }
                                    guard !points.isEmpty else { return nil }
                                    var result = group; result.points = points; return result
                                }
                                let orderedSelection = workspace.selectedInsightsInOrder.filter { matchesPoint($0, pages: allowedPages) }
                                let groups = pointsMode == .mine
                                    ? (orderedSelection.isEmpty ? [] : [InsightGroup(title: "My selection", description: "Findings in your chosen order.", points: orderedSelection)])
                                    : groupedMatches
                                let totalByGroup = Dictionary(uniqueKeysWithValues: workspace.insightGroups.map { ($0.id, $0.points.count) })
                                if groups.isEmpty {
                                    let onlyBackground = pointsMode == .featured && pointPageFilter.isEmpty && reviewFilter == 0
                                        && !workspace.insightGroups.isEmpty
                                        && workspace.insightGroups.flatMap(\.points).allSatisfy { $0.relevanceClass == "background" }
                                    let emptyMessage = onlyBackground ? "No featured findings in this view. Check all findings for more detail."
                                        : (!pointPageFilter.isEmpty || reviewFilter != 0) ? "No findings match these filters."
                                        : pointsMode == .mine && workspace.chosenPassages.isEmpty ? "Your selection is empty. Use the star on a finding to add it."
                                        : pointsMode == .mine ? "Your selected passages are above. There are no AI findings in My selection."
                                        : workspace.analysisState.englishTitle
                                    Text(UIStrings.text(emptyMessage)).foregroundStyle(.secondary)
                                }
                                VStack(alignment: .leading, spacing: 16) {
                                ForEach(groups) { group in
                                    if pointsMode == .mine {
                                        LazyVStack(alignment: .leading, spacing: 12) {
                                            ForEach(Array(group.points.enumerated()), id: \.element.id) { index, point in
                                                selectionPointRow(point, index: index, count: group.points.count)
                                            }
                                        }
                                    } else {
                                    VStack(alignment: .leading, spacing: 0) {
                                    Button {
                                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                            if openGroups.contains(group.id) { openGroups.remove(group.id) }
                                            else { openGroups.insert(group.id) }
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(group.title + " · " + (pointsMode == .mine ? "\(group.points.count) " + UIStrings.text("selected") : pointsMode == .featured ? "\(group.points.count) " + UIStrings.text("of") + " \(totalByGroup[group.id, default: group.points.count])" : "\(group.points.count)"))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 12)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .rotationEffect(.degrees(openGroups.contains(group.id) ? 90 : 0))
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityValue(openGroups.contains(group.id) ? "Expanded" : "Collapsed")
                                    .accessibilityHint(UIStrings.text("Expand or collapse the category"))
                                    if openGroups.contains(group.id) {
                                        LazyVStack(alignment: .leading, spacing: 0) {
                                        Text(UIStrings.text(group.description)).font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                                ForEach(Array(PassagePointGroup.partition(group.points).enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().padding(.vertical, 8) }
                                    if item.points.count > 1, let first = item.points.first {
                                        PassagePointGroupView(points: item.points, showSource: { page, quote in
                                            showPDFPane = true
                                            pdfControls.pin(.init(id: first.id, page: page, quote: quote))
                                        }) { point in
                                            insightCard(point)
                                        }
                                    } else if let point = item.points.first {
                                        insightCard(point)
                                    }
                                }
                                        }
                                    }
                                    }
                                    }
                                }
                                }
                            } else if section != .selection || workspace.chosenPassages.isEmpty {
                                Text(UIStrings.text(workspace.analysisState.englishTitle)).foregroundStyle(.secondary)
                            }
                            }
                            }
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !pdfControls.highlightNotice.isEmpty { Text(UIStrings.text(pdfControls.highlightNotice)).font(.caption).foregroundStyle(.orange) }

                        }.frame(maxWidth: 820).frame(maxWidth: .infinity)
                            .padding(.horizontal, 24).padding(.bottom, 24)
                            .background(PersistentScrollbarsAttachment())
                    }.frame(minWidth: 380, idealWidth: 640)
                        .onChange(of: pendingScrollID) { _, destination in
                            if let destination {
                                let expectedDocumentID = workspace.documentID
                                let expectedPurpose = workspace.meetingPurpose
                                let parent = pendingCommitteePassageID
                                Task { @MainActor in
                                    await Task.yield()
                                    guard workspace.documentID == expectedDocumentID, pendingScrollID == destination else { return }
                                    if let parent {
                                        scrollProxy.scrollTo(parent, anchor: .top)
                                        // Materialize the lazy parent before addressing its child card.
                                        try? await Task.sleep(nanoseconds: 100_000_000)
                                    }
                                    guard workspace.documentID == expectedDocumentID, workspace.meetingPurpose == expectedPurpose,
                                          pendingScrollID == destination else { return }
                                    scrollProxy.scrollTo(destination, anchor: .top)
                                    pendingScrollID = nil; pendingCommitteePassageID = nil
                                }
                            }
                        }
                    }
                        .opacity(chatPresentation == nil ? 1 : 0)
                        .allowsHitTesting(chatPresentation == nil)
                        .accessibilityHidden(chatPresentation != nil)
                    if let chat = chatPresentation {
                        DocumentChatView(session: chat.wholeDocument ? workspace.documentChat : workspace.pageChat,
                                         document: chat.document, pages: chat.pages, model: chat.model, focus: chat.focus,
                                         showSource: { page, quote in
                                             showPDFPane = true
                                             pdfControls.pin(.init(id: "chat-\(page)-\(quote)", page: page, quote: quote))
                                         },
                                         embedded: true, passage: chat.passage, initialQuestion: chatQuestion,
                                         close: { chatPresentation = nil })
                            .id(chat.id).frame(minWidth: 410, idealWidth: 530)
                    }
                    }
                    }.frame(minWidth: 380, idealWidth: 640)
                    if showPDFPane {
                    PDFPreview(data: document.data, page: workspace.page, navigationID: workspace.navigationID, controls: pdfControls)
                        .overlay(alignment: .bottom) { PDFControlsBar(controls: pdfControls).padding(20) }
                        .overlay(alignment: .topLeading) {
                            GeometryReader { geometry in
                                if !selectingChart, let selection = pdfControls.selectedText, let anchor = pdfControls.selectionAnchor {
                                    let actionWidth = min(420, max(0, geometry.size.width - 16))
                                    PDFSelectionActionButton(disabled: workspace.busy || selectionSummary.busy,
                                                             waitingForAnalysis: workspace.busy,
                                                             action: { startSelectionSummary(selection) },
                                                             addChosen: { _ = workspace.addChosenPassage(selection) },
                                                             addDisabled: workspace.exporting || (workspace.busy && workspace.processingPresented && !workspace.processingDocumentReady) || workspace.document == nil,
                                                             alreadyAdded: workspace.chosenPassages.contains { $0.text == selection.text && $0.pages == selection.pages })
                                    .frame(width: actionWidth, alignment: .leading)
                                    .position(x: min(max(actionWidth / 2 + 8, anchor.x), max(actionWidth / 2 + 8, geometry.size.width - actionWidth / 2 - 8)),
                                              y: min(max(20, anchor.y + 30), max(20, geometry.size.height - 48)))
                                }
                            }
                        }
                        .overlay {
                            if selectingChart {
                                GeometryReader { _ in
                                    Color.clear.contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                if chartDragStart == nil { chartDragStart = value.startLocation }
                                                chartDragEnd = value.location
                                            }
                                            .onEnded { value in
                                                let start = chartDragStart ?? value.startLocation
                                                let area = CGRect(x: start.x, y: start.y,
                                                                  width: value.location.x - start.x,
                                                                  height: value.location.y - start.y).standardized
                                                chartDragStart = nil; chartDragEnd = nil; selectingChart = false
                                                finishChartSelection(area)
                                            })
                                    if let start = chartDragStart, let end = chartDragEnd {
                                        let area = CGRect(x: start.x, y: start.y,
                                                          width: end.x - start.x, height: end.y - start.y).standardized
                                        Rectangle().fill(Color.blue.opacity(0.16))
                                            .overlay { Rectangle().strokeBorder(.blue, lineWidth: 2) }
                                            .frame(width: area.width, height: area.height)
                                            .position(x: area.midX, y: area.midY)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if selectingChart {
                                Text(UIStrings.text("Drag a box around the chart, including its title and legend"))
                                    .font(.caption.bold()).padding(10)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                    .padding(12).allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            Menu {
                Button(selectingChart ? "Cancel selection" : "Select chart") {
                                    selectingChart.toggle(); chartDragStart = nil; chartDragEnd = nil; pdfControls.selectedText = nil
                                }
                                Button(UIStrings.text("Enter chart area…")) { selectingChart = false; showingChartArea = true }
                            } label: { Label(UIStrings.text("Chart"), systemImage: "chart.bar.xaxis").foregroundStyle(Color.primary) }
                            .focusMenu().fixedSize()
                            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)

                        }
                        .frame(minWidth: 320, idealWidth: 480)
                        .background(SPTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
        }
        .onChange(of: pdfControls.pinned) { _, target in if target != nil { showPDFPane = true } }
        .onChange(of: workspace.navigationID) { _, _ in
            if restoredNavigationID == workspace.navigationID {
                restoredNavigationID = nil
            } else if workspace.restoredViewState != nil {
                restoredNavigationID = workspace.navigationID
            } else {
                showPDFPane = true
            }
        }
    }

    private var readingAgendaCard: some View {
        let entries = ReadingAgenda.entries(workspace.organizedInsights)
        let uniquePointCount = Set(entries.map { $0.point.id }).count
        let populatedCategories = ReadingAgendaCategory.allCases.filter { category in entries.contains { $0.category == category } }
        let card: AnyView
        if entries.isEmpty {
            let message = overviewAnalysisIncomplete
                ? "No findings are available for the reading agenda yet. Processing is incomplete, so the overview may be partial."
                : "No findings are available for the reading agenda."
            card = AnyView(Text(UIStrings.text(message)).font(.callout).foregroundStyle(.secondary))
        } else {
            card = AnyView(DisclosureGroup(isExpanded: $readingAgendaExpanded) {
            VStack(alignment: .leading, spacing: 14) {
            Text(UIStrings.text("A quick route through existing findings. Each finding keeps its own text and sources."))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(populatedCategories) { category in
                var seenCategoryPointIDs = Set<String>()
                let matches = entries.filter { $0.category == category && seenCategoryPointIDs.insert($0.point.id).inserted }
                VStack(alignment: .leading, spacing: 7) {
                    Text(readingAgendaCategoryTitle(category)).font(.headline)
                        Text(UIStrings.text("Points") + " · \(matches.count)")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(matches.prefix(3)) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Button(entry.point.title) { openAgendaPoint(entry.point) }
                                    .buttonStyle(FocusQuietActionStyle()).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Button(UIStrings.text("p. \(entry.point.page)")) {
                                    showPDFPane = true
                                    pdfControls.pin(.init(id: entry.point.id, page: entry.point.page, quote: entry.point.quote))
                                }.buttonStyle(FocusQuietActionStyle()).font(.caption)
                            }
                        }
                        if matches.count > 3 {
                            Button(UIStrings.text("Open all document findings")) {
                                section = .points; pointsMode = .all; pointsExpanded = true
                                if workspace.meetingPurpose != .raad { committeeShowAll[workspace.meetingPurpose.rawValue] = true }
                                pointPageFilter = ""; reviewFilter = 0
                            }.buttonStyle(FocusQuietActionStyle())
                        }
                }
            }
            }
        } label: {
            HStack {
                Text(UIStrings.text("Reading agenda")).font(.title3.weight(.semibold))
                Spacer()
                Text("\(uniquePointCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            })
        }
        return card.padding(24).frame(maxWidth: .infinity, alignment: .leading).readingSurface()
    }

    private func selectionPointRow(_ point: Insight, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FocusMenuPicker(UIStrings.text("Review status"), selection: Binding(
                    get: { workspace.meetingStatus(for: point) },
                    set: { workspace.setMeetingStatus($0, for: point) }
                ), selectedTitle: meetingStatusLabel(workspace.meetingStatus(for: point))) {
                    ForEach(SelectionMeetingStatus.allCases, id: \.self) { status in
                        Text(meetingStatusLabel(status)).tag(status)
                    }
                }.frame(maxWidth: 220)
                    .accessibilityLabel("Review status for \(point.title)")
                Button { workspace.moveSelected(point, by: -1) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small).disabled(index == 0)
                    .help(UIStrings.text("Move finding up"))
                    .accessibilityLabel(UIStrings.text("Move finding up"))
                Button { workspace.moveSelected(point, by: 1) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small).disabled(index == count - 1)
                    .help(UIStrings.text("Move finding down"))
                    .accessibilityLabel(UIStrings.text("Move finding down"))
                Spacer(minLength: 0)
            }
            insightCard(point)
        }
        .padding(12).background(SPTheme.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func insightCard(_ point: Insight, committee: CommitteeCardContext? = nil) -> some View {
        InsightCard(point: point, neutral: workspace.neutralAnalysis, model: AIConfiguration.selectedModel, focus: focus.prompt,
                    selected: showPDFPane && pdfControls.pinned?.id == point.id && pdfControls.pinned?.page == pdfControls.page, starred: workspace.isStarred(point),
                    toggleStar: { workspace.toggleStar(point) },
                    annotation: workspace.annotation(for: point),
                    annotationChanged: { workspace.setAnnotation($0, for: point) },
                    compact: compactReading, committeeLabel: committee?.label,
                    committeeReason: committee?.reason, committeeEvidence: committee?.evidence,
                    committeeContextSources: committee?.sources ?? [],
                    savedQuestions: workspace.passageQuestions[SimpleWorkspace.selectionKey(point)] ?? [],
                    questionsChanged: { workspace.setPassageQuestions($0, for: SimpleWorkspace.selectionKey(point)) },
                    showSource: { page, quote in
                        showPDFPane = true
                        pdfControls.pin(.init(id: point.id, page: page, quote: quote))
                    },
                    explain: {
                        pdfControls.pin(.init(id: point.id, page: point.page, quote: point.quote))
                        openChat(pages: [point.page], wholeDocument: false, passage: point.quote,
                                 question: "Explain this passage in plain English. What does it state, and what remains unclear?")
                    }).id(point.id)
    }

    private var coverageCard: some View {
        let coverage = workspace.documentCoverage
        return DisclosureGroup(isExpanded: $showingCoverage) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Physical PDF pages: \(coverage.totalPages)")
                Text("Pages with readable text: \(coverage.readablePages) of \(coverage.totalPages)")
                switch coverage.analysis {
                case .complete(let count):
                    Text("Analysis completed successfully for \(count) readable \(count == 1 ? "page" : "pages").")
                    if let pages = coverage.completedAnalysisPageNumbers, !pages.isEmpty {
                        Text(UIStrings.text("Completed pages:" )).font(.caption.weight(.semibold))
                        pageLinks(pages, label: "Analyzed")
                    }
                case .partial:
                    Text(UIStrings.text("Analysis is partial; the number of completed sections is unknown."))
                        .foregroundStyle(.orange)
                case .unknown:
                    Text(UIStrings.text("Analysis completeness is unknown; no successfully completed analysis scope was saved."))
                        .foregroundStyle(.secondary)
                }
                if !coverage.unreadablePageNumbers.isEmpty {
                    Text(UIStrings.text("Pages without readable text:" )).font(.caption.weight(.semibold))
                    pageLinks(coverage.unreadablePageNumbers, label: "No readable text")
                }
                Divider()
                Text("Image-based tables: \(coverage.confirmedOCRTables) checked against the source · \(coverage.unconfirmedOCRTables) not yet checked.")
                ForEach(coverage.unconfirmedOCRTableIDs, id: \.self) { id in
                    if let table = workspace.tables.first(where: { $0.id == id }) {
                        Button("Review \(table.title) · PDF page \(table.pages.first ?? 1)") {
                            section = .tables; showPDFPage(table.pages.first ?? 1)
                        }.buttonStyle(FocusQuietActionStyle())
                    }
                }
                Text("Text tables with clear structure: \(coverage.reliableTextTables) · uncertain structure: \(coverage.uncertainTextTables). These counts do not mean a person checked the source.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(coverage.uncertainTableIDs, id: \.self) { id in
                    if let table = workspace.tables.first(where: { $0.id == id }) {
                        Button("Review uncertain table: \(table.title) · PDF page \(table.pages.first ?? 1)") {
                            section = .tables; showPDFPage(table.pages.first ?? 1)
                        }.buttonStyle(FocusQuietActionStyle())
                    }
                }
            }.font(.callout).padding(.top, 10)
        } label: {
            Label(UIStrings.text("Coverage check"), systemImage: "checklist")
                .font(.title3.weight(.semibold))
        }
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .padding(24).frame(maxWidth: .infinity, alignment: .leading).readingSurface()
    }

    @ViewBuilder private func pageLinks(_ pages: [Int], label: String) -> some View {
        HStack {
            Text("\(label): \(pages.count) \(pages.count == 1 ? "page" : "pages") (\(pages.first ?? 0)–\(pages.last ?? 0))")
                .font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(pages, id: \.self) { page in
                    Button("PDF page \(page)") { showPDFPage(page) }
                }
            } label: { Text(UIStrings.text("Choose source page")).foregroundStyle(Color.primary) }
                .disabled(pages.isEmpty).focusMenu()
        }
    }

    private func openAgendaPoint(_ point: Insight) {
        openPoint(point)
    }

    /// Display wording may describe scope, while the stored WorkbenchSection stays stable for archives.
    private func workbenchSectionTitle(_ destination: WorkbenchSection) -> String {
        switch destination {
        case .overview: "Document overview"
        case .points: workspace.meetingPurpose == .raad ? "Document findings" : "Profile findings"
        case .tables: "Tables"
        case .selection: "My selection"
        case .search: "Search"
        }
    }

    private func openPoint(_ point: Insight) {
        section = .points; pointsMode = .all; pointsExpanded = true
        pendingCommitteePassageID = nil
        if workspace.meetingPurpose != .raad {
            committeeShowAll[workspace.meetingPurpose.rawValue] = true
            if let review = workspace.committeeReviews[workspace.meetingPurpose.rawValue] {
                pendingCommitteePassageID = CommitteePointPresentation(review: review, points: workspace.organizedInsights).scrollID(containing: point.id)
            }
        }
        pointPageFilter = ""; reviewFilter = 0
        if let group = workspace.insightGroups.first(where: { $0.points.contains(where: { $0.id == point.id }) }) { openGroups.insert(group.id) }
        pendingScrollID = point.id
    }

    @ViewBuilder private func committeeReviewView(for purpose: MeetingPurpose) -> some View {
        CommitteeReviewView(workspace: workspace,
                            showAll: Binding(get: { committeeShowAll[purpose.rawValue] ?? false },
                                             set: { committeeShowAll[purpose.rawValue] = $0 }),
                            expandedCategories: Binding(get: { committeeOpenCategories[purpose.rawValue] ?? [] },
                                                        set: { committeeOpenCategories[purpose.rawValue] = $0 }),
                            hasStoredCategoryState: committeeOpenCategories[purpose.rawValue] != nil,
                            pageFilter: pointPageFilter, reviewFilter: reviewFilter, pendingPointID: pendingScrollID,
                            showSource: { page, quote in
                                showPDFPane = true
                                pdfControls.pin(.init(id: "committee-\(page)-\(quote.hashValue)", page: page, quote: quote))
                            },
                            pointContent: { point, context in insightCard(point, committee: context) })
            .id("committee-review-\(purpose.rawValue)")
    }

    private func trackViewStateChange() {
        workspace.updateTerminationSnapshot(readingPage: workspace.page, viewState: viewState)
        if viewState != savedViewState { workspace.markDirty() }
    }

    private func handleOpenPDFRequest() {
        guard !workspace.busy, !workspace.committeeReviewBusy, !workspace.exporting else { return }
        importing = true
    }

    private func handleFindRequest() {
        guard !workspace.showsWelcome, !workspace.processingPresented else { return }
        chatPresentation = nil
        section = .search
        searchFocusRequest += 1
    }

    private func handleAppear() {
        closeBridge.workspace = workspace
        WorkspaceWindowRegistry.register(workspace)
        workspace.updateTerminationSnapshot(readingPage: workspace.page, viewState: viewState)
        refreshProgramChoice()
        appleUnavailable = AIConfiguration.unavailability()
    }
    private func handleSettingsDismiss() {
        workspace.useConfiguredReference()
        refreshProgramChoice()
        appleUnavailable = AIConfiguration.unavailability()
    }

    private func openPendingComparisonSource() {
        guard let source = pendingComparisonSource else { return }
        pendingComparisonSource = nil
        showPDFPane = true
        workspace.showPage(source.page)
        pdfControls.pin(.init(id: source.id, page: source.page, quote: source.quote))
    }

    private func showPDFPage(_ page: Int) {
        showPDFPane = true
        pdfControls.resetHighlight()
        workspace.showPage(page)
    }

    private func requestWorkspaceAction(_ action: PendingWorkspaceAction) {
        if case .choosePDF = action {
            guard !workspace.busy, !workspace.committeeReviewBusy, !workspace.exporting else { return }
            if workspace.showsWelcome { pendingImportPurpose = importPurpose; importing = true }
            else { importPurpose = .raad; showingImportPurpose = true }
            return
        }
        if case .returnToImport = action, workspace.busy, !workspace.processingDocumentReady, workspace.document != nil {
            workspace.returnToImport()
            return
        }
        guard !workspace.busy || isReturnAction(action) || isTerminationAction(action) || isWindowCloseAction(action) else { return }
        guard !workspace.exporting else { return }
        if workspace.committeeReviewBusy {
            workspace.stopCommitteeReview()
            Task { @MainActor in
                while workspace.committeeReviewBusy { try? await Task.sleep(nanoseconds: 20_000_000) }
                requestWorkspaceAction(action)
            }
            return
        }
        if workspace.document != nil && workspace.hasUnsavedChanges {
            pendingWorkspaceAction = action
            pendingActionDialogPresented = true
        } else {
            pendingWorkspaceAction = action
            performPendingAction()
        }
    }

    private func isReturnAction(_ action: PendingWorkspaceAction) -> Bool {
        if case .returnToImport = action { return true }
        return false
    }

    private func isTerminationAction(_ action: PendingWorkspaceAction) -> Bool {
        if case .terminate = action { return true }
        return false
    }
    private func isWindowCloseAction(_ action: PendingWorkspaceAction) -> Bool {
        if case .closeWindow = action { return true }
        return false
    }

    private func performPendingAction() {
        guard let action = pendingWorkspaceAction else { return }
        pendingWorkspaceAction = nil
        pendingActionDialogPresented = false
        switch action {
        case .choosePDF: importing = true
        case .importPDF(let urls): _ = importPDF(urls)
        case .openWorkspace: workspace.openWorkspace()
        case .openWorkspaceURL(let url): workspace.openWorkspace(at: url)
        case .openRecentWorkspace(let entry): workspace.openRecentWorkspace(entry)
        case .relocateRecentWorkspace(let entry): workspace.relocateRecentWorkspace(entry)
        case .returnToImport: workspace.returnToImport()
        case .closeWindow: closeBridge.closeAfterAuthorization()
        case .terminate:
            if workspace.hasUnsavedChanges { WorkspaceWindowRegistry.authorizeTerminationRevision(for: workspace) }
            continueTerminationSequence()
        }
    }

    private func cancelPendingAction() {
        let wasTermination: Bool
        if let action = pendingWorkspaceAction, case .terminate = action { wasTermination = true } else { wasTermination = false }
        pendingWorkspaceAction = nil
        pendingActionDialogPresented = false
        if wasTermination { WorkspaceWindowRegistry.cancelTerminationSequence() }
    }

    private func handleTerminationRequest(_ object: Any?) {
        guard let target = object as? ObjectIdentifier,
              target == ObjectIdentifier(workspace), workspace.hasUnsavedChanges else { return }
        requestWorkspaceAction(.terminate)
    }

    private func handleWindowCloseRequest(_ object: Any?) {
        guard let target = object as? ObjectIdentifier,
              target == ObjectIdentifier(workspace), workspace.document != nil,
              workspace.hasUnsavedChanges else { return }
        requestWorkspaceAction(.closeWindow)
    }

    private func continueTerminationSequence() {
        if !WorkspaceWindowRegistry.requestNextDirtyWorkspace() {
            TerminationScheduler.enqueue { NSApp.terminate(nil) }
        }
    }

    private func saveThenContinue() {
        guard let action = pendingWorkspaceAction else { return }
        pendingActionSaveInFlight = true
        pendingActionDialogPresented = false
        let documentID = workspace.documentID
        let capturedState = viewState
        workspace.saveWorkspace(readingPage: workspace.page, viewState: capturedState) { saved in
            pendingActionSaveInFlight = false
            guard saved, workspace.documentID == documentID, !workspace.hasUnsavedChanges else {
                cancelPendingAction()
                return
            }
            guard pendingWorkspaceAction != nil else { return }
            savedViewState = capturedState
            pendingWorkspaceAction = action
            performPendingAction()
        }
    }

    private func saveWorkspace() {
        let capturedState = viewState
        workspace.saveWorkspace(readingPage: workspace.page, viewState: capturedState) { saved in
            if saved { savedViewState = capturedState }
        }
    }

    private var isWorkspaceFileModalPresented: Bool {
        showingFocus || showingLayout || showingGlossary ||
        showingSettings || showingTutorial || showingChartArea || selectedChart != nil ||
        showingSavedExtras || showingExport || showingComparison || showingImportPurpose || importing ||
        pendingActionDialogPresented || workspace.error != nil
    }

    private var workspaceFileMenuActions: WorkspaceFileMenuActions {
        let canInteract = !workspace.busy && !workspace.committeeReviewBusy && !workspace.exporting
        return WorkspaceFileMenuActions(
            canOpen: canInteract,
            canSave: canInteract && workspace.document != nil,
            open: {
                guard !isWorkspaceFileModalPresented, NSApp.modalWindow == nil,
                      NSApp.keyWindow?.sheetParent == nil, NSApp.keyWindow?.attachedSheet == nil,
                      !workspace.busy, !workspace.committeeReviewBusy, !workspace.exporting else { return }
                requestWorkspaceAction(.openWorkspace)
            },
            save: {
                guard !isWorkspaceFileModalPresented, NSApp.modalWindow == nil,
                      NSApp.keyWindow?.sheetParent == nil, NSApp.keyWindow?.attachedSheet == nil,
                      !workspace.busy, !workspace.committeeReviewBusy, !workspace.exporting,
                      workspace.document != nil else { return }
                saveWorkspace()
            })
    }

    @ViewBuilder private var pointFilters: some View {
        Toggle(UIStrings.text("Compact reading"), isOn: $compactReading).toggleStyle(.checkbox)
        TextField(UIStrings.text("Filter pages"), text: $pointPageFilter).textFieldStyle(FocusInputFieldStyle()).frame(maxWidth: 150)
        let selectedReviewTitle = ["All", "Needs review", "Checked by me"][min(2, max(0, reviewFilter))]
        FocusMenuPicker(UIStrings.text("Review"), selection: $reviewFilter, selectedTitle: UIStrings.text(selectedReviewTitle)) {
            Text(UIStrings.text("All")).tag(0)
            Text(UIStrings.text("Needs review")).tag(1)
            Text(UIStrings.text("Checked by me")).tag(2)
        }.frame(maxWidth: 240)
        if !pointPageFilter.isEmpty || reviewFilter != 0 { Button(UIStrings.text("Clear filters")) { pointPageFilter = ""; reviewFilter = 0 } }
    }

    private func finishChartSelection(_ area: CGRect) {
        guard area.width >= 30, area.height >= 30,
              let view = pdfControls.view, let document = view.document else {
            workspace.error = "Select a larger area around the chart."
            return
        }
        func point(_ source: CGPoint) -> CGPoint {
            CGPoint(x: source.x, y: view.isFlipped ? source.y : view.bounds.height - source.y)
        }
        let first = point(CGPoint(x: area.minX, y: area.minY))
        let last = point(CGPoint(x: area.maxX, y: area.maxY))
        guard let page = view.page(for: first, nearest: false),
              let finalPage = view.page(for: last, nearest: false), page === finalPage else {
            workspace.error = "Select one chart on a single PDF page."
            return
        }
        let a = view.convert(first, to: page), b = view.convert(last, to: page)
        let region = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                            width: abs(a.x - b.x), height: abs(a.y - b.y))
        guard let image = ChartImageRenderer.render(page: page, region: region) else {
            workspace.error = "The selected chart could not be read as an image. Select a smaller area."
            return
        }
        selectedChartExplanation = nil
        selectedChart = SelectedChart(page: document.index(for: page) + 1, image: image)
    }

    private func openChat(pages: [Int], wholeDocument: Bool, passage: String? = nil, question: String = "") {
        guard let document = workspace.document else { return }
        do {
            let chat = try ChatPresentation(document: document, selected: pages, model: AIConfiguration.selectedModel, focus: focus.prompt, wholeDocument: wholeDocument, passage: passage)
            let session = wholeDocument ? workspace.documentChat : workspace.pageChat
            let key = LocalCache.key([LocalCache.key(document.pages), chat.model, chat.focus, workspace.programIdentity, passage ?? ""] + chat.pages.map(String.init))
            let saved = workspace.savedChatThreads.last { $0.id == key }
            configureChatSession(session, key: key, chat: chat, savedMessages: saved?.messages)
            workspace.documentChat.cancel(); workspace.pageChat.cancel()
            chatQuestion = question
            chatPresentation = chat
        } catch { workspace.error = error.localizedDescription }
    }

    private func configureSelectionSummaryCapture() {
        let expectedDocumentID = workspace.documentID
        selectionSummary.onSummary = { [weak workspace] saved in
            workspace?.rememberSelectionSummary(saved, expectedDocumentID: expectedDocumentID)
        }
    }
    private func startSelectionSummary(_ selection: SelectedPDFText) {
        configureSelectionSummaryCapture()
        selectionSummary.start(selection, model: AIConfiguration.selectedModel)
    }
    private func openSavedSelectionSummary(_ saved: SavedSelectionSummary) {
        configureSelectionSummaryCapture()
        selectionSummary.restore(saved)
    }

    private func configureChatSession(_ session: DocumentChatSession, key: String, chat: ChatPresentation, savedMessages: [ChatMessage]?) {
        let expectedDocumentID = workspace.documentID
        session.onMessagesChanged = nil
        session.configure(workspace.chatStorageKey(key))
        if let savedMessages { session.messages = savedMessages }
        let capture: ([ChatMessage]) -> Void = { [weak workspace] messages in
            workspace?.rememberChat(SavedChatThread(id: key, pages: chat.pages, model: chat.model, focus: chat.focus,
                wholeDocument: chat.wholeDocument, passage: chat.passage, messages: messages), expectedDocumentID: expectedDocumentID)
        }
        session.onMessagesChanged = capture
        if !session.messages.isEmpty { capture(session.messages) }
    }

    private func openSavedChat(_ thread: SavedChatThread) {
        guard let document = workspace.document else { return }
        do {
            let chat = try ChatPresentation(document: document, selected: thread.pages, model: thread.model,
                focus: thread.focus, wholeDocument: thread.wholeDocument, passage: thread.passage)
            workspace.documentChat.cancel(); workspace.pageChat.cancel()
            let session = thread.wholeDocument ? workspace.documentChat : workspace.pageChat
            configureChatSession(session, key: thread.id, chat: chat, savedMessages: thread.messages)
            chatQuestion = ""
            chatPresentation = chat
        } catch { workspace.error = error.localizedDescription }
    }

    private func refreshSearchBase() async {
        guard let document = workspace.document else { searchBase = []; return }
        let key = workspace.documentID
        searchIndexing = true
        let pages = document.pages
        let documentKey = LocalCache.key(pages)
        let records = await Task.detached(priority: .utility) {
            UnifiedSearch.documentRecords(pages: pages, documentKey: documentKey)
        }.value
        guard key == workspace.documentID else { return }
        searchBase = records
        searchIndexing = false
    }

    private func openTable(_ id: String) {
        section = .tables
        openTableIDs.insert(id)
        lastTableID = id
        pendingTableID = id
    }

    private func openSearchResult(_ record: SearchRecord) {
        switch record.action {
        case .page(let page, let quote):
            showPDFPane = true
            workspace.showPage(page)
            if let quote { pdfControls.pin(.init(id: record.id, page: page, quote: quote)) }
            else { pdfControls.resetHighlight() }
        case .point(let id, _, _):
            if let point = workspace.organizedInsights.first(where: { $0.id == id }) { openPoint(point) }
        case .chosenPassage(let id):
            section = .selection; pointsMode = .mine; pointsExpanded = true
            pendingScrollID = "chosen-\(id.uuidString)"
        case .table(let id, let page):
            openTable(id)
            if let page { showPDFPage(page) }
        case .summary:
            section = .overview; pendingScrollID = "summary-root"
        case .glossary(let term):
            glossarySearch = term
            showingGlossary = true
        }
    }

    private func refreshProgramChoice() {
        workspace.refreshProgram()
        if workspace.programIdentity == "none" { compareProgram = false }
    }

    @discardableResult private func importPDF(_ urls: [URL]) -> Bool {
        if compareProgram && workspace.programIdentity == "none" {
            workspace.error = UIStrings.text("Add a reference document in Settings before comparing documents, or choose a document overview.")
            return false
        }
        return workspace.load(urls, themes: focus.themes, focus: focus.prompt,
                              model: AIConfiguration.selectedModel, compareProgram: compareProgram,
                              meetingPurpose: pendingImportPurpose) != nil
    }

}

private func meetingStatusLabel(_ status: SelectionMeetingStatus) -> String {
    switch status {
    case .discuss: "Discuss"
    case .askQuestion: "Ask a question"
    case .done: "Resolved"
    }
}

private func readingAgendaCategoryTitle(_ category: ReadingAgendaCategory) -> String {
    switch category {
    case .decisions: "Decisions"
    case .money: "Costs"
    case .deadlines: "Deadlines"
    case .actions: "Actions"
    case .risks: "Risks"
    case .openQuestions: "Open questions"
    }
}

func analysisStateLabel(_ state: AnalysisState) -> String {
    switch state {
    case .notStarted: "Not analyzed yet."
    case .running: "Analysis in progress…"
    case .needsProgram: "Add a reference document in Settings to start this comparison."
    case .noSummaryPoints: "No summary findings with confirmed source quotations were found."
    case .noMatches: "Analysis complete: no supported connections were found."
    case .unconfirmed: "Analysis complete: proposed connections could not be confirmed with source quotations."
    case .complete: "Analysis complete."
    case .incomplete: "Analysis partially complete. Retry the missing steps."
    case .failed: "Analysis failed. Try again."
    case .cancelled: "Analysis stopped. You can run it again."
    }
}

private struct AnalysisCard: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .readingSurface()
    }
}
