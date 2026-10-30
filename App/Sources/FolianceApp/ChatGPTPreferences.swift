import Foundation

/// Persistent ChatGPT model choices. Catalog reads never modify these values;
/// only initial defaulting and an explicit user model selection may do so.
enum ChatGPTPreferences {
    static let modeKey = "chatGPTRoutingMode"
    static let modelKey = "chatGPTModel"
    static let effortKey = "chatGPTReasoning"
    static let workerModelKey = "chatGPTSubagentModel"
    static let workerEffortKey = "chatGPTSubagentReasoning"

    static let defaultOrchestrator = "gpt-5.4-mini"
    static let defaultWorker = "gpt-5.4-mini"
    static let defaultEffort = "auto"

    static func mode(defaults: UserDefaults) -> AIConfiguration.ChatGPTMode {
        if let stored = defaults.string(forKey: modeKey),
           let value = AIConfiguration.ChatGPTMode(rawValue: stored) {
            return value
        }

        if defaults.string(forKey: workerModelKey).map({ !$0.isEmpty }) == true {
            return .orchestrated
        }
        return .single
    }

    /// Initializes only absent preferences. It determines the mode before adding
    /// missing worker defaults so a legacy main-only choice stays single-model.
    static func initializeDefaults(defaults: UserDefaults) {
        let inferredMode = mode(defaults: defaults)
        if defaults.object(forKey: modeKey) == nil ||
            AIConfiguration.ChatGPTMode(rawValue: defaults.string(forKey: modeKey) ?? "") == nil {
            defaults.set(inferredMode.rawValue, forKey: modeKey)
        }

        if defaults.string(forKey: modelKey) == nil { defaults.set(defaultOrchestrator, forKey: modelKey) }
        if defaults.string(forKey: effortKey) == nil { defaults.set(defaultEffort, forKey: effortKey) }
        if let savedWorker = defaults.string(forKey: workerModelKey), !savedWorker.isEmpty {
            // Keep any saved worker identifier, including one absent from the catalog.
        } else {
            defaults.set(defaultWorker, forKey: workerModelKey)
        }
        if defaults.string(forKey: workerEffortKey) == nil { defaults.set(defaultEffort, forKey: workerEffortKey) }
    }

    static func normalizeEffortAfterExplicitModelChoice(current: String, available: [String]) -> String {
        guard !available.isEmpty else { return "auto" }
        if available.contains(current) { return current }
        return ["high", "medium", "low", "xhigh", "max", "auto", "none"].first(where: available.contains)
            ?? available[0]
    }

    static func modelIsAvailable(_ modelID: String, catalogIDs: [String]) -> Bool {
        catalogIDs.contains(modelID)
    }
}
