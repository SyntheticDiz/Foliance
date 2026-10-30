import SwiftUI

struct ProcessingStatusView: View {
    @ObservedObject var workspace: SimpleWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(UIStrings.text("Analysis status")).font(.headline)
                Spacer()
                Text(UIStrings.text(workspace.activeScope)).font(.caption)
                if !workspace.activeModel.isEmpty { Text(providerLabel).font(.caption).foregroundStyle(.secondary) }
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
                DisclosureGroup(UIStrings.text("Model details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current choice: \(AIConfiguration.label(workspace.activeModel))")
                        Text("Findings: \(workspace.analysisModel.map(AIConfiguration.label) ?? "Not recorded yet")")
                        Text("Document overview: \(workspace.summaryModel.map(AIConfiguration.label) ?? "Not recorded yet")")
                        Text("Source passages: \(workspace.highlightModel.map(AIConfiguration.label) ?? "Not recorded yet")")
                    }.font(.caption).textSelection(.enabled)
                }.font(.caption)
            }
        }.padding(12).background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var providerLabel: String {
        if AIConfiguration.isChatGPT(workspace.activeModel) {
            return AIConfiguration.usesChatGPTPlan(workspace.activeModel) ? "ChatGPT plan · online" : "OpenAI API · online"
        }
        return "Apple Intelligence · on-device"
    }
    @ViewBuilder private var recovery: some View {
        if workspace.canResume { Button(UIStrings.text("Resume missing sections")) { workspace.resumeMissing() } }
        if workspace.summaryError != nil { Button(UIStrings.text("Retry overview")) { workspace.retrySummary() } }
        if !workspace.keyPointIssues.isEmpty { Button(UIStrings.text("Retry source excerpts")) { workspace.retryHighlights() } }
        if workspace.analysisState == .incomplete || workspace.analysisState == .failed || workspace.analysisState == .cancelled { Button(UIStrings.text("Retry points")) { workspace.retryIncompleteAnalysis() } }
    }
    @ViewBuilder private var stages: some View {
        stage("Read PDF", ready: workspace.document != nil, issue: !workspace.layoutNotice.isEmpty)
        if workspace.meetingPurpose != .raad {
            stage(workspace.meetingPurpose.title,
                  ready: workspace.committeeReviews[workspace.meetingPurpose.rawValue]?.complete == true,
                  issue: workspace.committeeReviewError != nil, active: workspace.committeeReviewBusy)
        }
        stage("Document overview", ready: workspace.documentSummary != nil, issue: workspace.summaryError != nil)
        stage("Key passages", ready: workspace.keyPointsReady, issue: !workspace.keyPointIssues.isEmpty)
        stage("Findings", ready: workspace.analyzed && workspace.analysisState != .running, issue: [.needsProgram, .incomplete, .failed, .cancelled].contains(workspace.analysisState))
    }
    private func stage(_ title: String, ready: Bool, issue: Bool, active: Bool = false) -> some View {
        Label(title + ": " + (issue ? "Needs attention" : ready ? "Ready" : active ? "In progress" : "Not started"),
              systemImage: issue ? "exclamationmark.triangle" : ready ? "checkmark.circle" : "circle")
    }
}
