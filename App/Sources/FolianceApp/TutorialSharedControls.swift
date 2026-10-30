import SwiftUI

/// Controls used by both the workbench and its isolated tutorial example.
struct ProcessingModePicker: View {
    @Binding var compareProgram: Bool
    var disabled = false

    var body: some View {
        Menu {
            Picker(UIStrings.text("Leesdoel"), selection: $compareProgram) {
                Text(UIStrings.text("Documentsamenvatting")).tag(false)
                Text(UIStrings.text("Vergelijk met referentiedocument")).tag(true)
            }
        } label: {
            Text(UIStrings.text(compareProgram ? "Vergelijk met referentiedocument" : "Documentsamenvatting"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .focusToolbarMenu()
        .disabled(disabled)
        .accessibilityLabel(UIStrings.text("Leesdoel"))
        .tutorialTarget("mode")
    }
}

struct PDFImportCard: View {
    let busy: Bool
    let targeted: Bool
    let addPDF: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(targeted ? SPTheme.accent : Color.secondary)
            Text(UIStrings.text(busy ? "Pdf inladen…" : "Sleep je pdf hierheen")).font(.title2.bold())
            if busy { ProgressView() }
            else {
                Button(UIStrings.text("Pdf toevoegen…"), systemImage: "plus") { addPDF() }
                    .buttonStyle(FocusPrimaryButtonStyle())
                    .tint(SPTheme.accent)
                    .controlSize(.regular)
            }
            Text(UIStrings.text("Eén pdf met leesbare tekst")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(40).frame(maxWidth: .infinity, minHeight: 260)
        .background(targeted ? SPTheme.accent.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(targeted ? SPTheme.accent : Color.secondary.opacity(0.2),
                              style: targeted ? StrokeStyle(lineWidth: 2, dash: [7, 5]) : StrokeStyle(lineWidth: 1))
        }
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .tutorialTarget("import")
    }
}

struct AnalysisControlRow: View {
    @ObservedObject var workspace: SimpleWorkspace
    let disabled: Bool
    var stopTitle = "Stop analyse"
    var showsCompletionSummary = true
    let action: () -> Void
    var demoRemaining: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Label(UIStrings.text(workspace.busy ? stopTitle : workspace.canResume ? "Hervat ontbrekende onderdelen" : workspace.analyzed ? "Vernieuw analyse" : "Start analyse"),
                      systemImage: workspace.busy ? "stop.fill" : "play.fill")
            }
            .modifier(GlassActionStyle(prominent: workspace.busy || workspace.canResume || !workspace.analyzed,
                                       size: workspace.busy ? .large : .regular))
            .disabled(disabled)
            .tutorialTarget("start")
            if workspace.canCancelExport {
                Button { workspace.cancelExport() } label: {
                    Label(UIStrings.text("Stop exporteren"), systemImage: "stop.fill")
                }
                .buttonStyle(FocusSecondaryButtonStyle())
                .accessibilityIdentifier("cancel-export")
            }
            if showsCompletionSummary || workspace.busy {
            VStack(alignment: .leading, spacing: 4) {
                Text(UIStrings.text(workspace.completionTitle)).font(.callout.weight(.medium)).lineLimit(2)
                if workspace.busy {
                    ProgressView(value: workspace.progress.fraction).frame(maxWidth: 360)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("≈ \(workspace.progress.percent)% · " + (demoRemaining ?? workspace.progress.remaining(now: context.date)))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if !workspace.busy && workspace.analyzed {
                    Text("\(workspace.insights.count) " + UIStrings.text("aandachtspunten") + " · \(workspace.keyPoints.count) " + UIStrings.text("kernpunten"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            }
        }
    }
}

struct PDFSelectionActionButton: View {
    let disabled: Bool
    let waitingForAnalysis: Bool
    let action: () -> Void
    var addChosen: (() -> Void)? = nil
    var addDisabled = true
    var alreadyAdded = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                summarizeButton
                if let addChosen { chosenButton(addChosen) }
            }.accessibilityIdentifier("selection-actions-inline")
            if let addChosen {
                Menu {
                    summarizeButton
                    chosenButton(addChosen)
                } label: {
                    Label(UIStrings.text(alreadyAdded ? "Opgenomen in Mijn selectie" : "Selectieacties"),
                          systemImage: alreadyAdded ? "checkmark" : "text.quote").foregroundStyle(Color.primary)
                }.focusMenu().accessibilityIdentifier("selection-actions-menu")
            } else {
                summarizeButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("selection-actions-container")
    }

    private var summarizeButton: some View {
        Button(UIStrings.text("Vat selectie samen"), systemImage: "text.alignleft", action: action)
            .buttonStyle(FocusPrimaryButtonStyle())
            .disabled(disabled)
            .help(waitingForAnalysis ? "Wait for analysis to finish or stop it first." : "Summarize only the selected text")
            .tutorialTarget("selection")
    }

    private func chosenButton(_ action: @escaping () -> Void) -> some View {
        Button(UIStrings.text(alreadyAdded ? "Opgenomen in Mijn selectie" : "Opnemen in samenvatting"),
               systemImage: alreadyAdded ? "checkmark" : "plus", action: action)
            .buttonStyle(FocusSecondaryButtonStyle())
            .disabled(addDisabled || alreadyAdded)
            .help(UIStrings.text(alreadyAdded ? "Passage staat in Mijn selectie" : "Bewaar deze tekst letterlijk in Mijn selectie"))
            .accessibilityLabel(UIStrings.text(alreadyAdded ? "Opgenomen in Mijn selectie" : "Opnemen in samenvatting"))
    }
}
