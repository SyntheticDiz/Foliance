import SwiftUI

struct ProcessingSplashView: View {
    @ObservedObject var workspace: SimpleWorkspace
    var onReturnToImport: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var completed: Bool { !workspace.busy && workspace.processingMessage == nil }
    private var presentation: ProcessingPresentation {
        ProcessingPresentation(
            status: workspace.status,
            busy: workspace.busy,
            completed: completed,
            documentReady: workspace.processingDocumentReady || !workspace.busy,
            documentPresent: workspace.document != nil,
            documentIssue: workspace.status.hasPrefix("Pdf inladen mislukt") ||
                (workspace.processingMessage != nil && workspace.document == nil),
            pointsReady: workspace.analyzed && workspace.analysisState != .running,
            pointsIssue: [.needsProgram, .incomplete, .failed, .cancelled].contains(workspace.analysisState) || !workspace.citationWarning.isEmpty,
            summaryReady: workspace.documentSummary != nil,
            summaryIssue: workspace.summaryError != nil,
            highlightsReady: workspace.keyPointsReady,
            highlightsIssue: !workspace.keyPointIssues.isEmpty,
            committeeIncluded: workspace.meetingPurpose != .raad,
            committeeActive: workspace.importCommitteeReviewActive,
            committeeReady: workspace.committeeReviews[workspace.meetingPurpose.rawValue]?.complete == true,
            committeeIssue: workspace.committeeReviewError != nil ||
                (workspace.processingDocumentReady && !workspace.committeeReviewBusy && workspace.meetingPurpose != .raad &&
                 workspace.committeeReviews[workspace.meetingPurpose.rawValue]?.complete != true))
    }

    var body: some View {
        VStack(spacing: 24) {
            ProcessingDocumentIllustration(scanning: workspace.busy, completed: completed)
                .frame(width: 190, height: 236)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(workspace.processingName).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(3)
                ZStack {
                    Text(UIStrings.text(presentation.primaryStatus) + (presentation.activeStage == .committee ? " · " + UIStrings.text(workspace.meetingPurpose.title) : "")).id(presentation.primaryStatus)
                        .font(.body).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).transition(.opacity)
                }
                .frame(height: 44)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: presentation.primaryStatus)
            }
            stageRow
            if workspace.processingMessage == nil {
                VStack(spacing: 10) {
                    ProgressView(value: workspace.busy ? workspace.progress.fraction : 1)
                        .tint(.secondary)
                        .accessibilityLabel(UIStrings.text("Voortgang") + ": " + UIStrings.text(presentation.primaryStatus))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: workspace.progress.fraction)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: completed)
                    HStack {
                        Text("\(workspace.busy ? workspace.progress.percent : 100)%").monospacedDigit()
                        Spacer()
                        if workspace.busy { Text(UIStrings.text(workspace.progress.remaining())) }
                    }.font(.callout).foregroundStyle(.secondary)
                }
            }
            if workspace.busy {
                if let count = progressCount {
                    Text(UIStrings.text(count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(UIStrings.text(workspace.processingDocumentReady ? "Stop en terug naar importeren" : "Annuleer import")) { onReturnToImport() }
                        .buttonStyle(FocusSecondaryButtonStyle())
                    if workspace.canSwitchChatGPTModel {
                        Button(UIStrings.text("Wissel AI-model…")) { workspace.presentChatGPTModelSwitch() }
                            .buttonStyle(FocusSecondaryButtonStyle())
                    }
                    if workspace.processingDocumentReady {
                    Button(UIStrings.text("Open document en resultaten")) { workspace.showInterimResults() }
                        .buttonStyle(FocusPrimaryButtonStyle())
                    }
                }.controlSize(.large)
            } else if completed {
                // Reserve the action's space so completion does not move the illustration.
                Button(UIStrings.text("Stop analyse")) {}.controlSize(.large).hidden().accessibilityHidden(true)
            } else if let message = workspace.processingMessage {
                ScrollView {
                    Text(message.components(separatedBy: "\n").map { UIStrings.text($0) }.joined(separator: "\n")).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 140)
                HStack(spacing: 12) {
                    Button(UIStrings.text("Terug naar importeren")) { onReturnToImport() }
                        .buttonStyle(FocusSecondaryButtonStyle())
                    if !workspace.showsWelcome && workspace.document != nil {
                        Button(UIStrings.text("Open document en resultaten")) { workspace.showProcessedResults() }
                            .buttonStyle(FocusPrimaryButtonStyle())
                    }
                }.controlSize(.large)
            }
            details
        }
        .frame(maxWidth: 460)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SPTheme.background)
    }

    private var stageRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { ForEach(presentation.stages, id: \.self) { stage in stageItem(stage).fixedSize(horizontal: true, vertical: false) } }
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    stageItem(.document)
                    if workspace.meetingPurpose != .raad { stageItem(.committee) }
                    stageItem(.points)
                }
                HStack(spacing: 10) { stageItem(.summary); stageItem(.highlights) }
            }
        }
        .font(.caption2)
        .accessibilityElement(children: .combine)
    }

    private func stageItem(_ stage: ProcessingPresentation.Stage) -> some View {
        let state = presentation.stageStates[stage] ?? .pending
        let symbol: String
        let label: String
        switch state {
        case .ready: symbol = "checkmark.circle.fill"; label = "Gereed"
        case .active: symbol = "circle.dashed"; label = "Bezig"
        case .issue: symbol = "exclamationmark.circle.fill"; label = "Aandacht"
        case .pending: symbol = "circle"; label = "Wacht"
        }
        return VStack(spacing: 2) {
            Label(UIStrings.text(stage.rawValue), systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(state == .issue ? Color.orange : state == .active ? Color.primary : Color.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(UIStrings.text(label)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(UIStrings.text(stage.rawValue) + ": " + UIStrings.text(label))
    }

    private var progressCount: String? {
        guard workspace.progress.phaseTotal > 0 else { return nil }
        let unit = workspace.progress.isMergingSummary ? "samenvoegingen" : "stappen"
        return "\(workspace.progress.phaseCompleted) van \(workspace.progress.phaseTotal) \(unit) gereed"
    }

    private var details: some View {
        DisclosureGroup(UIStrings.text("Details")) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    if !workspace.activeModel.isEmpty {
                        Text(UIStrings.text(AIConfiguration.label(workspace.activeModel)))
                    }
                    if workspace.importCommitteeReviewActive {
                        Text(UIStrings.text("Commissievoorbereiding") + " · " + UIStrings.text(workspace.meetingPurpose.title))
                    }
                    if let phase = workspace.analysisPhase {
                        Text(UIStrings.text("Huidige AI-fase: \(phase.title)"))
                    }
                    Text(UIStrings.text("Verstreken \(elapsed(now: context.date)) · \(requestStatus)"))
                    Text(UIStrings.text(workspace.status)).textSelection(.enabled)
                }
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption)
    }

    private func elapsed(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(workspace.progress.started)))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private var requestStatus: String {
        let progress = workspace.progress
        guard workspace.busy else { return completed ? "Verwerking afgerond" : "Verwerking vraagt aandacht" }
        return progress.phaseTotal > 0 && progress.phaseCompleted >= progress.phaseTotal
            ? "Aanvraagfase afronden" : "Wachten op of verwerken van aanvraag"
    }
}

private struct ProcessingDocumentIllustration: View {
    let scanning: Bool
    let completed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unfolded = false
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || !scanning)) { timeline in
            Canvas { context, size in
                let inset: CGFloat = 26
                let elapsed = max(0, timeline.date.timeIntervalSince(started))
                let cycle = max(0, elapsed - 0.85).truncatingRemainder(dividingBy: 4.8) / 4.8
                let pass = min(1, cycle / 0.8)
                let eased = pass * pass * (3 - 2 * pass)
                let scanY = 28 + (size.height - 56) * eased
                let scanningNow = scanning && !reduceMotion && elapsed > 0.85 && cycle < 0.8
                let scanOpacity = min(1, min(pass * 10, (1 - pass) * 10))
                for row in 0..<10 {
                    let width = (row == 3 || row == 7) ? size.width * 0.48 : size.width - inset * 2
                    let y = 38 + CGFloat(row) * 16
                    let reveal = reduceMotion || completed ? 1 : min(1, max(0, (elapsed - 0.15 - Double(row) * 0.04) / 0.24))
                    let smoothReveal = reveal * reveal * (3 - 2 * reveal)
                    let emphasis = scanningNow ? max(0, 1 - abs(y - scanY) / 32) * scanOpacity : 0
                    let rect = CGRect(x: inset, y: y, width: width * smoothReveal, height: 4)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.secondary.opacity((0.22 + emphasis * 0.3) * smoothReveal)))
                }
                if scanningNow {
                    // A small gradient gives a soft glow without a full-screen blur or redraw.
                    let glow = CGRect(x: 18, y: scanY - 12, width: size.width - 36, height: 24)
                    context.fill(Path(roundedRect: glow, cornerRadius: 8), with: .linearGradient(
                        Gradient(colors: [.clear, .secondary.opacity(0.12 * scanOpacity), .clear]),
                        startPoint: CGPoint(x: 0, y: scanY - 12), endPoint: CGPoint(x: 0, y: scanY + 12)))
                    let line = CGRect(x: 18, y: scanY, width: size.width - 36, height: 1.5)
                    context.fill(Path(roundedRect: line, cornerRadius: 0.75), with: .color(.secondary.opacity(0.55 * scanOpacity)))
                }
            }
        }
        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .medium)).foregroundStyle(.secondary)
                .background(SPTheme.surface, in: Circle())
                .padding(14).scaleEffect(completed ? 1 : 0.85).opacity(completed ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: completed)
        }
        .rotation3DEffect(.degrees(unfolded ? 0 : -45), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.3)
        .opacity(unfolded ? 1 : 0)
        .onAppear {
            started = Date()
            withAnimation(reduceMotion ? nil : .timingCurve(0.2, 0.75, 0.25, 1, duration: 0.75)) { unfolded = true }
        }
    }
}
