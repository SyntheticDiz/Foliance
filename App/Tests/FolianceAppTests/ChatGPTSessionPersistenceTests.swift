import Foundation
import XCTest
@testable import FolianceApp

final class ChatGPTSessionPersistenceTests: XCTestCase {
    func testRestoredAccountRenewsExpiredTokenAndReloadsCatalogWithoutOpeningBrowser() async throws {
        let credential = makeCredential(expiry: Date(timeIntervalSince1970: 1))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { request in
            switch request.url?.path {
            case "/.well-known/openid-configuration":
                return .init(status: 200, body: Self.discovery)
            case "/api/accounts/oauth/token":
                return .init(status: 200, body: Self.tokenResponse(access: "fresh-access", refresh: "fresh-refresh"))
            case "/v1/models":
                return .init(status: 200, body: Self.modelCatalog)
            default:
                return .init(status: 404, body: Data())
            }
        }
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())
        let account = await MainActor.run {
            ChatGPTSubscriptionAccount(connection: connection, shouldLoadCatalogAutomatically: { true })
        }

        await account.restoreSessionIfNeeded()

        let state = await MainActor.run { (account.isConnected, account.canUsePlan, account.email, account.selectedAccountID, account.models) }
        XCTAssertTrue(state.0)
        XCTAssertTrue(state.1)
        XCTAssertEqual(state.2, credential.email)
        XCTAssertEqual(state.3, credential.clientID)
        XCTAssertEqual(state.4.map(\.id), ["gpt-6.1-sol"])
        let saved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(saved.clientID, credential.clientID)
        XCTAssertEqual(saved.hostID, credential.hostID)
        XCTAssertEqual(saved.accessToken, "fresh-access")
        XCTAssertEqual(saved.refreshToken, "fresh-refresh")
        XCTAssertTrue(SessionURLProtocolFixture.requests.contains { $0.url?.path == "/v1/models" })
        XCTAssertFalse(SessionURLProtocolFixture.requests.contains { $0.url?.path == "/api/accounts/authorize" })
    }

    func testSavedAccountRestoresWithoutNetworkWhenPlanProviderIsNotSelected() async throws {
        let credential = makeCredential(expiry: Date().addingTimeInterval(600))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { _ in .init(status: 500, body: Data()) }
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())
        let account = await MainActor.run {
            ChatGPTSubscriptionAccount(connection: connection, shouldLoadCatalogAutomatically: { false })
        }

        await account.restoreSessionIfNeeded()

        let state = await MainActor.run { (account.isConnected, account.canUsePlan, account.models, account.didRestoreSession) }
        XCTAssertTrue(state.0)
        XCTAssertTrue(state.1)
        XCTAssertTrue(state.2.isEmpty)
        XCTAssertTrue(state.3)
        XCTAssertTrue(SessionURLProtocolFixture.requests.isEmpty)
    }

    func testTransientKeychainReadFailureCanBeRetriedAndDoesNotCacheEmptyAccounts() async throws {
        let credential = makeCredential(expiry: Date().addingTimeInterval(600))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        store.setReadFailure(true)
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())

        do {
            _ = try await connection.accountSnapshot()
            XCTFail("A failed Keychain read must surface instead of looking like an empty account list.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }

        let account = await MainActor.run {
            ChatGPTSubscriptionAccount(connection: connection, shouldLoadCatalogAutomatically: { false }, automaticallyRestore: false)
        }
        await account.restoreSessionIfNeeded()
        let failedRestore = await MainActor.run { (account.didRestoreSession, account.isConnected, account.error) }
        XCTAssertFalse(failedRestore.0)
        XCTAssertFalse(failedRestore.1)
        XCTAssertNotNil(failedRestore.2)

        store.setReadFailure(false)
        await account.restoreSessionIfNeeded()
        let retriedRestore = await MainActor.run { (account.didRestoreSession, account.isConnected) }
        XCTAssertTrue(retriedRestore.0)
        XCTAssertTrue(retriedRestore.1)
        let restoredProfile = try await connection.savedProfile()
        let profile = try XCTUnwrap(restoredProfile)
        XCTAssertEqual(profile.subject, credential.subject)
        let snapshot = try await connection.accountSnapshot()
        XCTAssertEqual(snapshot.accounts.map(\.id), [credential.clientID])
    }

    func testTransientNetworkOrKeychainSaveFailurePreservesTokensForRetry() async throws {
        let credential = makeCredential(expiry: Date(timeIntervalSince1970: 1))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" {
                return .init(status: 503, body: Data())
            }
            return .init(status: 404, body: Data())
        }
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())

        do {
            _ = try await connection.accessToken()
            XCTFail("The temporary discovery failure should fail the request.")
        } catch { }
        XCTAssertEqual(try store.loadAll().first?.accessToken, credential.accessToken)
        XCTAssertEqual(try store.loadAll().first?.refreshToken, credential.refreshToken)

        SessionURLProtocolFixture.configure { request in
            switch request.url?.path {
            case "/.well-known/openid-configuration": return .init(status: 200, body: Self.discovery)
            case "/api/accounts/oauth/token": return .init(status: 200, body: Self.tokenResponse(access: "rotated-access", refresh: "rotated-refresh"))
            default: return .init(status: 404, body: Data())
            }
        }
        store.setSaveFailure(true)
        do {
            _ = try await connection.accessToken()
            XCTFail("A locked Keychain must prevent using a rotated token that was not durably saved.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }
        XCTAssertEqual(try store.loadAll().first?.accessToken, credential.accessToken)
        XCTAssertEqual(try store.loadAll().first?.refreshToken, credential.refreshToken)

        store.setSaveFailure(false)
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/api/accounts/oauth/token" {
                return .init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            if request.url?.path == "/v1/models" { return .init(status: 200, body: Self.modelCatalog) }
            return .init(status: 404, body: Data())
        }
        let retriedAccess = try await connection.accessToken()
        XCTAssertEqual(retriedAccess, "rotated-access")
        let models = try await connection.refreshModels()
        XCTAssertEqual(models.map(\.id), ["gpt-6.1-sol"])
        XCTAssertFalse(SessionURLProtocolFixture.requests.contains { $0.url?.path == "/api/accounts/oauth/token" },
                       "The retry must persist and use the first rotated refresh token, not resubmit the consumed token.")
        let modelRequest = try XCTUnwrap(SessionURLProtocolFixture.requests.first { $0.url?.path == "/v1/models" })
        XCTAssertEqual(modelRequest.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
        XCTAssertEqual(try store.loadAll().first?.refreshToken, "rotated-refresh")
    }

    func testRefreshRequestsAreSerializedAndTerminalInvalidGrantClearsOnlyTokens() async throws {
        let credential = makeCredential(expiry: Date(timeIntervalSince1970: 1))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" {
                return .init(status: 200, body: Self.discovery)
            }
            if request.url?.path == "/api/accounts/oauth/token" {
                return .init(status: 200, body: Self.tokenResponse(access: "one-access", refresh: "one-refresh"))
            }
            return .init(status: 404, body: Data())
        }
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())

        async let first = connection.accessToken()
        async let second = connection.accessToken()
        let firstToken = try await first
        let secondToken = try await second
        XCTAssertEqual(firstToken, "one-access")
        XCTAssertEqual(secondToken, "one-access")
        XCTAssertEqual(SessionURLProtocolFixture.requests.filter { $0.url?.path == "/api/accounts/oauth/token" }.count, 1)

        let terminalStore = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" {
                return .init(status: 200, body: Self.discovery)
            }
            if request.url?.path == "/api/accounts/oauth/token" {
                return .init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            return .init(status: 404, body: Data())
        }
        let terminalConnection = ChatGPTSubscriptionConnection(store: terminalStore, session: makeSession())
        do {
            _ = try await terminalConnection.accessToken()
            XCTFail("A terminal invalid_grant should require the user to reconnect.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .refreshFailed)
        }
        let snapshot = try await terminalConnection.accountSnapshot()
        XCTAssertEqual(snapshot.accounts.map(\.id), [credential.clientID])
        XCTAssertFalse(try XCTUnwrap(snapshot.accounts.first).isConnected)
        let signedOut = try XCTUnwrap(try terminalStore.loadAll().first)
        XCTAssertNil(signedOut.accessToken)
        XCTAssertNil(signedOut.refreshToken)
        XCTAssertEqual(signedOut.subject, credential.subject)
        XCTAssertEqual(signedOut.email, credential.email)
        XCTAssertEqual(signedOut.clientID, credential.clientID)
        XCTAssertEqual(signedOut.hostID, credential.hostID)
    }

    func testSuccessfulSignOutRevokesAndClearsTokensButRetainsRegistration() async throws {
        let credential = makeCredential(expiry: Date().addingTimeInterval(600))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" {
                return .init(status: 200, body: Self.discovery)
            }
            if request.url?.path == "/api/accounts/oauth/revoke" { return .init(status: 200, body: Data()) }
            return .init(status: 404, body: Data())
        }
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())

        let revocationConfirmed = try await connection.signOut()
        XCTAssertTrue(revocationConfirmed)

        let saved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertNil(saved.idToken)
        XCTAssertNil(saved.accessToken)
        XCTAssertNil(saved.refreshToken)
        XCTAssertEqual(saved.subject, credential.subject)
        XCTAssertEqual(saved.email, credential.email)
        XCTAssertEqual(saved.clientID, credential.clientID)
        XCTAssertEqual(saved.hostID, credential.hostID)
        XCTAssertEqual(store.activeClientID(), credential.clientID)
        let revoke = try XCTUnwrap(SessionURLProtocolFixture.requests.first { $0.url?.path == "/api/accounts/oauth/revoke" })
        XCTAssertEqual(revoke.url?.host, "auth.openai.com")
    }

    func testPendingRotationIsNeverResentAndInvalidationClearsItAfterKeychainUnlock() async throws {
        let credential = makeCredential(expiry: Date(timeIntervalSince1970: 1))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())
        try await createPendingRotation(connection, store: store)

        do {
            try await connection.invalidateSession()
            XCTFail("The locked Keychain should keep the token-clearing record pending.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }
        XCTAssertEqual(try store.loadAll().first?.refreshToken, credential.refreshToken,
                       "The underlying locked store cannot be updated until Keychain access returns.")

        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/api/accounts/oauth/token" {
                return .init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            return .init(status: 404, body: Data())
        }
        do {
            _ = try await connection.accessToken()
            XCTFail("A pending token-clearing write must block every token request while Keychain is locked.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }
        XCTAssertFalse(SessionURLProtocolFixture.requests.contains { $0.url?.path == "/api/accounts/oauth/token" })

        store.setSaveFailure(false)
        do {
            _ = try await connection.accessToken()
            XCTFail("The cleared session must not return an access token after the pending write is saved.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .notConnected)
        }
        let cleared = try XCTUnwrap(try store.loadAll().first)
        XCTAssertNil(cleared.accessToken)
        XCTAssertNil(cleared.refreshToken)
        XCTAssertEqual(cleared.clientID, credential.clientID)
        XCTAssertEqual(cleared.hostID, credential.hostID)
    }

    func testSignOutRevokesPendingRotatedRefreshTokenAndKeepsClearPendingUntilSaved() async throws {
        let credential = makeCredential(expiry: Date(timeIntervalSince1970: 1))
        let store = SessionCredentialStore(credentials: [credential], activeClientID: credential.clientID)
        let connection = ChatGPTSubscriptionConnection(store: store, session: makeSession())
        try await createPendingRotation(connection, store: store)

        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" { return .init(status: 200, body: Self.discovery) }
            if request.url?.path == "/api/accounts/oauth/revoke" { return .init(status: 200, body: Data()) }
            return .init(status: 404, body: Data())
        }
        do {
            _ = try await connection.signOut()
            XCTFail("The locked Keychain should leave the cleared registration pending locally.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }
        let revoke = try XCTUnwrap(SessionURLProtocolFixture.requests.first { $0.url?.path == "/api/accounts/oauth/revoke" })
        let body = String(decoding: try XCTUnwrap(revoke.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("token=rotated-refresh"), "Sign-out must revoke the newest rotated token, not the consumed stored token.")
        XCTAssertEqual(try store.loadAll().first?.refreshToken, credential.refreshToken)

        store.setSaveFailure(false)
        do {
            _ = try await connection.accessToken()
            XCTFail("The cleared pending record must be saved before token lookup resumes.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .notConnected)
        }
        let saved = try XCTUnwrap(try store.loadAll().first)
        XCTAssertNil(saved.accessToken)
        XCTAssertNil(saved.refreshToken)
        XCTAssertEqual(saved.clientID, credential.clientID)
        XCTAssertEqual(saved.hostID, credential.hostID)
    }

    private func makeCredential(expiry: Date) -> ChatGPTSubscriptionCredential {
        ChatGPTSubscriptionCredential(clientID: "oaiapp-session-test", hostID: "urn:uuid:stable-host",
            subject: "subject-1", email: "reader@example.com", idToken: "validated-id-token",
            accessToken: "old-access", refreshToken: "old-refresh", expiresAt: expiry,
            scopes: Array(ChatGPTSubscriptionOAuth.requiredScopes))
    }

    private func createPendingRotation(_ connection: ChatGPTSubscriptionConnection,
                                       store: SessionCredentialStore) async throws {
        SessionURLProtocolFixture.configure { request in
            if request.url?.path == "/.well-known/openid-configuration" { return .init(status: 200, body: Self.discovery) }
            if request.url?.path == "/api/accounts/oauth/token" {
                return .init(status: 200, body: Self.tokenResponse(access: "rotated-access", refresh: "rotated-refresh"))
            }
            return .init(status: 404, body: Data())
        }
        store.setSaveFailure(true)
        do {
            _ = try await connection.accessToken()
            XCTFail("A Keychain write failure should preserve the first validated rotation in memory.")
        } catch {
            XCTAssertEqual(error as? ChatGPTSubscriptionError, .keychainFailure)
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionURLProtocolFixture.self]
        return URLSession(configuration: configuration)
    }

    private static let discovery = Data(#"{"issuer":"https://auth.openai.com","authorization_endpoint":"https://auth.openai.com/api/accounts/authorize","token_endpoint":"https://auth.openai.com/api/accounts/oauth/token","jwks_uri":"https://auth.openai.com/.well-known/jwks.json","revocation_endpoint":"https://auth.openai.com/api/accounts/oauth/revoke"}"#.utf8)
    private static let modelCatalog = Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT 6.1 Sol","visibility":"list","supported_reasoning_levels":["low","medium"]}]}"#.utf8)

    private static func tokenResponse(access: String, refresh: String) -> Data {
        Data(#"{"token_type":"Bearer","access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":3600}"#.utf8)
    }
}

private final class SessionCredentialStore: ChatGPTSubscriptionCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: Data]
    private var selectedID: String?
    private var readFailure = false
    private var saveFailure = false

    init(credentials: [ChatGPTSubscriptionCredential], activeClientID: String?) {
        rows = Dictionary(uniqueKeysWithValues: credentials.compactMap { credential in
            guard let data = try? JSONEncoder().encode(credential) else { return nil }
            return (credential.clientID, data)
        })
        selectedID = activeClientID
    }

    func loadAll() throws -> [ChatGPTSubscriptionCredential] {
        lock.lock(); defer { lock.unlock() }
        guard !readFailure else { throw ChatGPTSubscriptionError.keychainFailure }
        return try rows.values.map { try JSONDecoder().decode(ChatGPTSubscriptionCredential.self, from: $0) }
    }

    func save(_ credential: ChatGPTSubscriptionCredential) throws {
        let data = try JSONEncoder().encode(credential)
        lock.lock(); defer { lock.unlock() }
        guard !saveFailure else { throw ChatGPTSubscriptionError.keychainFailure }
        rows[credential.clientID] = data
    }

    func activeClientID() -> String? { lock.lock(); defer { lock.unlock() }; return selectedID }
    func setActiveClientID(_ clientID: String?) { lock.lock(); selectedID = clientID; lock.unlock() }
    func setReadFailure(_ value: Bool) { lock.lock(); readFailure = value; lock.unlock() }
    func setSaveFailure(_ value: Bool) { lock.lock(); saveFailure = value; lock.unlock() }
}

private final class SessionURLProtocolFixture: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { let status: Int; let body: Data }
    private static let lock = NSLock()
    private static var handler: (@Sendable (URLRequest) -> Reply)?
    private static var storedRequests: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storedRequests }

    static func configure(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        lock.lock(); self.handler = handler; storedRequests = []; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.storedRequests.append(Self.copyRequestWithCapturedBody(request))
        let reply = Self.handler?(request) ?? Reply(status: 500, body: Data())
        Self.lock.unlock()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func copyRequestWithCapturedBody(_ request: URLRequest) -> URLRequest {
        var captured = request
        guard let stream = request.httpBodyStream else { return captured }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        captured.httpBodyStream = nil
        captured.httpBody = data
        return captured
    }
}
