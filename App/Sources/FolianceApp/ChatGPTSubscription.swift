import AppKit
import Combine
import CryptoKit
import Foundation
import Network
import Security

struct ChatGPTSubscriptionModel: Identifiable, Sendable {
    let id: String
    let displayName: String
    let reasoningEfforts: [String]
}

struct ChatGPTSubscriptionProfile: Sendable {
    let email: String
    let subject: String
    let canUsePlan: Bool
}

enum ChatGPTSubscriptionStorageIdentity {
    static let keychainService = "app.foliance.mac.chatgpt-subscription"
    static let activeClientIDDefaultsKey = "foliance.chatGPTSubscription.activeClientID"
    static let hostIDDefaultsKey = "foliance.chatGPTSubscription.extAgentHostID"
}

struct ChatGPTSubscriptionSavedAccount: Identifiable, Sendable {
    let id: String
    let email: String
    let isConnected: Bool
    var label: String {
        let suffix = String(id.suffix(8))
        return email.isEmpty ? "ChatGPT account · \(suffix)" : "\(email) · \(suffix)"
    }
}

struct ChatGPTSubscriptionCredential: Codable, Sendable {
    var clientID: String
    var hostID: String
    var subject: String
    var email: String
    var idToken: String?
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]
}

struct ChatGPTSubscriptionAccountSnapshot: Sendable {
    let accounts: [ChatGPTSubscriptionSavedAccount]
    let selectedID: String?
}

protocol ChatGPTSubscriptionCredentialStore: Sendable {
    func loadAll() throws -> [ChatGPTSubscriptionCredential]
    func save(_ credential: ChatGPTSubscriptionCredential) throws
    func activeClientID() -> String?
    func setActiveClientID(_ clientID: String?)
}

enum ChatGPTSubscriptionError: LocalizedError, Sendable, Equatable {
    case invalidRequest, randomnessUnavailable, invalidCallback, callbackTimedOut, listenerUnavailable
    case browserUnavailable, accessDenied, planScopeMissing, invalidIdentityToken, invalidDiscovery
    case codeExchangeFailed, invalidResponse, networkRequestFailed, modelsUnavailable, notConnected
    case refreshFailed, keychainFailure

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Foliance could not prepare the ChatGPT sign-in request."
        case .randomnessUnavailable: "Foliance could not create secure sign-in values."
        case .invalidCallback: "The ChatGPT sign-in response could not be verified. Try signing in again."
        case .callbackTimedOut: "ChatGPT sign-in timed out. Try again."
        case .listenerUnavailable: "Foliance could not start its local sign-in callback."
        case .browserUnavailable: "Foliance could not open your browser."
        case .accessDenied: "ChatGPT sign-in or plan permission was declined."
        case .planScopeMissing: "This ChatGPT account has not granted permission to use its plan in Foliance."
        case .invalidIdentityToken: "Foliance could not verify the identity returned by ChatGPT."
        case .invalidDiscovery: "OpenAI returned invalid sign-in configuration."
        case .codeExchangeFailed: "ChatGPT sign-in could not be completed. Try again."
        case .invalidResponse: "OpenAI returned an invalid sign-in response."
        case .networkRequestFailed: "Foliance could not connect to OpenAI. Check your connection and try again."
        case .modelsUnavailable: "Foliance could not load models for this ChatGPT account."
        case .notConnected: "Connect a ChatGPT account that has granted plan usage to Foliance."
        case .refreshFailed: "The ChatGPT session could not be renewed. Sign in again."
        case .keychainFailure: "Foliance could not access or update the ChatGPT session in this Mac’s Keychain. Unlock Keychain and retry."
        }
    }
}

enum ChatGPTSubscriptionOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let dynamicClientID = "dynamic_agent_client"
    static let requiredScopes: Set<String> = ["openid", "profile", "email", "offline_access", "resource.invoke", "chatgpt.tokens.use.direct"]
    static let planScopes: Set<String> = ["resource.invoke", "chatgpt.tokens.use.direct"]

    struct Callback: Sendable {
        let code: String?
        let state: String
        let clientID: String?
        let error: String?
    }
    struct Identity: Sendable { let subject: String; let email: String }

    static func randomURLSafeValue(byteCount: Int = 32) throws -> String {
        guard (16...128).contains(byteCount) else { throw ChatGPTSubscriptionError.invalidRequest }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw ChatGPTSubscriptionError.randomnessUnavailable
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    static func pkceChallenge(verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authorizationURL(clientID: String, callbackURI: String, state: String, nonce: String,
                                 challenge: String, hostID: String, reauthorization: Bool,
                                 idTokenHint: String? = nil, loginHint: String? = nil,
                                 agentName: String = "Foliance", promptForConsent: Bool = false) throws -> URL {
        guard var components = URLComponents(string: issuer + "/api/accounts/authorize"),
              let callback = URL(string: callbackURI), callback.scheme == "http", callback.host == "127.0.0.1",
              callback.path == "/auth/callback", callback.port != nil,
              !clientID.isEmpty, !state.isEmpty, !nonce.isEmpty, !challenge.isEmpty, !hostID.isEmpty else {
            throw ChatGPTSubscriptionError.invalidRequest
        }
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: callbackURI),
            URLQueryItem(name: "scope", value: requiredScopes.sorted().joined(separator: " ")),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "ext_agent_host_id", value: hostID)
        ]
        if !reauthorization { items.append(URLQueryItem(name: "agent_name_hint", value: agentName)) }
        if reauthorization, promptForConsent { items.append(URLQueryItem(name: "prompt", value: "consent")) }
        if reauthorization, let idTokenHint, !idTokenHint.isEmpty { items.append(URLQueryItem(name: "id_token_hint", value: idTokenHint)) }
        if reauthorization, let loginHint, !loginHint.isEmpty { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components.queryItems = items
        guard let url = components.url else { throw ChatGPTSubscriptionError.invalidRequest }
        return url
    }

    static func parseCallbackRequest(_ data: Data, expectedHost: String) -> Callback? {
        guard data.count <= 16_384, let request = String(data: data, encoding: .utf8),
              let headerEnd = request.range(of: "\r\n\r\n") else { return nil }
        let lines = String(request[..<headerEnd.lowerBound]).components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == "GET", ["HTTP/1.0", "HTTP/1.1"].contains(String(parts[2])),
              let host = lines.dropFirst().first(where: { $0.lowercased().hasPrefix("host:") }),
              String(host.dropFirst(5)).trimmingCharacters(in: .whitespaces) == expectedHost else { return nil }
        let target = String(parts[1])
        guard target.hasPrefix("/auth/callback?"), !target.contains("#"),
              let components = URLComponents(string: "http://127.0.0.1" + target),
              components.path == "/auth/callback", let query = components.queryItems, !query.isEmpty else { return nil }
        var values: [String: String] = [:]
        for item in query {
            guard values[item.name] == nil, let value = item.value, value.utf8.count <= 4096 else { return nil }
            values[item.name] = value
        }
        guard let state = values["state"], !state.isEmpty,
              (values["code"] != nil) != (values["error"] != nil),
              values["code"]?.isEmpty != true else { return nil }
        return Callback(code: values["code"], state: state, clientID: values["client_id"], error: values["error"])
    }

    static func callbackMatches(_ callback: Callback, expectedState: String, expectedClientID: String?, isNewRegistration: Bool) -> Bool {
        guard callback.state == expectedState, callback.error == nil else { return false }
        if isNewRegistration {
            return callback.code != nil && callback.clientID.map { !$0.isEmpty && $0 != dynamicClientID } == true
        }
        guard let expectedClientID else { return false }
        return callback.code != nil && (callback.clientID == nil || callback.clientID == expectedClientID)
    }

    static func hasPlanScope(_ scope: String) -> Bool { hasPlanScope(scope.split(whereSeparator: \.isWhitespace).map(String.init)) }
    static func hasPlanScope(_ scopes: [String]) -> Bool { Set(scopes).isSuperset(of: planScopes) }
    static func hasSavedSession(subject: String, accessToken: String?, refreshToken: String?) -> Bool {
        !subject.isEmpty && (accessToken != nil || refreshToken != nil)
    }

    static func parseModels(_ data: Data) throws -> [ChatGPTSubscriptionModel] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["models"] as? [[String: Any]] else { throw ChatGPTSubscriptionError.invalidResponse }
        let allowed: Set<String> = ["none", "low", "medium", "high", "xhigh", "max"]
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard entry["visibility"] as? String == "list",
                  let slug = entry["slug"] as? String, !slug.isEmpty,
                  slug.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil,
                  seen.insert(slug).inserted,
                  let name = entry["display_name"] as? String, !name.isEmpty else { return nil }
            let efforts: [String]
            if entry["supported_reasoning_levels"] == nil {
                efforts = fallbackEfforts(for: slug)
            } else {
                efforts = (entry["supported_reasoning_levels"] as? [Any] ?? []).compactMap { value -> String? in
                    if let text = value as? String { return text }
                    if let object = value as? [String: Any] { return object["effort"] as? String ?? object["name"] as? String }
                    return nil
                }.filter { allowed.contains($0) }
            }
            var unique = Set<String>()
            return ChatGPTSubscriptionModel(id: slug, displayName: name,
                                            reasoningEfforts: efforts.filter { unique.insert($0).inserted })
        }
    }

    private static func fallbackEfforts(for modelID: String) -> [String] {
        switch modelID {
        case "gpt-6.1-sol": ["low", "medium", "high", "xhigh", "max"]
        case "gpt-6-luna": ["none", "low", "medium", "high", "xhigh", "max"]
        default: []
        }
    }

    static func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.keys.sorted().map { URLQueryItem(name: $0, value: values[$0]) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "%20", with: "+").utf8)
    }

    /// Verifies RS256 with the supplied published JWKS before trusting OIDC identity claims.
    static func verifyIDToken(_ token: String, jwksData: Data, audience: String, nonce: String?,
                              expectedSubject: String? = nil, now: Date = Date(),
                              signatureCheck: ((Data, Data, Data) -> Bool)? = nil) throws -> Identity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = decodeBase64URL(String(parts[0])), let claimsData = decodeBase64URL(String(parts[1])),
              let signature = decodeBase64URL(String(parts[2])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", let keyID = header["kid"] as? String,
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let jwks = try JSONSerialization.jsonObject(with: jwksData) as? [String: Any],
              let keys = jwks["keys"] as? [[String: Any]],
              let jwk = keys.first(where: { $0["kid"] as? String == keyID && $0["kty"] as? String == "RSA" && ($0["use"] as? String == nil || $0["use"] as? String == "sig") }),
              let modulus = jwk["n"] as? String, let exponent = jwk["e"] as? String,
              let n = decodeBase64URL(modulus), let e = decodeBase64URL(exponent),
              let keyData = rsaPublicKeyDER(modulus: n, exponent: e) else {
            throw ChatGPTSubscriptionError.invalidIdentityToken
        }
        let signedBytes = Data((String(parts[0]) + "." + String(parts[1])).utf8)
        let verified: Bool
        if let signatureCheck {
            verified = signatureCheck(signedBytes, signature, keyData)
        } else {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA,
                                               kSecAttrKeyClass: kSecAttrKeyClassPublic,
                                               kSecAttrKeySizeInBits: n.count * 8]
            var keyError: Unmanaged<CFError>?
            guard let publicKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
                throw ChatGPTSubscriptionError.invalidIdentityToken
            }
            verified = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                              signedBytes as CFData, signature as CFData, &keyError)
        }
        let audiences = (claims["aud"] as? String).map { [$0] } ?? (claims["aud"] as? [String] ?? [])
        guard verified, claims["iss"] as? String == issuer, audiences.contains(audience),
              audiences.count == 1 || claims["azp"] as? String == audience,
              let expiration = claims["exp"] as? TimeInterval, expiration > now.timeIntervalSince1970,
              nonce == nil || claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty,
              expectedSubject == nil || expectedSubject == subject else {
            throw ChatGPTSubscriptionError.invalidIdentityToken
        }
        return Identity(subject: subject, email: claims["email"] as? String ?? "")
    }

    private static func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data? {
        func integer(_ bytes: Data) -> Data? {
            var value = Array(bytes.drop(while: { $0 == 0 }))
            guard !value.isEmpty else { return nil }
            if value[0] & 0x80 != 0 { value.insert(0, at: 0) }
            return derElement(tag: 0x02, body: Data(value))
        }
        guard let n = integer(modulus), let e = integer(exponent) else { return nil }
        return derElement(tag: 0x30, body: n + e)
    }

    private static func derElement(tag: UInt8, body: Data) -> Data {
        var result = Data([tag])
        let count = body.count
        if count < 128 { result.append(UInt8(count)) }
        else {
            var length = count.bigEndian
            let bytes = withUnsafeBytes(of: &length) { Array($0.drop(while: { $0 == 0 })) }
            result.append(0x80 | UInt8(bytes.count)); result.append(contentsOf: bytes)
        }
        result.append(body)
        return result
    }
}

@MainActor
final class ChatGPTSubscriptionAccount: ObservableObject {
    static let shared = ChatGPTSubscriptionAccount()

    @Published private(set) var isConnected = false
    @Published private(set) var canUsePlan = false
    @Published private(set) var needsPlanConsent = false
    @Published private(set) var busy = false
    @Published private(set) var email = ""
    @Published private(set) var status = "Not connected to ChatGPT."
    @Published private(set) var error: String?
    @Published private(set) var models: [ChatGPTSubscriptionModel] = []
    @Published private(set) var savedAccounts: [ChatGPTSubscriptionSavedAccount] = []
    @Published private(set) var selectedAccountID: String?
    @Published private(set) var didRestoreSession = false

    private var signInTask: Task<ChatGPTSubscriptionProfile, Error>?
    private let connection: ChatGPTSubscriptionConnection
    private let shouldLoadCatalogAutomatically: () -> Bool
    private var restoreTask: Task<Void, Never>?
    private var isRefreshingModels = false

    init(connection: ChatGPTSubscriptionConnection = .shared,
         shouldLoadCatalogAutomatically: @escaping () -> Bool = {
             AIConfiguration.usesChatGPTPlan(AIConfiguration.selectedModel)
         }, automaticallyRestore: Bool = true) {
        self.connection = connection
        self.shouldLoadCatalogAutomatically = shouldLoadCatalogAutomatically
        if automaticallyRestore { Task { await restoreSessionIfNeeded() } }
    }

    func signIn() async { await performSignIn(forcePlanConsent: false, addAccount: false) }

    func addAccount() async { await performSignIn(forcePlanConsent: false, addAccount: true) }

    func selectAccount(id: String) async {
        guard !busy, id != selectedAccountID else { return }
        busy = true; error = nil
        do {
            let profile = try await connection.selectAccount(id: id)
            selectedAccountID = id
            if let profile {
                isConnected = true; email = profile.email; canUsePlan = profile.canUsePlan
                needsPlanConsent = !profile.canUsePlan
                status = profile.canUsePlan ? "Connected to ChatGPT plan usage." : "Connected. ChatGPT plan usage permission was not granted."
                models = []
                if profile.canUsePlan { await refreshModels() }
            } else {
                isConnected = false; canUsePlan = false; needsPlanConsent = false; email = ""; models = []
                status = "Selected account. Sign in to reconnect."
            }
            try await refreshSavedAccounts()
        } catch {
            self.error = error.localizedDescription
            status = "The saved ChatGPT account could not be loaded. Try again."
        }
        busy = false
    }

    /// Call only after the user explicitly chooses to enable ChatGPT plan usage.
    func enablePlanUsage() async {
        guard isConnected else { await signIn(); return }
        await performSignIn(forcePlanConsent: true, addAccount: false)
    }

    private func performSignIn(forcePlanConsent: Bool, addAccount: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; status = "Connecting to ChatGPT…"
        let task = Task { try await connection.signIn(forcePlanConsent: forcePlanConsent, addAccount: addAccount) }
        signInTask = task
        do {
            let profile = try await task.value
            let snapshot = try await connection.accountSnapshot()
            selectedAccountID = snapshot.selectedID
            isConnected = true; email = profile.email; canUsePlan = profile.canUsePlan
            needsPlanConsent = !profile.canUsePlan
            status = profile.canUsePlan ? "Connected to ChatGPT plan usage." : "Connected. ChatGPT plan usage permission was not granted."
            models = []
            if profile.canUsePlan { await refreshModels() } else { models = [] }
        } catch is CancellationError {
            status = "ChatGPT sign-in cancelled."
        } catch {
            self.error = error.localizedDescription; status = "ChatGPT sign-in failed."
        }
        signInTask = nil; busy = false
        do { try await refreshSavedAccounts() }
        catch { self.error = error.localizedDescription }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        Task { await connection.cancelSignIn() }
    }

    func signOut() async {
        busy = true; error = nil
        do {
            let revoked = try await connection.signOut()
            isConnected = false; canUsePlan = false; email = ""; models = []; busy = false
            needsPlanConsent = false
            status = revoked ? "Disconnected from ChatGPT." : "Disconnected locally; OpenAI did not confirm remote revocation."
            try await refreshSavedAccounts()
        } catch {
            self.error = error.localizedDescription
            status = "The ChatGPT session could not be disconnected from this Mac."
            busy = false
        }
    }

    func refreshModels() async {
        guard isConnected, canUsePlan else { models = []; return }
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        do {
            models = try await connection.refreshModels()
            status = "ChatGPT models updated."
            error = nil
        } catch {
            self.error = error.localizedDescription; status = "ChatGPT models could not be loaded."
            do {
                let profile = try await connection.savedProfile()
                if profile == nil {
                    isConnected = false; canUsePlan = false; needsPlanConsent = false; models = []
                }
            } catch { /* A locked Keychain must not be presented as a disconnected account. */ }
        }
    }

    func accessToken() async throws -> String {
        do { return try await connection.accessToken() }
        catch {
            do {
                let profile = try await connection.savedProfile()
                if profile == nil {
                    isConnected = false; canUsePlan = false; needsPlanConsent = false; models = []
                    status = "ChatGPT session expired. Sign in again."
                }
            } catch { /* Preserve the current account state while Keychain access is unavailable. */ }
            throw error
        }
    }

    /// Call when the Responses transport receives a confirmed 401 for this account.
    func invalidateAfterUnauthorizedResponse() async {
        do {
            try await connection.invalidateSession()
            isConnected = false; canUsePlan = false; needsPlanConsent = false; models = []
            status = "ChatGPT session was rejected. Sign in again."
        } catch {
            self.error = error.localizedDescription
            status = "The rejected ChatGPT session could not be cleared from this Mac."
        }
    }

    func restoreSessionIfNeeded(loadCatalog: Bool = false) async {
        var startedRestore = false
        if let restoreTask {
            await restoreTask.value
        } else if !didRestoreSession {
            guard !busy else { return }
            busy = true
            startedRestore = true
            let task = Task { await self.loadSavedAccount() }
            restoreTask = task
            await task.value
            restoreTask = nil
        }
        if loadCatalog || shouldLoadCatalogAutomatically() { await loadCatalogIfNeeded() }
        if startedRestore { busy = false }
    }

    private func loadCatalogIfNeeded() async {
        guard isConnected, canUsePlan, models.isEmpty else { return }
        await refreshModels()
    }

    private func loadSavedAccount() async {
        do {
            let snapshot = try await connection.accountSnapshot()
            savedAccounts = snapshot.accounts
            selectedAccountID = snapshot.selectedID
            guard let profile = try await connection.savedProfile() else {
                isConnected = false; canUsePlan = false; needsPlanConsent = false; email = ""; models = []
                status = snapshot.selectedID == nil ? "Not connected to ChatGPT." : "Saved account. Sign in to reconnect."
                didRestoreSession = true
                return
            }
            isConnected = true; canUsePlan = profile.canUsePlan; email = profile.email
            needsPlanConsent = !profile.canUsePlan
            status = profile.canUsePlan ? "Connected to ChatGPT plan usage." : "Connected. ChatGPT plan usage permission was not granted."
            didRestoreSession = true
        } catch {
            self.error = error.localizedDescription
            status = "The saved ChatGPT session could not be restored. Try again."
            didRestoreSession = false
        }
    }

    private func refreshSavedAccounts() async throws {
        let snapshot = try await connection.accountSnapshot()
        savedAccounts = snapshot.accounts
        selectedAccountID = snapshot.selectedID
    }
}

actor ChatGPTSubscriptionConnection {
    static let shared = ChatGPTSubscriptionConnection()
    private struct Discovery: Decodable {
        let issuer: String
        let authorization_endpoint: URL
        let token_endpoint: URL
        let jwks_uri: URL
        let revocation_endpoint: URL
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let token_type: String
        let expires_in: TimeInterval
        let scope: String?
    }
    private struct Attempt: Sendable {
        let clientID: String
        let isNewRegistration: Bool
        let callbackURI: String
        let state: String
        let nonce: String
        let verifier: String
    }

    private let session: URLSession
    private let store: any ChatGPTSubscriptionCredentialStore
    private var credentials: [String: ChatGPTSubscriptionCredential] = [:]
    private var pendingCredentialWrites: [String: ChatGPTSubscriptionCredential] = [:]
    private var activeClientID: String?
    private var loaded = false
    private var callbackServer: ChatGPTSubscriptionLoopbackServer?
    private var refreshTasks: [String: Task<String, Error>] = [:]
    private var loggingOut = false
    private var generation: UInt64 = 0

    init(store: any ChatGPTSubscriptionCredentialStore = ChatGPTSubscriptionKeychain(), session: URLSession? = nil) {
        self.store = store
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 25
            configuration.timeoutIntervalForResource = 45
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration, delegate: ChatGPTSubscriptionRedirectRefuser(), delegateQueue: nil)
        }
    }

    func savedProfile() throws -> ChatGPTSubscriptionProfile? {
        guard let record = try loadCredential(), ChatGPTSubscriptionOAuth.hasSavedSession(
            subject: record.subject, accessToken: record.accessToken, refreshToken: record.refreshToken) else { return nil }
        return profile(record)
    }

    func accountSnapshot() throws -> ChatGPTSubscriptionAccountSnapshot {
        try loadCredentials()
        let accounts = credentials.values.sorted { $0.clientID < $1.clientID }.map { record in
            ChatGPTSubscriptionSavedAccount(id: record.clientID, email: record.email,
                isConnected: ChatGPTSubscriptionOAuth.hasSavedSession(subject: record.subject,
                    accessToken: record.accessToken, refreshToken: record.refreshToken))
        }
        return ChatGPTSubscriptionAccountSnapshot(accounts: accounts, selectedID: activeClientID)
    }

    func selectAccount(id: String) throws -> ChatGPTSubscriptionProfile? {
        try loadCredentials()
        guard credentials[id] != nil else { return nil }
        try flushPendingCredential(clientID: id)
        activeClientID = id
        store.setActiveClientID(id)
        return try savedProfile()
    }

    func signIn(forcePlanConsent: Bool = false, addAccount: Bool = false) async throws -> ChatGPTSubscriptionProfile {
        try Task.checkCancellation()
        guard !loggingOut else { throw ChatGPTSubscriptionError.notConnected }
        try loadCredentials()
        let previousClientID = addAccount ? nil : activeClientID
        if let previousClientID { try flushPendingCredential(clientID: previousClientID) }
        let previous = previousClientID.flatMap { credentials[$0] }
        let isNew = previous == nil || previous?.clientID.isEmpty == true
        let opGeneration = generation
        let hostID = previous.flatMap { $0.hostID.isEmpty ? nil : $0.hostID } ?? stableHostID()
        let server = try ChatGPTSubscriptionLoopbackServer()
        callbackServer = server
        defer { server.cancel(); callbackServer = nil }
        let callbackURI = try await server.start()
        let attempt = Attempt(clientID: isNew ? ChatGPTSubscriptionOAuth.dynamicClientID : previous!.clientID,
                              isNewRegistration: isNew, callbackURI: callbackURI,
                              state: try ChatGPTSubscriptionOAuth.randomURLSafeValue(),
                              nonce: try ChatGPTSubscriptionOAuth.randomURLSafeValue(),
                              verifier: try ChatGPTSubscriptionOAuth.randomURLSafeValue(byteCount: 48))
        let url = try ChatGPTSubscriptionOAuth.authorizationURL(
            clientID: attempt.clientID, callbackURI: callbackURI, state: attempt.state, nonce: attempt.nonce,
            challenge: ChatGPTSubscriptionOAuth.pkceChallenge(verifier: attempt.verifier), hostID: hostID,
            reauthorization: !isNew, idTokenHint: previous?.idToken, loginHint: previous?.email,
            promptForConsent: forcePlanConsent)
        let callbackTask = Task { try await server.waitForCallback() }
        guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else {
            callbackTask.cancel(); throw ChatGPTSubscriptionError.browserUnavailable
        }
        let callback: ChatGPTSubscriptionOAuth.Callback
        do {
            callback = try await withTaskCancellationHandler { try await callbackTask.value }
                onCancel: { callbackTask.cancel(); server.cancel() }
        } catch { callbackTask.cancel(); throw error }
        try Task.checkCancellation()
        guard callback.state == attempt.state else { throw ChatGPTSubscriptionError.invalidCallback }
        if callback.error == "access_denied" { throw ChatGPTSubscriptionError.accessDenied }
        guard ChatGPTSubscriptionOAuth.callbackMatches(callback, expectedState: attempt.state,
                                                        expectedClientID: previous?.clientID, isNewRegistration: isNew),
              let code = callback.code else { throw ChatGPTSubscriptionError.invalidCallback }
        let issuedClientID = isNew ? try requireIssuedClientID(callback.clientID) : previous!.clientID
        if isNew {
            try ensureCurrent(opGeneration)
            try saveCredential(ChatGPTSubscriptionCredential(clientID: issuedClientID, hostID: hostID, subject: "", email: "",
                                          idToken: nil, accessToken: nil, refreshToken: nil, expiresAt: nil, scopes: []),
                               activate: activeClientID == nil)
        }
        try ensureCurrent(opGeneration)
        let discovery = try await fetchDiscovery()
        let tokens = try await exchangeCode(code, clientID: issuedClientID, attempt: attempt, endpoint: discovery.token_endpoint)
        guard tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty,
              tokens.expires_in > 0, tokens.expires_in.isFinite,
              let idToken = tokens.id_token, let refreshToken = tokens.refresh_token, !refreshToken.isEmpty else {
            throw ChatGPTSubscriptionError.invalidResponse
        }
        let jwks = try await fetch(discovery.jwks_uri)
        let identity = try ChatGPTSubscriptionOAuth.verifyIDToken(idToken, jwksData: jwks, audience: issuedClientID,
                                                                  nonce: attempt.nonce,
                                                                  expectedSubject: previous.flatMap { $0.subject.isEmpty ? nil : $0.subject })
        let scopes = (tokens.scope ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        try ensureCurrent(opGeneration)
        let saved = ChatGPTSubscriptionCredential(clientID: issuedClientID, hostID: hostID, subject: identity.subject,
                               email: identity.email, idToken: idToken, accessToken: tokens.access_token,
                               refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(tokens.expires_in), scopes: scopes)
        try saveCredential(saved, activate: true)
        return profile(saved)
    }

    func cancelSignIn() { callbackServer?.cancel() }

    func signOut() async throws -> Bool {
        loggingOut = true; generation &+= 1
        callbackServer?.cancel(); callbackServer = nil
        refreshTasks.values.forEach { $0.cancel() }
        refreshTasks.removeAll()
        defer { loggingOut = false }
        guard var record = try loadCredential() else { return true }
        var revoked = record.refreshToken == nil && record.accessToken == nil
        if let refreshToken = record.refreshToken, !record.clientID.isEmpty {
            for attempt in 0..<3 {
                do {
                    let discovery = try await fetchDiscovery()
                    var request = URLRequest(url: discovery.revocation_endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = ChatGPTSubscriptionOAuth.formBody([
                        "token": refreshToken, "token_type_hint": "refresh_token", "client_id": record.clientID
                    ])
                    let (_, response) = try await session.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode
                    if status == 200 { revoked = true; break }
                    revoked = false
                    guard let status, (500..<600).contains(status), attempt < 2 else { break }
                } catch {
                    revoked = false
                    guard attempt < 2 else { break }
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 150_000_000)
            }
        }
        record.idToken = nil; record.accessToken = nil; record.refreshToken = nil; record.expiresAt = nil; record.scopes = []
        try saveCredential(record, activate: false)
        return revoked
    }

    func accessToken() async throws -> String {
        guard !loggingOut else { throw ChatGPTSubscriptionError.notConnected }
        try loadCredentials()
        guard let clientID = activeClientID else { throw ChatGPTSubscriptionError.notConnected }
        try flushPendingCredential(clientID: clientID)
        guard let record = credentials[clientID], ChatGPTSubscriptionOAuth.hasPlanScope(record.scopes),
              let token = record.accessToken, let expiry = record.expiresAt, record.refreshToken != nil else {
            throw ChatGPTSubscriptionError.notConnected
        }
        if expiry.timeIntervalSinceNow > 90 { return token }
        if let refreshTask = refreshTasks[record.clientID] { return try await refreshTask.value }
        let task = Task { try await self.refreshAccessToken(clientID: clientID) }
        refreshTasks[clientID] = task
        defer { refreshTasks[clientID] = nil }
        return try await task.value
    }

    func refreshModels() async throws -> [ChatGPTSubscriptionModel] {
        let token = try await accessToken()
        var request = URLRequest(url: URL(string: ChatGPTSubscriptionOAuth.resource + "/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTSubscriptionError.networkRequestFailed }
        if http.statusCode == 401 {
            try clearSessionTokens()
            throw ChatGPTSubscriptionError.notConnected
        }
        guard http.statusCode == 200 else { throw ChatGPTSubscriptionError.modelsUnavailable }
        return try ChatGPTSubscriptionOAuth.parseModels(data)
    }

    func invalidateSession() throws { try clearSessionTokens() }

    private func refreshAccessToken(clientID: String) async throws -> String {
        let opGeneration = generation
        try loadCredentials()
        try flushPendingCredential(clientID: clientID)
        guard var record = credentials[clientID], let refreshToken = record.refreshToken, !clientID.isEmpty else {
            throw ChatGPTSubscriptionError.notConnected
        }
        let discovery = try await fetchDiscovery()
        var request = URLRequest(url: discovery.token_endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ChatGPTSubscriptionOAuth.formBody([
            "grant_type": "refresh_token", "client_id": record.clientID,
            "refresh_token": refreshToken, "resource": ChatGPTSubscriptionOAuth.resource
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTSubscriptionError.networkRequestFailed }
        guard http.statusCode == 200 else {
            if isTerminalRefreshError(data) {
                record.idToken = nil; record.accessToken = nil; record.refreshToken = nil; record.expiresAt = nil; record.scopes = []
                try saveCredential(record, activate: activeClientID == clientID)
            }
            throw ChatGPTSubscriptionError.refreshFailed
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard tokens.token_type.lowercased() == "bearer", !tokens.access_token.isEmpty,
              tokens.expires_in > 0, tokens.expires_in.isFinite,
              let nextRefresh = tokens.refresh_token, !nextRefresh.isEmpty else { throw ChatGPTSubscriptionError.invalidResponse }
        let scopes = (tokens.scope ?? record.scopes.joined(separator: " ")).split(whereSeparator: \.isWhitespace).map(String.init)
        guard ChatGPTSubscriptionOAuth.hasPlanScope(scopes) else { throw ChatGPTSubscriptionError.planScopeMissing }
        if let idToken = tokens.id_token {
            let jwks = try await fetch(discovery.jwks_uri)
            let identity = try ChatGPTSubscriptionOAuth.verifyIDToken(idToken, jwksData: jwks,
                audience: record.clientID, nonce: nil, expectedSubject: record.subject)
            record.idToken = idToken; record.email = identity.email
        }
        record.accessToken = tokens.access_token; record.refreshToken = nextRefresh
        record.expiresAt = Date().addingTimeInterval(tokens.expires_in); record.scopes = scopes
        try ensureCurrent(opGeneration)
        try saveCredential(record, activate: activeClientID == clientID)
        return tokens.access_token
    }

    private func exchangeCode(_ code: String, clientID: String, attempt: Attempt, endpoint: URL) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ChatGPTSubscriptionOAuth.formBody([
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "redirect_uri": attempt.callbackURI, "code_verifier": attempt.verifier,
            "resource": ChatGPTSubscriptionOAuth.resource
        ])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ChatGPTSubscriptionError.codeExchangeFailed }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func fetchDiscovery() async throws -> Discovery {
        let url = URL(string: ChatGPTSubscriptionOAuth.issuer + "/.well-known/openid-configuration")!
        let data = try await fetch(url)
        let discovery = try JSONDecoder().decode(Discovery.self, from: data)
        let endpoints = [discovery.authorization_endpoint, discovery.token_endpoint, discovery.jwks_uri, discovery.revocation_endpoint]
        guard discovery.issuer == ChatGPTSubscriptionOAuth.issuer,
              endpoints.allSatisfy({ $0.scheme == "https" && $0.host == "auth.openai.com" }) else {
            throw ChatGPTSubscriptionError.invalidDiscovery
        }
        return discovery
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ChatGPTSubscriptionError.networkRequestFailed }
        return data
    }

    private func profile(_ record: ChatGPTSubscriptionCredential) -> ChatGPTSubscriptionProfile {
        ChatGPTSubscriptionProfile(email: record.email, subject: record.subject,
                                   canUsePlan: ChatGPTSubscriptionOAuth.hasPlanScope(record.scopes) && record.accessToken != nil)
    }

    private func loadCredentials() throws {
        guard !loaded else { return }
        let stored = try store.loadAll()
        credentials = Dictionary(stored.map { ($0.clientID, $0) }, uniquingKeysWith: { _, latest in latest })
        let requestedID = store.activeClientID()
        activeClientID = requestedID.flatMap { credentials[$0] == nil ? nil : $0 }
        if activeClientID == nil, let first = credentials.keys.sorted().first {
            activeClientID = first
            store.setActiveClientID(first)
        }
        loaded = true
    }

    private func loadCredential() throws -> ChatGPTSubscriptionCredential? {
        try loadCredentials()
        guard let activeClientID else { return nil }
        return credentials[activeClientID]
    }

    private func saveCredential(_ record: ChatGPTSubscriptionCredential, activate: Bool = true) throws {
        do { try store.save(record) }
        catch {
            // Retain a validated rotated record in process memory until Keychain
            // can atomically store it. Callers must flush this before using tokens.
            credentials[record.clientID] = record
            pendingCredentialWrites[record.clientID] = record
            loaded = true
            throw error
        }
        credentials[record.clientID] = record
        pendingCredentialWrites.removeValue(forKey: record.clientID)
        loaded = true
        if activate {
            activeClientID = record.clientID
            store.setActiveClientID(record.clientID)
        }
    }

    private func flushPendingCredential(clientID: String) throws {
        guard let pending = pendingCredentialWrites[clientID] else { return }
        try store.save(pending)
        credentials[clientID] = pending
        pendingCredentialWrites.removeValue(forKey: clientID)
        loaded = true
    }

    private func clearSessionTokens() throws {
        guard var record = try loadCredential() else { return }
        record.idToken = nil; record.accessToken = nil; record.refreshToken = nil; record.expiresAt = nil; record.scopes = []
        try saveCredential(record, activate: false)
    }

    private func stableHostID() -> String {
        let defaults = UserDefaults.standard
        let key = ChatGPTSubscriptionStorageIdentity.hostIDDefaultsKey
        if let value = defaults.string(forKey: key), UUID(uuidString: value) != nil { return "urn:uuid:" + value.lowercased() }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return "urn:uuid:" + value
    }

    private func ensureCurrent(_ expected: UInt64) throws {
        try Task.checkCancellation()
        guard !loggingOut, expected == generation else { throw CancellationError() }
    }

    private func requireIssuedClientID(_ value: String?) throws -> String {
        guard let value, !value.isEmpty, value != ChatGPTSubscriptionOAuth.dynamicClientID,
              value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ChatGPTSubscriptionError.invalidCallback
        }
        return value
    }

    private func isTerminalRefreshError(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let error = object["error"] as? String ?? (object["error"] as? [String: Any])?["code"] as? String ?? ""
        return ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(error)
    }
}

final class ChatGPTSubscriptionKeychain: ChatGPTSubscriptionCredentialStore, @unchecked Sendable {
    func loadAll() throws -> [ChatGPTSubscriptionCredential] {
        var query = Self.baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { throw ChatGPTSubscriptionError.keychainFailure }
        var credentials: [ChatGPTSubscriptionCredential] = []
        credentials.reserveCapacity(rows.count)
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let credential = try? JSONDecoder().decode(ChatGPTSubscriptionCredential.self, from: data),
                  credential.clientID == account,
                  account.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
                throw ChatGPTSubscriptionError.keychainFailure
            }
            credentials.append(credential)
        }
        return credentials
    }

    func save(_ credential: ChatGPTSubscriptionCredential) throws {
        guard !credential.clientID.isEmpty,
              credential.clientID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw ChatGPTSubscriptionError.keychainFailure
        }
        let data: Data
        do { data = try JSONEncoder().encode(credential) }
        catch { throw ChatGPTSubscriptionError.keychainFailure }
        let values: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let query = accountQuery(credential.clientID)
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            for (key, value) in values { addQuery[key] = value }
            guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else { throw ChatGPTSubscriptionError.keychainFailure }
        } else if status != errSecSuccess { throw ChatGPTSubscriptionError.keychainFailure }
    }

    func activeClientID() -> String? { UserDefaults.standard.string(forKey: ChatGPTSubscriptionStorageIdentity.activeClientIDDefaultsKey) }

    func setActiveClientID(_ clientID: String?) {
        let defaults = UserDefaults.standard
        if let clientID { defaults.set(clientID, forKey: ChatGPTSubscriptionStorageIdentity.activeClientIDDefaultsKey) }
        else { defaults.removeObject(forKey: ChatGPTSubscriptionStorageIdentity.activeClientIDDefaultsKey) }
    }

    private func accountQuery(_ clientID: String) -> [String: Any] {
        var query = Self.baseQuery
        query[kSecAttrAccount as String] = clientID
        return query
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: ChatGPTSubscriptionStorageIdentity.keychainService,
         kSecAttrSynchronizable as String: false]
    }
}

private final class ChatGPTSubscriptionRedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class ChatGPTSubscriptionLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.foliance.chatgpt-subscription-callback")
    private let lock = NSLock()
    private var ready: CheckedContinuation<URL, Error>?
    private var callback: CheckedContinuation<ChatGPTSubscriptionOAuth.Callback, Error>?
    private var result: Result<ChatGPTSubscriptionOAuth.Callback, Error>?
    private var timeout: Task<Void, Never>?
    private var stopped = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] in self?.receive($0) }
    }

    func start() async throws -> String {
        let url = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.lock()
                guard !stopped else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                ready = continuation; lock.unlock()
                listener.stateUpdateHandler = { [weak self] in self?.stateChanged($0) }
                listener.start(queue: queue)
            }
        } onCancel: { self.cancel() }
        return url.absoluteString
    }

    func waitForCallback(timeout seconds: TimeInterval = 300) async throws -> ChatGPTSubscriptionOAuth.Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ChatGPTSubscriptionOAuth.Callback, Error>) in
                lock.lock()
                if let result { lock.unlock(); continuation.resume(with: result); return }
                guard !stopped else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                callback = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
                    catch { return }
                    self?.finish(.failure(ChatGPTSubscriptionError.callbackTimedOut))
                }
                lock.unlock()
            }
        } onCancel: { self.finish(.failure(CancellationError())) }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else { finishReady(.failure(ChatGPTSubscriptionError.listenerUnavailable)); return }
            var components = URLComponents()
            components.scheme = "http"; components.host = "127.0.0.1"; components.port = Int(port.rawValue); components.path = "/auth/callback"
            guard let url = components.url else { finishReady(.failure(ChatGPTSubscriptionError.listenerUnavailable)); return }
            finishReady(.success(url))
        case .failed: finishReady(.failure(ChatGPTSubscriptionError.listenerUnavailable)); finish(.failure(ChatGPTSubscriptionError.listenerUnavailable))
        case .cancelled: finishReady(.failure(CancellationError()))
        default: break
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        guard accumulated.count < 16_384 else { connection.cancel(); finish(.failure(ChatGPTSubscriptionError.invalidCallback)); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384 - accumulated.count) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            if error != nil { connection.cancel(); return }
            var bytes = accumulated
            if let data { bytes.append(data) }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                let expectedHost = "127.0.0.1:\(self.listener.port?.rawValue ?? 0)"
                guard let parsed = ChatGPTSubscriptionOAuth.parseCallbackRequest(Data(bytes[..<end.upperBound]), expectedHost: expectedHost) else {
                    self.respond(connection, status: 400, message: "Invalid sign-in response.")
                    self.finish(.failure(ChatGPTSubscriptionError.invalidCallback)); return
                }
                self.respond(connection, status: 200, message: "Sign-in response received. Return to Foliance.")
                self.finish(.success(parsed)); return
            }
            if complete { connection.cancel(); self.finish(.failure(ChatGPTSubscriptionError.invalidCallback)) }
            else { self.receive(connection, accumulated: bytes) }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, message: String) {
        let body = "<!doctype html><meta charset=utf-8><title>Foliance</title><p>\(message)</p>"
        let data = Data(body.utf8)
        let response = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8) + data
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finishReady(_ value: Result<URL, Error>) {
        lock.lock(); let continuation = ready; ready = nil; lock.unlock()
        continuation?.resume(with: value)
    }

    private func finish(_ value: Result<ChatGPTSubscriptionOAuth.Callback, Error>) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true; result = value
        let continuation = callback; callback = nil
        let readyContinuation = ready; ready = nil
        let timer = timeout; timeout = nil
        lock.unlock()
        timer?.cancel(); listener.cancel()
        readyContinuation?.resume(throwing: value.failure ?? CancellationError())
        continuation?.resume(with: value)
    }
}

private extension Result where Success == ChatGPTSubscriptionOAuth.Callback, Failure == Error {
    var failure: Error? { if case .failure(let error) = self { return error }; return nil }
}
