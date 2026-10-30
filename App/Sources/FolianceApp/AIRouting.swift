import Foundation

enum AppleAISettings {
    static func migrate(defaults: UserDefaults = .standard) {
        let provider = defaults.string(forKey: "localAIProvider")
        if provider != "openai" && provider != "apple" && provider != "chatgpt" {
            defaults.set("apple", forKey: "localAIProvider")
        }
        defaults.removeObject(forKey: "ollamaModel")
        defaults.removeObject(forKey: "automaticAIRoutingMigrated")
    }
}

enum AIRouting {
    /// The legacy internal identifier selects OpenAI only after both explicit setup gates pass.
    static func resolve(_ requested: String,
                        appleUnavailable: () -> String? = { AppleAIService.unavailability() },
                        openAIReady: () -> Bool = { OpenAIConsent.isGranted() && OpenAICredentials.shared.hasAPIKey },
                        chatGPTPlanReady: () async -> Bool = { await ChatGPTSubscriptionAccount.shared.canUsePlan && OpenAIConsent.isGranted() }) async throws -> String {
        try Task.checkCancellation()
        if requested.hasPrefix("chatgpt:") {
            guard AIConfiguration.chatGPTSelection(requested) != nil else { throw ChatGPTService.ChatGPTError.invalidRequest }
            if AIConfiguration.usesChatGPTPlan(requested) {
                guard await chatGPTPlanReady() else { throw AppError(message: "ChatGPT plan is not ready. Continue with ChatGPT in Settings, choose an available model and grant document-sharing consent.") }
            } else {
                guard openAIReady() else { throw ChatGPTService.ChatGPTError.signInRequired }
            }
            return requested
        }
        if let reason = appleUnavailable() { throw AppError(message: reason) }
        return AppleAIService.modelID
    }
}
