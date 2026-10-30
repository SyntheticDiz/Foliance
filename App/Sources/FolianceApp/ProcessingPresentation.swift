import Foundation

enum ProcessingStageState: Equatable {
    case ready
    case active
    case issue
    case pending
}

struct ProcessingPresentation {
    enum Stage: String, CaseIterable {
        case document = "Read document"
        case committee = "Profile review"
        case points = "Findings"
        case summary = "Document overview"
        case highlights = "Key passages"
    }

    let primaryStatus: String
    let activeStage: Stage?
    let stageStates: [Stage: ProcessingStageState]
    let stages: [Stage]

    init(status: String, busy: Bool, completed: Bool,
         documentReady: Bool, documentPresent: Bool, documentIssue: Bool,
         pointsReady: Bool, pointsIssue: Bool,
         summaryReady: Bool, summaryIssue: Bool,
         highlightsReady: Bool, highlightsIssue: Bool,
         committeeIncluded: Bool = false, committeeActive: Bool = false,
         committeeReady: Bool = false, committeeIssue: Bool = false) {
        let active = busy ? (committeeIncluded && committeeActive ? Stage.committee : Self.knownStage(for: status)) : nil
        stages = committeeIncluded ? [.document, .committee, .points, .summary, .highlights] : [.document, .points, .summary, .highlights]
        activeStage = active
        primaryStatus = busy ? (active.map(Self.primaryLabel(for:)) ?? "Processing")
            : (completed ? "Document ready" : "Processing needs attention")

        var states: [Stage: ProcessingStageState] = [
            .document: Self.state(ready: documentReady && documentPresent,
                                  issue: documentIssue,
                                  active: active == .document),
            .points: Self.state(ready: pointsReady, issue: pointsIssue, active: active == .points),
            .summary: Self.state(ready: summaryReady, issue: summaryIssue, active: active == .summary),
            .highlights: Self.state(ready: highlightsReady, issue: highlightsIssue, active: active == .highlights)
        ]
        if committeeIncluded {
            states[.committee] = Self.state(ready: committeeReady, issue: committeeIssue, active: active == .committee)
        }
        stageStates = states
    }

    static func knownStage(for status: String) -> Stage? {
        let value = status.lowercased()
        if value.hasPrefix("preparing profile review") || value.hasPrefix("reviewing profile") { return .committee }
        if value.hasPrefix("loading pdf") || value.hasPrefix("reading pdf") { return .document }
        if value.hasPrefix("reviewing key passages") { return .highlights }
        if value.hasPrefix("summarizing document") || value.hasPrefix("merging document overview") ||
            value.hasPrefix("merging key points") { return .summary }
        if value.hasPrefix("paragraph findings:") || value.hasPrefix("paragraph points:") ||
            value.hasPrefix("creating overview findings") ||
            value.hasPrefix("comparing with reference document") ||
            value.hasPrefix("checking source relationships") || value.hasPrefix("source checks") ||
            value.hasPrefix("ai analysis") {
            return .points
        }
        return nil
    }

    static func state(ready: Bool, issue: Bool, active: Bool) -> ProcessingStageState {
        if issue { return .issue }
        if ready { return .ready }
        if active { return .active }
        return .pending
    }

    private static func primaryLabel(for stage: Stage) -> String {
        switch stage {
        case .document: "Reading document"
        case .committee: "Reviewing profile"
        case .points: "Preparing findings"
        case .summary: "Preparing document overview"
        case .highlights: "Preparing key passages"
        }
    }
}

