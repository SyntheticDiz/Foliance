import Foundation

enum ProcessingStageState: Equatable {
    case ready
    case active
    case issue
    case pending
}

struct ProcessingPresentation {
    enum Stage: String, CaseIterable {
        case document = "Document lezen"
        case committee = "Gerichte beoordeling"
        case points = "Punten"
        case summary = "Samenvatting"
        case highlights = "Kernselectie"
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
        primaryStatus = busy ? (active.map(Self.primaryLabel(for:)) ?? "Verwerking bezig")
            : (completed ? "Document klaar" : "Verwerking vraagt aandacht")

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
        if value.hasPrefix("voorbereiding voor ") { return .committee }
        if value.hasPrefix("pdf inladen") || value.hasPrefix("pdf lezen") { return .document }
        if value.hasPrefix("kernpunten beoordelen") { return .highlights }
        if value.hasPrefix("document samenvatten") || value.hasPrefix("documentsamenvatting samenvoegen") ||
            value.hasPrefix("hoofdpunten samenvoegen") { return .summary }
        if value.hasPrefix("alinea ") || value.hasPrefix("alineapunten:") ||
            value.hasPrefix("neutrale samenvattingspunten maken") ||
            value.hasPrefix("vergelijken met referentiedocument") ||
            value.hasPrefix("programmapassages vergelijken") || value.hasPrefix("samenhang controleren") ||
            value.hasPrefix("bronnen controleren") || value.hasPrefix("ai-analyse") {
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
        case .document: "Document lezen"
        case .committee: "Gerichte beoordeling"
        case .points: "Punten samenstellen"
        case .summary: "Samenvatting samenstellen"
        case .highlights: "Kernselectie samenstellen"
        }
    }
}

