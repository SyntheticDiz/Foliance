import SwiftUI

struct ProcessingStatusView: View {
    @ObservedObject var workspace: SimpleWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(UIStrings.text("Analyseoverzicht")).font(.headline)
                Spacer()
                Text(UIStrings.text(workspace.activeScope)).font(.caption)
                if !workspace.activeModel.isEmpty { Text(UIStrings.text("Apple Intelligence · lokaal")).font(.caption).foregroundStyle(.secondary) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { stages }
                VStack(alignment: .leading, spacing: 6) { stages }
            }.font(.caption)
            if workspace.busy {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(UIStrings.text(workspace.progress.activity(now: context.date))).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if !workspace.busy && !workspace.completionDetails.isEmpty {
                ScrollView {
                    Text(workspace.completionDetails.components(separatedBy: "\n\n")
                        .map { UIStrings.text($0) }.joined(separator: "\n\n"))
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 80)
                ViewThatFits(in: .horizontal) {
                    HStack { recovery }
                    VStack(alignment: .leading) { recovery }
                }.disabled(!workspace.canStartAnalysis)
            }
            if !workspace.activeModel.isEmpty {
                DisclosureGroup(UIStrings.text("Modeldetails")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIStrings.text("Huidige keuze: \(AIConfiguration.label(workspace.activeModel))"))
                        Text(UIStrings.text("Punten: \(workspace.analysisModel.map(AIConfiguration.label) ?? "Nog niet vastgelegd")"))
                        Text(UIStrings.text("Documentsamenvatting: \(workspace.summaryModel.map(AIConfiguration.label) ?? "Nog niet vastgelegd")"))
                        Text(UIStrings.text("Bronpassages: \(workspace.highlightModel.map(AIConfiguration.label) ?? "Nog niet vastgelegd")"))
                    }.font(.caption).textSelection(.enabled)
                }.font(.caption)
            }
        }.padding(12).background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var recovery: some View {
        if workspace.canResume { Button(UIStrings.text("Ontbrekende onderdelen herstellen")) { workspace.resumeMissing() } }
        if workspace.summaryError != nil { Button(UIStrings.text("Overzicht opnieuw")) { workspace.retrySummary() } }
        if !workspace.keyPointIssues.isEmpty { Button(UIStrings.text("Bronpassages opnieuw")) { workspace.retryHighlights() } }
        if workspace.analysisState == .incomplete || workspace.analysisState == .failed || workspace.analysisState == .cancelled { Button(UIStrings.text("Punten opnieuw")) { workspace.retryIncompleteAnalysis() } }
    }
    @ViewBuilder private var stages: some View {
        stage("PDF-tekst", ready: workspace.document != nil, issue: !workspace.layoutNotice.isEmpty)
        if workspace.meetingPurpose != .raad {
            stage(workspace.meetingPurpose.title,
                  ready: workspace.committeeReviews[workspace.meetingPurpose.rawValue]?.complete == true,
                  issue: workspace.committeeReviewError != nil, active: workspace.committeeReviewBusy)
        }
        stage("Overzicht", ready: workspace.documentSummary != nil, issue: workspace.summaryError != nil)
        stage("Bronpassages", ready: workspace.keyPointsReady, issue: !workspace.keyPointIssues.isEmpty)
        stage("Punten", ready: workspace.analyzed && workspace.analysisState != .running, issue: [.needsProgram, .incomplete, .failed, .cancelled].contains(workspace.analysisState))
    }
    private func stage(_ title: String, ready: Bool, issue: Bool, active: Bool = false) -> some View {
        Label(UIStrings.text(title) + ": " + UIStrings.text(issue ? "Vraagt aandacht" : ready ? "Gereed" : active ? "Bezig" : "Nog niet gereed"),
              systemImage: issue ? "exclamationmark.triangle" : ready ? "checkmark.circle" : "circle")
    }
}
