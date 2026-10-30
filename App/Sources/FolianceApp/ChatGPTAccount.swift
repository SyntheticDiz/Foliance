import Foundation
import Combine

/// Internal compatibility value. Models are entered manually; the app does not
/// guess which model IDs or reasoning options a user's API key can access.
struct ChatGPTModel: Identifiable, Sendable {
    let id: String
    let displayName: String
    let reasoningEfforts: [String]
}

/// Kept only so old call sites can decode or compile; API keys have no profile.
struct ChatGPTAccountProfile: Sendable { let email: String; let subject: String }

@MainActor final class ChatGPTAccount: ObservableObject {
    static let shared = ChatGPTAccount()

    @Published private(set) var isSignedIn = false // Compatibility only; no sign-in occurs.
    @Published private(set) var busy = false
    @Published private(set) var email = ""
    @Published private(set) var status = "Add an OpenAI API key in Settings."
    @Published private(set) var error: String?
    @Published private(set) var models: [ChatGPTModel] = []
    @Published private(set) var catalogNotice = "Enter a model ID. OpenAI checks access when you run a request."

    private let credentials: OpenAICredentials

    init(credentials: OpenAICredentials = .shared) {
        self.credentials = credentials
        refreshKeyStatus()
    }

    var hasAPIKey: Bool { credentials.hasAPIKey }
    var canUseOpenAI: Bool { hasAPIKey && OpenAIConsent.isGranted() }

    func refreshKeyStatus() {
        let saved = credentials.hasAPIKey
        isSignedIn = false
        email = ""
        status = saved ? "API key saved in this app’s Keychain." : "No OpenAI API key is saved."
    }

    func saveAPIKey(_ value: String) {
        do {
            try credentials.save(value)
            error = nil
            refreshKeyStatus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func removeAPIKey() {
        do {
            try credentials.remove()
            error = nil
            refreshKeyStatus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Legacy entry points stay inert and never open a browser or load a profile.
    func signIn() async { error = "OpenAI API uses a user-provided API key. Add it in Settings." }
    func cancelSignIn() {}
    func signOut() async { removeAPIKey() }
    func refreshModels() async {
        models = []
        catalogNotice = "Enter a model ID. OpenAI checks access when you run a request."
    }
}

/// Historical transport adapter: it never reads Foliance Keychain items and
/// never returns an OAuth token. New requests use OpenAICredentials directly.
actor ChatGPTConnection {
    static let shared = ChatGPTConnection()
    func savedProfile() -> ChatGPTAccountProfile? { nil }
    func accessToken() throws -> String { throw ChatGPTService.ChatGPTError.signInRequired }
}
