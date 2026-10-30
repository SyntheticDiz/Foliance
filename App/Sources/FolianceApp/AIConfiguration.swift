import Foundation

/// A model identifier captures provider and effort for the whole operation.
enum AIConfiguration {
    enum ChatGPTMode: String { case single, orchestrated }
    enum ChatGPTRole { case worker, orchestrator }

    static var selectedModel: String { selectedModel(defaults: .standard) }
    static func selectedModel(defaults: UserDefaults) -> String {
        if defaults.string(forKey: "localAIProvider") == "chatgpt" {
            let model = defaults.string(forKey: ChatGPTPlanPreferences.modelKey) ?? ChatGPTPlanPreferences.defaultOrchestrator
            let effort = defaults.string(forKey: ChatGPTPlanPreferences.effortKey) ?? ChatGPTPlanPreferences.defaultEffort
            if ChatGPTPlanPreferences.mode(defaults: defaults) == .orchestrated {
                let worker = defaults.string(forKey: ChatGPTPlanPreferences.workerModelKey) ?? ChatGPTPlanPreferences.defaultWorker
                let workerEffort = defaults.string(forKey: ChatGPTPlanPreferences.workerEffortKey) ?? ChatGPTPlanPreferences.defaultEffort
                return chatGPTJob(orchestrator: model, effort: effort, worker: worker, workerEffort: workerEffort) + ":plan"
            }
            return chatGPTPlanModel(model, effort: effort)
        }
        guard defaults.string(forKey: "localAIProvider") == "openai" else { return AppleAIService.modelID }
        let model = defaults.string(forKey: ChatGPTPreferences.modelKey) ?? ChatGPTPreferences.defaultOrchestrator
        let effort = defaults.string(forKey: ChatGPTPreferences.effortKey) ?? "auto"
        return chatGPTModel(model, effort: effort)
    }
    static func chatGPTMode(defaults: UserDefaults) -> ChatGPTMode {
        ChatGPTPreferences.mode(defaults: defaults)
    }
    static func setChatGPTMode(_ mode: ChatGPTMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: ChatGPTPreferences.modeKey)
    }
    static func chatGPTModel(_ slug: String, effort: String) -> String { "chatgpt:\(slug):\(effort)" }
    static func chatGPTPlanModel(_ slug: String, effort: String) -> String { chatGPTModel(slug, effort: effort) + ":plan" }
    static func usesChatGPTPlan(_ identifier: String) -> Bool { identifier.hasSuffix(":plan") && chatGPTSelection(identifier) != nil }
    private static func preservingBilling(_ identifier: String, from original: String) -> String {
        original.hasSuffix(":plan") ? identifier + ":plan" : identifier
    }
    static func chatGPTSelection(_ identifier: String) -> (model: String, effort: String)? {
        var parts = identifier.split(separator: ":", omittingEmptySubsequences: false)
        if parts.last == "plan" { parts.removeLast() }
        guard (parts.count == 3 || parts.count == 5), parts[0] == "chatgpt", !parts[1].isEmpty,
              parts[1].range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
              ["auto", "none", "low", "medium", "high", "xhigh", "max"].contains(String(parts[2])) else { return nil }
        if parts.count == 5 {
            guard chatGPTSelection("chatgpt:" + parts[3] + ":" + parts[4]) != nil else { return nil }
        }
        return (String(parts[1]), String(parts[2]))
    }
    static func chatGPTJob(orchestrator: String, effort: String, worker: String, workerEffort: String) -> String {
        chatGPTModel(orchestrator, effort: effort) + ":" + worker + ":" + workerEffort
    }
    static func orchestratorModel(_ job: String) -> String {
        guard let selection = chatGPTSelection(job) else { return job }
        return preservingBilling(chatGPTModel(selection.model, effort: selection.effort), from: job)
    }
    static func workerModel(_ job: String) -> String {
        guard isChatGPT(job) else { return job }
        var parts = job.split(separator: ":", omittingEmptySubsequences: false)
        if parts.last == "plan" { parts.removeLast() }
        return parts.count == 5 ? preservingBilling(chatGPTModel(String(parts[3]), effort: String(parts[4])), from: job) : job
    }
    static func isChatGPT(_ model: String) -> Bool { chatGPTSelection(model) != nil }
    static func label(_ model: String) -> String {
        guard let selection = chatGPTSelection(model) else { return "Apple Intelligence · On-Device" }
        let provider = usesChatGPTPlan(model) ? "ChatGPT plan" : "OpenAI API"
        if model.split(separator: ":").count == (usesChatGPTPlan(model) ? 6 : 5) {
            let worker = chatGPTSelection(workerModel(model))!
            return "\(provider) · \(selection.model) · \(selection.effort) · Online · Secondary model: \(worker.model) (\(worker.effort))"
        }
        return "\(provider) · \(selection.model) · \(selection.effort) · Online"
    }
    static func phaseModelLabel(_ model: String, role: ChatGPTRole? = nil) -> String {
        guard isChatGPT(model) else { return "" }
        let routed: String
        if let role { routed = role == .orchestrator ? orchestratorModel(model) : workerModel(model) }
        else { routed = model }
        guard let selection = chatGPTSelection(routed) else { return "" }
        return " · \(usesChatGPTPlan(model) ? "ChatGPT plan" : "OpenAI API") \(selection.model)"
    }
    @MainActor static func unavailability() -> String? {
        return AppleAIService.unavailability()
    }
}

/// ChatGPT-plan models are chosen from the signed-in account's actual catalog.
enum ChatGPTPlanPreferences {
    static let defaultOrchestrator = "gpt-6.1-sol"
    static let defaultWorker = "gpt-6-luna"
    static let defaultEffort = "high"
    static let modelKey = "chatGPTPlanModel"
    static let effortKey = "chatGPTPlanReasoning"
    static let modeKey = "chatGPTPlanRoutingMode"
    static let workerModelKey = "chatGPTPlanSubagentModel"
    static let workerEffortKey = "chatGPTPlanSubagentReasoning"
    static func mode(defaults: UserDefaults = .standard) -> AIConfiguration.ChatGPTMode {
        AIConfiguration.ChatGPTMode(rawValue: defaults.string(forKey: modeKey) ?? "single") ?? .single
    }
}
