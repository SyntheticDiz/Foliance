import SwiftUI

struct WorkspaceStatusStripPresentation {
    let showsCommittee: Bool
    let analysisIncomplete: Bool
    let committeeBusy: Bool
    let showsStopCommitteeReview: Bool
    let showsAssessmentAction: Bool
    let assessmentActionInStrip: Bool
    let assessmentActionInDetails: Bool
    let assessmentActionTitle: String?
    let assessmentActionEnabled: Bool
    let showsCategorizationAction: Bool
    let categorizationActionEnabled: Bool
    let committeeNeedsAttention: Bool
    let hasCriticalSourceWarning: Bool
    let criticalSourcePages: [Int]
    let sourceIssueCount: Int

    static func make(purpose: MeetingPurpose, analysisIncomplete: Bool, committeeBusy: Bool,
                     review: CommitteeAssessmentService.Review?, reviewError: String?,
                     selectedModel: String, canStartReview: Bool, canCategorize: Bool,
                     sourceIssues: [WorkspaceSourceIssue]) -> Self {
        let showsCommittee = purpose != .raad
        let reviewIncomplete = review?.complete != true
        let assessmentActionTitle = showsCommittee ? CommitteeFailurePresentation.actionTitle(review: review, model: selectedModel) : nil
        let needsCategorization = showsCommittee && !committeeBusy && review?.entries.contains(where: { $0.categoryModel == nil }) == true
        let criticalPages = Array(Set(sourceIssues.filter { $0.kind == .unreadable }.map(\.page))).sorted()
        return Self(showsCommittee: showsCommittee, analysisIncomplete: analysisIncomplete, committeeBusy: committeeBusy,
                    showsStopCommitteeReview: showsCommittee && committeeBusy,
                    showsAssessmentAction: showsCommittee && !committeeBusy,
                    assessmentActionInStrip: false,
                    assessmentActionInDetails: showsCommittee && !committeeBusy,
                    assessmentActionTitle: assessmentActionTitle,
                    assessmentActionEnabled: canStartReview,
                    showsCategorizationAction: needsCategorization,
                    categorizationActionEnabled: canCategorize,
                    committeeNeedsAttention: showsCommittee && !committeeBusy && (reviewError != nil || reviewIncomplete),
                    hasCriticalSourceWarning: !criticalPages.isEmpty,
                    criticalSourcePages: criticalPages,
                    sourceIssueCount: sourceIssues.count)
    }
}

/// Makes the complete disclosure header row the keyboard and pointer target.
/// Using a single native Button avoids a separate chevron action and preserves
/// the DisclosureGroup's existing expansion binding.
struct FullRowDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Spacer(minLength: 8)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(UIStrings.text("Expand or collapse the contents"))

            if configuration.isExpanded {
                configuration.content
                    .padding(.top, 8)
            }
        }
    }
}

struct WorkspaceStatusBanner: View {
    @ObservedObject var workspace: SimpleWorkspace
    @Binding var showingAnalysisOverview: Bool
    let showPage: (Int) -> Void
    let showSource: (Int, String) -> Void
    let showTable: (String) -> Void

    private var sourceIssues: [WorkspaceSourceIssue] {
        WorkspaceSourceIssue.make(readings: workspace.document?.readings ?? [])
    }
    private var selectedReview: CommitteeAssessmentService.Review? {
        workspace.committeeReviews[workspace.meetingPurpose.rawValue]
    }
    private var strip: WorkspaceStatusStripPresentation {
        .make(purpose: workspace.meetingPurpose, analysisIncomplete: workspace.baseAnalysisIncomplete,
              committeeBusy: workspace.committeeReviewBusy, review: selectedReview,
              reviewError: workspace.committeeReviewError, selectedModel: AIConfiguration.selectedModel,
              canStartReview: workspace.canStartCommitteeReview,
              canCategorize: workspace.canCategorizeCommitteeReview, sourceIssues: sourceIssues)
    }

    var body: some View {
        Group {
            if showsCompactStatus || showingAnalysisOverview {
                if showingAnalysisOverview {
                    VStack(alignment: .leading, spacing: 9) {
                        statusContent
                        ProcessingStatusView(workspace: workspace)
                        if hasDetails { details }
                    }
                    .padding(12)
                    .readingSurface()
                } else {
                    statusContent
                }
            }
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            if workspace.busy || workspace.committeeReviewBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UIStrings.text(compactStatusTitle))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    if workspace.committeeReviewBusy && strip.showsCommittee {
                        Button(UIStrings.text("Stop assessment")) { workspace.stopCommitteeReview() }
                            .buttonStyle(FocusSecondaryButtonStyle()).controlSize(.small)
                    }
                }
            }
            warningRows
        }
    }

    private var showsCompactStatus: Bool {
        workspace.busy || workspace.committeeReviewBusy || compactWarningCount > 0
    }

    private var compactStatusTitle: String {
        if workspace.committeeReviewBusy {
            let phase = workspace.committeeReviewStatus.hasPrefix("Onderwerpen") ? "Categorizing topics" : "Profile review"
            return "\(phase) · \(workspace.committeeReviewCompleted)/\(workspace.committeeReviewTotal)"
        }
        return "Base analysis in progress"
    }

    @ViewBuilder private var warningRows: some View {
        if compactWarningCount > 0 {
            HStack(spacing: 14) { warningButtonsContent }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var warningButtonsContent: some View {
        if strip.hasCriticalSourceWarning {
            warningButton(compactCriticalSourceTitle, symbol: "exclamationmark.triangle.fill")
        }
        if strip.committeeNeedsAttention {
            warningButton("Profile review incomplete", symbol: "person.3.fill")
        }
        if !strip.hasCriticalSourceWarning && !strip.committeeNeedsAttention && strip.showsCategorizationAction {
            warningButton("Topic grouping incomplete", symbol: "square.grid.2x2")
        }
        if compactWarningCount == 1 && !strip.hasCriticalSourceWarning && !strip.committeeNeedsAttention && !strip.showsCategorizationAction {
            warningButton(workspace.baseAnalysisIncomplete || workspace.summaryError != nil || !workspace.analysisIssues.isEmpty ||
                          !workspace.keyPointIssues.isEmpty || !workspace.citationWarning.isEmpty || workspace.error != nil
                          ? "Base analysis incomplete" : "Source checks need attention",
                          symbol: "exclamationmark.triangle.fill")
        }
    }

    private func warningButton(_ title: String, symbol: String) -> some View {
        Button { showingAnalysisOverview = true } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(.orange).accessibilityHidden(true)
                Text(UIStrings.text(title)).font(.caption).lineLimit(1).multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(UIStrings.text("Show the related status details and recovery actions"))
    }

    private var compactWarningCount: Int {
        var count = 0
        if strip.hasCriticalSourceWarning { count += 1 }
        if strip.committeeNeedsAttention { count += 1 }
        if !strip.hasCriticalSourceWarning && !strip.committeeNeedsAttention && strip.showsCategorizationAction { count += 1 }
        if count == 0 && (workspace.baseAnalysisIncomplete || workspace.summaryError != nil || !workspace.analysisIssues.isEmpty ||
            !workspace.keyPointIssues.isEmpty || !workspace.citationWarning.isEmpty || workspace.error != nil ||
            !workspace.layoutNotice.isEmpty || strip.sourceIssueCount > 0) { count = 1 }
        return count
    }

    private var compactCriticalSourceTitle: String {
        strip.criticalSourcePages.count == 1
            ? "PDF page \(strip.criticalSourcePages[0]) was not included"
            : "\(strip.criticalSourcePages.count) pages were not included"
    }

    private var hasDetails: Bool {
        workspace.analyzed || !sourceIssues.isEmpty || !workspace.layoutNotice.isEmpty || workspace.baseAnalysisIncomplete ||
        workspace.summaryError != nil || !workspace.analysisIssues.isEmpty || !workspace.keyPointIssues.isEmpty ||
        !workspace.citationWarning.isEmpty || workspace.error != nil ||
        (strip.showsCommittee && (workspace.committeeReviewError != nil || selectedReview != nil || strip.committeeNeedsAttention))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if workspace.analyzed {
                Text("\(workspace.insights.count) \(workspace.insights.count == 1 ? "document finding" : "document findings") · \(workspace.keyPoints.count) \(workspace.keyPoints.count == 1 ? "key finding" : "key findings")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !workspace.layoutNotice.isEmpty || !sourceIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(UIStrings.text("PDF reading and source checks")).font(.caption.bold())
                    if !workspace.layoutNotice.isEmpty {
                        Text(UIStrings.text(workspace.layoutNotice)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    ForEach(sourceIssues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Button(UIStrings.text(issue.title)) { showPage(issue.page) }.buttonStyle(FocusQuietActionStyle())
                            Text(UIStrings.text(issue.notice)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            ForEach(workspace.tables.filter { $0.recognizedWithOCR == true && $0.pages.contains(issue.page) }) { table in
                                Button(UIStrings.text("Check table") + " · " + table.title) { showTable(table.id) }.buttonStyle(FocusQuietActionStyle())
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }
            if workspace.baseAnalysisIncomplete || workspace.summaryError != nil || !workspace.analysisIssues.isEmpty ||
                !workspace.keyPointIssues.isEmpty || !workspace.citationWarning.isEmpty || workspace.error != nil {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UIStrings.text("Base analysis")).font(.caption.bold())
                    Text(analysisStateLabel(workspace.analysisState)).font(.caption).foregroundStyle(.secondary)
                    if let error = workspace.error { Text(UIStrings.text(error)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if let error = workspace.summaryError { Text(UIStrings.text(error)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if !workspace.analysisIssues.isEmpty { Text(UIStrings.text(workspace.analysisIssues)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if !workspace.keyPointIssues.isEmpty { Text(UIStrings.text(workspace.keyPointIssues)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if !workspace.citationWarning.isEmpty { Text(UIStrings.text(workspace.citationWarning)).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }
            }
            if strip.showsCommittee {
                committeeDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    @ViewBuilder private var committeeDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(UIStrings.text("Focused review")).font(.caption.bold())
            if workspace.committeeReviewBusy {
                Text(UIStrings.text(workspace.committeeReviewStatus) + " \(workspace.committeeReviewCompleted)/\(workspace.committeeReviewTotal)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let error = workspace.committeeReviewError {
                Text(UIStrings.text(error)).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let review = selectedReview {
                if review.model != AIConfiguration.selectedModel {
                    Text(UIStrings.text("This review used a different model. Choosing the current model starts a new review; previous results remain saved."))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if !review.complete {
                    Label(UIStrings.text("Profile review incomplete; unassessed passages remain available."), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                    CommitteeFailureDetails(review: review, showSource: showSource)
                }
            } else {
                Text(UIStrings.text("No profile review is available yet. The source and existing analysis remain available."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if strip.showsAssessmentAction, let title = strip.assessmentActionTitle {
                Button(UIStrings.text(title)) { workspace.startCommitteeReview(model: AIConfiguration.selectedModel) }
                    .buttonStyle(FocusSecondaryButtonStyle()).disabled(!strip.assessmentActionEnabled)
            }
            if strip.showsCategorizationAction {
                Button(UIStrings.text("Categorize by topic")) { workspace.categorizeCommitteeReview() }
                    .buttonStyle(FocusQuietActionStyle()).disabled(!strip.categorizationActionEnabled)
            }
        }
    }

}
