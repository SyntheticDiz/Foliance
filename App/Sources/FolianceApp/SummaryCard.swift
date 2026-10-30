import SwiftUI

struct SummaryCard: View {
    private let uiLanguage = "en"
    @ObservedObject var workspace: SimpleWorkspace
    @AppStorage("compareProgram") private var compareProgram = false
    let model: String
    var showsOptions = false
    var tutorialExpanded: Bool? = nil
    let chat: ([Int]) -> Void
    let showPage: (Int) -> Void
    private var pageSelection: String { workspace.requestedSelection }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(UIStrings.text("Document-wide overview"), systemImage: "doc.text").font(.system(size: 21, weight: .semibold))
            if showsOptions {
            Text(UIStrings.text("These actions apply to the selected physical PDF pages. Leave blank for the entire document; examples: 3–7, 12.")).font(.caption).foregroundStyle(.secondary)
            Text("Selected AI model: \(AIConfiguration.label(model)). See Analysis status → Model details for the saved model choices.").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(UIStrings.text("Pages (blank = all)"), text: $workspace.requestedSelection).textFieldStyle(FocusInputFieldStyle())
            }
            HStack {
                Button(UIStrings.text("Refresh document overview"), systemImage: "text.alignleft") { workspace.summarize(model: model, selection: pageSelection) }.disabled(!workspace.canStartAnalysis)
                Button(UIStrings.text("Page chat"), systemImage: "bubble.left.and.bubble.right") {
                    do { chat(try PageScope.parse(pageSelection, count: workspace.document?.pages.count ?? 0)) }
                    catch { workspace.error = error.localizedDescription }
                }.help(UIStrings.text("Chat about these pages; blank means all pages")).disabled(workspace.busy)
            }
            Button(compareProgram ? "Refresh findings for these pages using the reference document" : "Refresh findings for these pages") {
                workspace.analyze(model: model, context: workspace.focus, selection: pageSelection, compareProgram: compareProgram)
            }.disabled(!workspace.canStartAnalysis)
            Menu {
                Button("Analyze the entire document", systemImage: "arrow.clockwise") {
                    workspace.requestedSelection = ""
                    workspace.analyze(model: model, context: workspace.focus, targeted: false, compareProgram: compareProgram)
                }.disabled(!workspace.canStartAnalysis)
            } label: { Text(UIStrings.text("More analysis actions")).foregroundStyle(Color.primary) }
                .disabled(!workspace.canStartAnalysis).focusMenu()
            }
            if let summary = workspace.documentSummary {
                Text(UIStrings.text(workspace.summaryScope)).font(.caption).foregroundStyle(.secondary)
                if let notice = summary.fallbackNotice {
                    Label(UIStrings.text("Overview from partial summaries"), systemImage: "doc.on.doc").font(.headline)
                    Text(UIStrings.text(notice)).font(.caption).foregroundStyle(.secondary)
                }
                ReadableText(text: summary.digest.overview).font(.system(size: 14))
                if !summary.digest.bullets.isEmpty { Text(UIStrings.text("Key points")).font(.headline).padding(.top, 8) }
                ForEach(Array(summary.digest.bullets.prefix(5).enumerated()), id: \.offset) { _, point in Text("• " + point).font(.body).textSelection(.enabled) }
                if let document = workspace.document {
                    CommissionRequestView(pages: PageScope.mask(document.pages, selected: workspace.summaryPages.isEmpty ? Array(1...document.pages.count) : workspace.summaryPages)) { showPage($0) }
                }
                Button(expanded ? "Close full overview" : "Full overview", systemImage: "text.alignleft") { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } }.buttonStyle(FocusQuietActionStyle()).tutorialTarget("summary")
                if expanded {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(workspace.summaryPageSections.enumerated()), id: \.offset) { _, section in
                            SummaryPageSectionView(section: section, showPage: showPage)
                        }
                    }
                }
            } else {
                Text(workspace.busy ? "Preparing the overview…" : "Choose pages and create a neutral overview with key points.").foregroundStyle(.secondary)
                Button("Create document overview", systemImage: "sparkles") { workspace.summarize(model: model, selection: pageSelection) }.disabled(!workspace.canStartAnalysis)
            }

        }.font(.body).lineSpacing(5).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .readingSurface()
            .onAppear { if let tutorialExpanded { expanded = tutorialExpanded } }
            .onChange(of: tutorialExpanded) { _, value in if let value { expanded = value } }
    }
}

struct SummaryPageSectionView: View {
    let section: DocumentSummary.Section
    let showPage: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Button("Show in PDF · p. \(section.page)", systemImage: "doc.text.magnifyingglass") { showPage(section.page) }
                .buttonStyle(FocusQuietActionStyle())
            ReadableText(text: section.digest.overview)
            ForEach(Array(section.digest.bullets.enumerated()), id: \.offset) { _, point in
                Text("• " + point).font(.body).textSelection(.enabled)
            }
        }
    }
}

/// Presentation-only long-form prose that preserves source text while matching
/// the reader's paragraph spacing and selectable text behavior.
struct ReadableText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(SummaryDisplayText.chunks(text).enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
