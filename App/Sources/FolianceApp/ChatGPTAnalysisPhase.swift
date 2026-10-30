import Foundation

enum ChatGPTAnalysisPhase: String, CaseIterable, Equatable, Sendable {
    case points
    case summary
    case highlights

    var title: String {
        switch self {
        case .points: "Punten"
        case .summary: "Documentsamenvatting"
        case .highlights: "Bronpassages"
        }
    }

    var remainingPhases: [Self] {
        guard let index = Self.allCases.firstIndex(of: self) else { return [] }
        return Array(Self.allCases[index...])
    }
}

enum WorkspaceAnalysisAdmission {
    static func canStart(busy: Bool, exporting: Bool, switchingModel: Bool) -> Bool {
        !busy && !exporting && !switchingModel
    }
}

struct ChatGPTModelChoice: Equatable, Sendable {
    enum Routing: String, Sendable, Hashable { case single, orchestrated }

    var routing: Routing
    var orchestratorModel: String
    var orchestratorEffort: String
    var workerModel: String
    var workerEffort: String

    mutating func normalize(using catalog: [ChatGPTModel]) {
        if let model = catalog.first(where: { $0.id == orchestratorModel }) {
            orchestratorEffort = Self.normalized(effort: orchestratorEffort, for: model)
        }
        if let model = catalog.first(where: { $0.id == workerModel }) {
            workerEffort = Self.normalized(effort: workerEffort, for: model)
        }
    }

    func encoded(using catalog: [ChatGPTModel]) -> String? {
        guard let main = catalog.first(where: { $0.id == orchestratorModel }),
              Self.valid(effort: orchestratorEffort, for: main),
              Self.valid(slug: orchestratorModel) else { return nil }
        guard routing == .orchestrated else {
            return AIConfiguration.chatGPTModel(orchestratorModel, effort: orchestratorEffort)
        }
        guard let worker = catalog.first(where: { $0.id == workerModel }),
              Self.valid(effort: workerEffort, for: worker), Self.valid(slug: workerModel) else { return nil }
        return AIConfiguration.chatGPTJob(orchestrator: orchestratorModel, effort: orchestratorEffort,
                                          worker: workerModel, workerEffort: workerEffort)
    }

    static func valid(slug: String) -> Bool {
        !slug.isEmpty && slug.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func valid(effort: String, for model: ChatGPTModel) -> Bool {
        model.reasoningEfforts.isEmpty ? effort == "auto" : model.reasoningEfforts.contains(effort)
    }

    private static func normalized(effort: String, for model: ChatGPTModel) -> String {
        guard !model.reasoningEfforts.isEmpty else { return "auto" }
        if model.reasoningEfforts.contains(effort) { return effort }
        return model.reasoningEfforts.contains("medium") ? "medium" : model.reasoningEfforts[0]
    }
}

@MainActor
enum ChatGPTModelSwitchDrain {
    /// Never starts the replacement workflow until the cancelled workflow has fully returned.
    static func cancelDrainAndRestart(_ previous: Task<Void, Never>,
                                      isCurrent: @MainActor () -> Bool,
                                      restart: @MainActor () async -> Void) async {
        previous.cancel()
        await previous.value
        guard isCurrent() else { return }
        await restart()
    }
}
