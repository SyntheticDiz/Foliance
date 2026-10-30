import SwiftUI

struct TutorialStep: Identifiable {
    let id: Int
    let group: String
    let title: String
    let action: String
    let outcome: String
    let tip: String
    let symbol: String

    static let all: [TutorialStep] = [
        .init(id: 0, group: "Getting started", title: "Open a PDF",
              action: "Drop a PDF in the start area or choose ‘Add PDF…’. You can also choose a reading profile that fits your goal.",
              outcome: "Foliance reads the text, reading order, and tables. Analysis then starts with your selected provider.",
              tip: "A scan without a readable text layer may need text recognition.", symbol: "doc.badge.plus"),
        .init(id: 1, group: "Getting started", title: "Choose an analysis provider",
              action: "Apple Intelligence is the default and keeps analysis on this Mac. In Settings, you can choose an OpenAI API key or Continue with ChatGPT for cloud analysis.",
              outcome: "Cloud analysis sends document content only after you enable consent and explicitly start an analysis. API-key use is billed to your API account; ChatGPT uses eligible plan usage or credits. For ChatGPT, choose one model for all tasks or separate orchestrator and agent models, each with its own reasoning effort. Foliance never switches providers automatically.",
              tip: "Check model availability and account eligibility in Settings. Reading, search, and saved results remain available when AI is unavailable.", symbol: "sparkles"),
        .init(id: 2, group: "Getting started", title: "Choose a reading goal",
              action: "Choose a reading profile when you add a PDF. You can also add a reference document in Settings.",
              outcome: "A reading profile guides the selection and presentation of findings. A reference document enables a separate comparison.",
              tip: "Add topics or questions under Reading goal to guide the analysis.", symbol: "slider.horizontal.3"),
        .init(id: 3, group: "Getting started", title: "Track and review analysis",
              action: "Follow progress in the analysis overview. Stop analysis to end processing that is in progress.",
              outcome: "Available results stay visible. Stopping while a PDF is being read cancels the import and returns you to the import screen.",
              tip: "Notices about skipped pages or incomplete results appear in the analysis overview. Open the details to see why and what you can do.", symbol: "play.circle"),
        .init(id: 4, group: "Reading", title: "Read the summary",
              action: "Open Overview to read the document summary. Choose Expanded summary for an explanation of each physical PDF page.",
              outcome: "You can see the big picture and where information appears in the document.",
              tip: "Enter a page range to summarize only that part of the document.", symbol: "text.alignleft"),
        .init(id: 5, group: "Reading", title: "Review findings and source passages",
              action: "Review specific source passages in Overview. Open Findings and switch between Most important and All findings.",
              outcome: "Most important shows the key selection. All findings keeps every available result within reach.",
              tip: "Select a finding’s title or summary to check its source text in the PDF.", symbol: "list.bullet.rectangle"),
        .init(id: 6, group: "Reading", title: "Check a finding in its source",
              action: "Select the title or summary of a finding.",
              outcome: "The PDF jumps to the stated physical page and highlights the related passage.",
              tip: "Check amounts, conditions, and conclusions against the original text.", symbol: "arrow.right.doc.on.clipboard"),
        .init(id: 7, group: "Reading", title: "Choose a passage yourself",
              action: "Select text in the PDF with your mouse, then release the button. Choose Summarize selection.",
              outcome: "Foliance explains the selected excerpt and identifies its source page.",
              tip: "The text must be selectable in the PDF.", symbol: "text.cursor"),
        .init(id: 8, group: "Reading", title: "Search the document",
              action: "Open Search or press ⌘F, then type a word or name.",
              outcome: "Search checks the PDF text and available summaries, findings, tables, and abbreviations on this Mac. A result opens the finding card or source passage.",
              tip: "Searching does not start a new AI request.", symbol: "magnifyingglass"),
        .init(id: 9, group: "Getting ready", title: "Understand tables and definitions",
              action: "Open Tables to review recognized figures and their explanations. Open Definitions to find meanings and where they appear.",
              outcome: "A table’s explanation appears beside the original source page. You can optionally look up missing meanings online.",
              tip: "Always check a comparison of figures against the original table.", symbol: "tablecells"),
        .init(id: 10, group: "Getting ready", title: "Ask questions and save findings",
              action: "Ask a focused question in Document chat. Select the star beside a finding to add it to My selection.",
              outcome: "Answers may include source links. You can find saved findings in My selection.",
              tip: "Check every answer using its source links. Chats and your selection are saved with the work document.", symbol: "bubble.left.and.bubble.right"),
        .init(id: 11, group: "Getting ready", title: "Export a PDF",
              action: "Choose Export, select the sections you want, and check the title and filename before saving the PDF.",
              outcome: "The export can include the summary, findings, questions, table explanations, abbreviations, and sources.",
              tip: "An export is a shareable PDF. Save a work document with ⌘S to continue later with your results and selection.", symbol: "square.and.arrow.up")
    ]
}

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let staticPreview: Bool
    private var reduceMotion: Bool { staticPreview || systemReduceMotion }
    @State private var step = 0
    @State private var demoPhase = 0
    @State private var replayCount = 0
    @State private var playbackStarted = Date()

    init(initialStep: Int = 0, staticPreview: Bool = false) {
        self.staticPreview = staticPreview
        _step = State(initialValue: min(max(initialStep, 0), TutorialStep.all.count - 1))
    }

    private var current: TutorialStep { TutorialStep.all[step] }
    private var playbackKey: String { "\(step)-\(replayCount)-\(reduceMotion)" }
    private var demoCaption: String { TutorialDemo.caption(step: step, phase: demoPhase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                Text(UIStrings.text("Stap \(step + 1) van \(TutorialStep.all.count)"))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Text("· " + current.group)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    stepMenuSection("Getting started", range: 0..<4)
                    stepMenuSection("Reading", range: 4..<9)
                    stepMenuSection("Getting ready", range: 9..<12)
                } label: {
                    Label(UIStrings.text("Kies stap"), systemImage: "list.number")
                }
                .focusToolbarMenu()
                .help(UIStrings.text("Rechtstreeks naar een stap gaan"))
            }
            ProgressView(value: Double(step + 1), total: Double(TutorialStep.all.count))
                .tint(SPTheme.accent)

            HStack(alignment: .top, spacing: 18) {
                previewColumn
                    .frame(width: 492)
                instructionCard
                    .id(step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(22)
        .frame(width: 900, height: 640)
        .background(SPTheme.background)
        .task(id: playbackKey) { await playDemo() }
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(UIStrings.text("Zo werkt Foliance"))
                    .font(.title2.bold())
                Text(UIStrings.text("Een rondleiding met fictieve voorbeelden · geen PDF of AI-model nodig"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(UIStrings.text("Sluiten"), systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(FocusToolbarActionStyle())
                .keyboardShortcut(.cancelAction)
                .help(UIStrings.text("Rondleiding sluiten"))
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            TutorialActualPreview(step: step, phase: demoPhase,
                                  playbackStarted: playbackStarted,
                                  reduceMotion: reduceMotion)
                .frame(height: 382)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Text(UIStrings.text(demoCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel((reduceMotion ? UIStrings.text("Stilstaand voorbeeld") + ": " : "") + UIStrings.text(demoCaption))
                if !reduceMotion {
                    Button {
                        demoPhase = 0
                        replayCount += 1
                    } label: {
                        Label(UIStrings.text("Opnieuw"), systemImage: "arrow.clockwise")
                    }
                    .font(.caption)
                    .disabled(demoPhase < 3)
                    .help(UIStrings.text("Voorbeeld opnieuw afspelen"))
                }
            }
            .frame(minHeight: 30)
        }
    }

    private var instructionCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: current.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(SPTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(SPTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    Text(current.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }

                instructionSection("DO THIS", text: current.action, symbol: "hand.tap")
                instructionSection("WHAT YOU SEE", text: current.outcome, symbol: "checkmark.circle")

                Label {
                    Text(current.tip)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(SPTheme.accent)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()
                Text(UIStrings.text("Dit voorbeeld verandert je documenten, analyse en instellingen niet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(0.07))
        }
    }

    private func instructionSection(_ heading: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(UIStrings.text(heading), systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(SPTheme.accent)
            Text(UIStrings.text(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                move(to: step - 1)
            } label: {
                Label(UIStrings.text("Vorige"), systemImage: "chevron.left")
            }
            .disabled(step == 0)

            Spacer()

            if step < TutorialStep.all.count - 1 {
                Button {
                    move(to: step + 1)
                } label: {
                    Label(UIStrings.text("Volgende"), systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FocusPrimaryButtonStyle())
                .tint(SPTheme.accent)
            } else {
                Button {
                    dismiss()
                } label: {
                    Label(UIStrings.text("Rondleiding afronden"), systemImage: "checkmark")
                }
                .buttonStyle(FocusPrimaryButtonStyle())
                .tint(SPTheme.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private func stepMenuSection(_ title: String, range: Range<Int>) -> some View {
        Section(UIStrings.text(title)) {
            ForEach(range, id: \.self) { index in
                Button {
                    move(to: index)
                } label: {
                    if index == step {
                        Label("\(index + 1). \(UIStrings.text(TutorialStep.all[index].title))", systemImage: "checkmark")
                    } else {
                        Text("\(index + 1). \(UIStrings.text(TutorialStep.all[index].title))")
                    }
                }
            }
        }
    }

    @MainActor private func playDemo() async {
        if reduceMotion {
            demoPhase = 3
            return
        }
        demoPhase = 0
        playbackStarted = Date()
        while demoPhase < 3 {
            let delays: [UInt64] = [1_150_000_000, 1_150_000_000, 1_350_000_000]
            do { try await Task.sleep(nanoseconds: delays[demoPhase]) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.28)) {
                demoPhase += 1
            }
        }
    }

    private func move(to target: Int) {
        guard TutorialStep.all.indices.contains(target) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            demoPhase = reduceMotion ? 3 : 0
            step = target
        }
    }
}

enum TutorialDemo {
    static func caption(step: Int, phase: Int) -> String {
        let captions: [[String]] = [
            ["Drop the PDF in the start area", "Release the PDF over the area", "Foliance reads text and tables", "Analysis starts automatically"],
            ["Choose an analysis provider", "Apple Intelligence is the default", "Review optional cloud choices", "Cloud analysis requires consent"],
            ["Choose a reading profile", "Point to a profile", "The profile is selected", "Optionally add a reference document"],
            ["Review analysis status", "Processing is getting ready", "Track progress and time remaining", "Available results appear"],
            ["Read the document summary", "Point to Expanded summary", "Open the expanded summary", "Read the explanation for each PDF page"],
            ["Review source passages in Overview", "Choose the Costs section", "Financial findings appear", "Each finding links to a source"],
            ["Choose a finding", "Select the card text", "The PDF jumps to page 4", "The related passage is highlighted"],
            ["Point to text in the PDF", "Drag across the text", "Release to summarize the selection", "The passage explanation appears"],
            ["Open Search or press ⌘F", "Type reading room", "Search results appear", "Open a result at its source"],
            ["Review the recognized table", "Open the Tables section", "Read the explanation and source page", "Open Definitions for terms"],
            ["Open a finding", "Choose Ask a question", "Document chat opens with your question", "Read the answer and source link"],
            ["Choose Export", "Check the title and filename", "Choose the sections", "Review the export before saving"]
        ]
        guard captions.indices.contains(step) else { return "Example ready" }
        return captions[step][min(max(phase, 0), 3)]
    }
}
