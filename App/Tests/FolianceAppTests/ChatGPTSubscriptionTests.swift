import Foundation
import XCTest
@testable import FolianceApp

final class ChatGPTSubscriptionTests: XCTestCase {
    func testFirstAuthorizationUsesDynamicRegistrationAndFullScopeSet() throws {
        let url = try ChatGPTSubscriptionOAuth.authorizationURL(
            clientID: ChatGPTSubscriptionOAuth.dynamicClientID,
            callbackURI: "http://127.0.0.1:1455/auth/callback",
            state: "fresh-state", nonce: "fresh-nonce", challenge: "challenge",
            hostID: "urn:uuid:abcd", reauthorization: false)
        let values = try queryValues(url)
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/api/accounts/authorize")
        XCTAssertEqual(values["client_id"], "dynamic_agent_client")
        XCTAssertEqual(values["agent_name_hint"], "Foliance")
        XCTAssertEqual(values["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(values["ext_agent_host_id"], "urn:uuid:abcd")
        XCTAssertEqual(values["state"], "fresh-state")
        XCTAssertEqual(values["nonce"], "fresh-nonce")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["code_challenge"], "challenge")
        XCTAssertEqual(Set((values["scope"] ?? "").split(separator: " ").map(String.init)), ChatGPTSubscriptionOAuth.requiredScopes)
        XCTAssertEqual(values["resource"], ChatGPTSubscriptionOAuth.resource)
        XCTAssertNil(values["id_token_hint"])
    }

    func testReturningAuthorizationUsesIssuedClientAndOmitsRegistrationName() throws {
        let url = try ChatGPTSubscriptionOAuth.authorizationURL(
            clientID: "oaiapp_issued-id", callbackURI: "http://127.0.0.1:55123/auth/callback",
            state: "state", nonce: "nonce", challenge: "challenge", hostID: "urn:uuid:abcd",
            reauthorization: true, idTokenHint: "old.id.token", loginHint: "reader@example.com", promptForConsent: true)
        let values = try queryValues(url)
        XCTAssertEqual(values["client_id"], "oaiapp_issued-id")
        XCTAssertNil(values["agent_name_hint"])
        XCTAssertEqual(values["id_token_hint"], "old.id.token")
        XCTAssertEqual(values["login_hint"], "reader@example.com")
        XCTAssertEqual(values["prompt"], "consent")
    }

    func testPKCEChallengeMatchesRFC7636Vector() {
        XCTAssertEqual(ChatGPTSubscriptionOAuth.pkceChallenge(
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testCallbackRequiresLoopbackRequestExactHostAndSingleParameters() throws {
        let valid = Data("GET /auth/callback?code=auth-code&state=expected&client_id=oaiapp_1 HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n".utf8)
        let callback = try XCTUnwrap(ChatGPTSubscriptionOAuth.parseCallbackRequest(valid, expectedHost: "127.0.0.1:1455"))
        XCTAssertTrue(ChatGPTSubscriptionOAuth.callbackMatches(callback, expectedState: "expected",
                                                                 expectedClientID: nil, isNewRegistration: true))
        XCTAssertFalse(ChatGPTSubscriptionOAuth.callbackMatches(callback, expectedState: "wrong",
                                                                  expectedClientID: nil, isNewRegistration: true))
        XCTAssertFalse(ChatGPTSubscriptionOAuth.callbackMatches(callback, expectedState: "expected",
                                                                  expectedClientID: "oaiapp_other", isNewRegistration: false))

        let wrongHost = Data("GET /auth/callback?code=c&state=s HTTP/1.1\r\nHost: localhost:1455\r\n\r\n".utf8)
        let duplicateState = Data("GET /auth/callback?code=c&state=s&state=other HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n".utf8)
        let wrongPath = Data("GET /callback?code=c&state=s HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n".utf8)
        XCTAssertNil(ChatGPTSubscriptionOAuth.parseCallbackRequest(wrongHost, expectedHost: "127.0.0.1:1455"))
        XCTAssertNil(ChatGPTSubscriptionOAuth.parseCallbackRequest(duplicateState, expectedHost: "127.0.0.1:1455"))
        XCTAssertNil(ChatGPTSubscriptionOAuth.parseCallbackRequest(wrongPath, expectedHost: "127.0.0.1:1455"))
    }

    func testRegistrationAndReturningCallbackClientIDRules() {
        let registration = ChatGPTSubscriptionOAuth.Callback(code: "code", state: "s",
            clientID: "oaiapp_issued", error: nil)
        XCTAssertTrue(ChatGPTSubscriptionOAuth.callbackMatches(registration, expectedState: "s",
                                                                 expectedClientID: nil, isNewRegistration: true))
        let missingRegistrationID = ChatGPTSubscriptionOAuth.Callback(code: "code", state: "s",
            clientID: nil, error: nil)
        XCTAssertFalse(ChatGPTSubscriptionOAuth.callbackMatches(missingRegistrationID, expectedState: "s",
                                                                  expectedClientID: nil, isNewRegistration: true))
        let returningWithoutID = ChatGPTSubscriptionOAuth.Callback(code: "code", state: "s",
            clientID: nil, error: nil)
        XCTAssertTrue(ChatGPTSubscriptionOAuth.callbackMatches(returningWithoutID, expectedState: "s",
                                                                 expectedClientID: "oaiapp_issued", isNewRegistration: false))
        let returningWithChangedID = ChatGPTSubscriptionOAuth.Callback(code: "code", state: "s",
            clientID: "oaiapp_other", error: nil)
        XCTAssertFalse(ChatGPTSubscriptionOAuth.callbackMatches(returningWithChangedID, expectedState: "s",
                                                                  expectedClientID: "oaiapp_issued", isNewRegistration: false))
    }

    func testGrantedDirectScopeIsRequiredForPlanUsage() {
        XCTAssertTrue(ChatGPTSubscriptionOAuth.hasPlanScope(
            "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"))
        XCTAssertFalse(ChatGPTSubscriptionOAuth.hasPlanScope(
            "openid profile email offline_access resource.invoke"))
    }

    func testSavedConnectionRequiresRetainedSessionTokens() {
        XCTAssertTrue(ChatGPTSubscriptionOAuth.hasSavedSession(subject: "subject", accessToken: "access", refreshToken: "refresh"))
        XCTAssertTrue(ChatGPTSubscriptionOAuth.hasSavedSession(subject: "subject", accessToken: nil, refreshToken: "refresh"))
        XCTAssertFalse(ChatGPTSubscriptionOAuth.hasSavedSession(subject: "subject", accessToken: nil, refreshToken: nil))
        XCTAssertFalse(ChatGPTSubscriptionOAuth.hasSavedSession(subject: "", accessToken: "access", refreshToken: "refresh"))
    }

    func testModelCatalogUsesVisibleUniqueSafeAccountModels() throws {
        let json = """
        {"models":[
          {"slug":"gpt-5.4-mini","display_name":"GPT 5.4 mini","visibility":"list","supported_reasoning_levels":["low","medium","low","unsupported"]},
          {"slug":"hidden-model","display_name":"Hidden","visibility":"hidden","supported_reasoning_levels":["high"]},
          {"slug":"gpt-5.4-mini","display_name":"Duplicate","visibility":"list"},
          {"slug":"bad/model","display_name":"Unsafe","visibility":"list"},
          {"slug":"gpt-next","display_name":"Next","visibility":"list","supported_reasoning_levels":[{"effort":"high"}]}
        ]}
        """
        let models = try ChatGPTSubscriptionOAuth.parseModels(Data(json.utf8))
        XCTAssertEqual(models.map(\.id), ["gpt-5.4-mini", "gpt-next"])
        XCTAssertEqual(models.first?.displayName, "GPT 5.4 mini")
        XCTAssertEqual(models.first?.reasoningEfforts, ["low", "medium"])
        XCTAssertEqual(models.last?.reasoningEfforts, ["high"])
    }

    func testCatalogFallbacksApplyOnlyToKnownModelsWhenFieldIsOmitted() throws {
        let json = """
        {"models":[
          {"slug":"gpt-6.1-sol","display_name":"Sol","visibility":"list"},
          {"slug":"gpt-6-luna","display_name":"Luna","visibility":"list"},
          {"slug":"gpt-7-sol-preview","display_name":"Unknown family","visibility":"list"}
        ]}
        """
        let models = try ChatGPTSubscriptionOAuth.parseModels(Data(json.utf8))
        XCTAssertEqual(models.map(\.id), ["gpt-6.1-sol", "gpt-6-luna", "gpt-7-sol-preview"])
        XCTAssertEqual(models[0].reasoningEfforts, ["low", "medium", "high", "xhigh", "max"])
        XCTAssertEqual(models[1].reasoningEfforts, ["none", "low", "medium", "high", "xhigh", "max"])
        XCTAssertEqual(models[2].reasoningEfforts, [])

        let explicitLevels = """
        {"models":[
          {"slug":"gpt-6.1-sol","display_name":"Explicit empty","visibility":"list","supported_reasoning_levels":[]},
          {"slug":"gpt-6-luna","display_name":"Advertised","visibility":"list","supported_reasoning_levels":["medium","none","medium","unsupported"]}
        ]}
        """
        let explicitModels = try ChatGPTSubscriptionOAuth.parseModels(Data(explicitLevels.utf8))
        XCTAssertEqual(explicitModels.map(\.reasoningEfforts), [[], ["medium", "none"]])
    }

    func testOIDCVerificationRequiresSignatureIssuerAudienceExpiryNonceAndSubject() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let jwks = Data(#"{"keys":[{"kid":"test-key","kty":"RSA","use":"sig","n":"AQAB","e":"Aw"}]}"#.utf8)
        let token = try idToken(issuer: ChatGPTSubscriptionOAuth.issuer, audience: "oaiapp_1",
                                expiry: 3_000, nonce: "nonce", subject: "subject")
        var checkedSignedInput = false
        let identity = try ChatGPTSubscriptionOAuth.verifyIDToken(token, jwksData: jwks, audience: "oaiapp_1",
            nonce: "nonce", expectedSubject: "subject", now: now,
            signatureCheck: { signed, signature, key in
                checkedSignedInput = !signed.isEmpty && !signature.isEmpty && key.first == 0x30
                return checkedSignedInput
            })
        XCTAssertEqual(identity.subject, "subject")
        XCTAssertEqual(identity.email, "person@example.com")
        XCTAssertTrue(checkedSignedInput)

        let wrongNonce = try idToken(issuer: ChatGPTSubscriptionOAuth.issuer, audience: "oaiapp_1",
                                     expiry: 3_000, nonce: "other", subject: "subject")
        XCTAssertThrowsError(try ChatGPTSubscriptionOAuth.verifyIDToken(wrongNonce, jwksData: jwks, audience: "oaiapp_1",
            nonce: "nonce", expectedSubject: "subject", now: now, signatureCheck: { _, _, _ in true }))
        XCTAssertThrowsError(try ChatGPTSubscriptionOAuth.verifyIDToken(token, jwksData: jwks, audience: "wrong-client",
            nonce: "nonce", now: now, signatureCheck: { _, _, _ in true }))
        XCTAssertThrowsError(try ChatGPTSubscriptionOAuth.verifyIDToken(token, jwksData: jwks, audience: "oaiapp_1",
            nonce: "nonce", expectedSubject: "other", now: now, signatureCheck: { _, _, _ in true }))
        let expired = try idToken(issuer: ChatGPTSubscriptionOAuth.issuer, audience: "oaiapp_1",
                                  expiry: 1_999, nonce: "nonce", subject: "subject")
        XCTAssertThrowsError(try ChatGPTSubscriptionOAuth.verifyIDToken(expired, jwksData: jwks, audience: "oaiapp_1",
            nonce: "nonce", now: now, signatureCheck: { _, _, _ in true }))
        XCTAssertThrowsError(try ChatGPTSubscriptionOAuth.verifyIDToken(token, jwksData: jwks, audience: "oaiapp_1",
            nonce: "nonce", now: now, signatureCheck: { _, _, _ in false }))
    }

    func testOAuthFormsEncodeRefreshAndRevocationWithoutPuttingTokensInURLs() throws {
        let refreshData = ChatGPTSubscriptionOAuth.formBody([
            "grant_type": "refresh_token", "client_id": "oaiapp_1",
            "refresh_token": "refresh+secret", "resource": ChatGPTSubscriptionOAuth.resource
        ])
        let refresh = try queryValues(URLComponents(string: "https://example.invalid/?" + String(decoding: refreshData, as: UTF8.self))!.url!)
        XCTAssertEqual(refresh["grant_type"], "refresh_token")
        XCTAssertEqual(refresh["client_id"], "oaiapp_1")
        XCTAssertEqual(refresh["refresh_token"], "refresh+secret")
        XCTAssertEqual(refresh["resource"], ChatGPTSubscriptionOAuth.resource)

        let revokeData = ChatGPTSubscriptionOAuth.formBody([
            "token": "refresh+secret", "token_type_hint": "refresh_token", "client_id": "oaiapp_1"
        ])
        let revoke = try queryValues(URLComponents(string: "https://example.invalid/?" + String(decoding: revokeData, as: UTF8.self))!.url!)
        XCTAssertEqual(revoke["token"], "refresh+secret")
        XCTAssertEqual(revoke["token_type_hint"], "refresh_token")
        XCTAssertEqual(revoke["client_id"], "oaiapp_1")
    }

    func testSubscriptionKeychainAndHostIDAreFolianceOnlyAndDoNotReuseBYOKNamespace() {
        XCTAssertEqual(ChatGPTSubscriptionStorageIdentity.keychainService, "app.foliance.mac.chatgpt-subscription")
        XCTAssertEqual(ChatGPTSubscriptionStorageIdentity.activeClientIDDefaultsKey, "foliance.chatGPTSubscription.activeClientID")
        XCTAssertNotEqual(ChatGPTSubscriptionStorageIdentity.keychainService, OpenAIKeychainStore.service)
        XCTAssertEqual(ChatGPTSubscriptionStorageIdentity.hostIDDefaultsKey, "foliance.chatGPTSubscription.extAgentHostID")
    }

    func testInjectedCredentialStoreKeepsRegistrationsSeparateAndSwitchesActiveAccount() async throws {
        let store = MemorySubscriptionCredentialStore(credentials: [
            subscriptionCredential(clientID: "oaiapp_one", subject: "sub-one", email: "one@example.com", token: "token-one"),
            subscriptionCredential(clientID: "oaiapp_two", subject: "sub-two", email: "two@example.com", token: "token-two")
        ], activeClientID: "oaiapp_one")
        let connection = ChatGPTSubscriptionConnection(store: store)

        let firstProfileValue = await connection.savedProfile()
        let firstProfile = try XCTUnwrap(firstProfileValue)
        XCTAssertEqual(firstProfile.subject, "sub-one")
        XCTAssertEqual(firstProfile.email, "one@example.com")

        let snapshot = await connection.accountSnapshot()
        XCTAssertEqual(snapshot.selectedID, "oaiapp_one")
        XCTAssertEqual(snapshot.accounts.map(\.id), ["oaiapp_one", "oaiapp_two"])
        XCTAssertTrue(snapshot.accounts.allSatisfy(\.isConnected))
        XCTAssertTrue(snapshot.accounts[0].label.contains("one@example.com"))
        XCTAssertTrue(snapshot.accounts[1].label.contains("two@example.com"))

        let secondProfileValue = await connection.selectAccount(id: "oaiapp_two")
        let secondProfile = try XCTUnwrap(secondProfileValue)
        XCTAssertEqual(secondProfile.subject, "sub-two")
        let switchedSnapshot = await connection.accountSnapshot()
        XCTAssertEqual(switchedSnapshot.selectedID, "oaiapp_two")
        let stored = try store.loadAll()
        XCTAssertEqual(stored.first(where: { $0.clientID == "oaiapp_one" })?.accessToken, "token-one")
        XCTAssertEqual(stored.first(where: { $0.clientID == "oaiapp_two" })?.accessToken, "token-two")
        XCTAssertEqual(store.activeClientID(), "oaiapp_two")

        let restoredConnection = ChatGPTSubscriptionConnection(store: store)
        let restoredProfileValue = await restoredConnection.savedProfile()
        let restoredProfile = try XCTUnwrap(restoredProfileValue)
        XCTAssertEqual(restoredProfile.subject, "sub-two")
        let restoredSnapshot = await restoredConnection.accountSnapshot()
        XCTAssertEqual(restoredSnapshot.accounts.map(\.id), ["oaiapp_one", "oaiapp_two"])
    }

    func testSignedOutRegistrationRemainsSelectableWithoutShowingConnected() async throws {
        let store = MemorySubscriptionCredentialStore(credentials: [
            subscriptionCredential(clientID: "oaiapp_saved", subject: "sub-saved", email: "saved@example.com", token: nil)
        ], activeClientID: "oaiapp_saved")
        let connection = ChatGPTSubscriptionConnection(store: store)

        let noProfile = await connection.savedProfile()
        XCTAssertNil(noProfile)
        let snapshot = await connection.accountSnapshot()
        XCTAssertEqual(snapshot.accounts.count, 1)
        XCTAssertEqual(snapshot.accounts.first?.id, "oaiapp_saved")
        XCTAssertFalse(try XCTUnwrap(snapshot.accounts.first).isConnected)
        let missing = await connection.selectAccount(id: "missing")
        XCTAssertNil(missing)
        let selected = await connection.selectAccount(id: "oaiapp_saved")
        XCTAssertNil(selected)
        XCTAssertEqual(store.activeClientID(), "oaiapp_saved")

        let signOutConfirmed = await connection.signOut()
        XCTAssertTrue(signOutConfirmed)
        let afterSignOut = await connection.accountSnapshot()
        XCTAssertEqual(afterSignOut.accounts.map(\.id), ["oaiapp_saved"])
        XCTAssertFalse(try XCTUnwrap(afterSignOut.accounts.first).isConnected)
        XCTAssertEqual(afterSignOut.selectedID, "oaiapp_saved")
    }

    private func subscriptionCredential(clientID: String, subject: String, email: String, token: String?) -> ChatGPTSubscriptionCredential {
        ChatGPTSubscriptionCredential(clientID: clientID, hostID: "urn:uuid:shared-host", subject: subject,
            email: email, idToken: token.map { "id-\($0)" }, accessToken: token, refreshToken: token.map { "refresh-\($0)" },
            expiresAt: token == nil ? nil : Date(timeIntervalSince1970: 4_000_000_000), scopes: token == nil ? [] : Array(ChatGPTSubscriptionOAuth.planScopes))
    }

    private func queryValues(_ url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private func idToken(issuer: String, audience: String, expiry: TimeInterval,
                        nonce: String, subject: String) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test-key"])
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": issuer, "aud": [audience], "exp": expiry, "nonce": nonce,
            "sub": subject, "email": "person@example.com"
        ])
        return [ChatGPTSubscriptionOAuth.base64URL(header), ChatGPTSubscriptionOAuth.base64URL(claims), "c2ln"].joined(separator: ".")
    }
}

private final class MemorySubscriptionCredentialStore: ChatGPTSubscriptionCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: Data]
    private var selectedID: String?

    init(credentials: [ChatGPTSubscriptionCredential], activeClientID: String?) {
        rows = Dictionary(uniqueKeysWithValues: credentials.compactMap { credential in
            guard let data = try? JSONEncoder().encode(credential) else { return nil }
            return (credential.clientID, data)
        })
        selectedID = activeClientID
    }

    func loadAll() throws -> [ChatGPTSubscriptionCredential] {
        lock.lock(); defer { lock.unlock() }
        return try rows.values.map { try JSONDecoder().decode(ChatGPTSubscriptionCredential.self, from: $0) }
    }

    func save(_ credential: ChatGPTSubscriptionCredential) throws {
        let data = try JSONEncoder().encode(credential)
        lock.lock(); rows[credential.clientID] = data; lock.unlock()
    }

    func activeClientID() -> String? { lock.lock(); defer { lock.unlock() }; return selectedID }

    func setActiveClientID(_ clientID: String?) { lock.lock(); selectedID = clientID; lock.unlock() }
}
