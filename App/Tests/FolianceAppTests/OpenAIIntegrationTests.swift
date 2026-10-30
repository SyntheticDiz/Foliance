import Foundation
import XCTest
@testable import FolianceApp

final class OpenAIIntegrationTests: XCTestCase {
    func testCredentialsUseInjectedSecretStoreAndNeverWriteKeyToDefaults() throws {
        let suite = "Foliance-OpenAISecret-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryOpenAISecretStore()
        let credentials = OpenAICredentials(store: store)

        try credentials.save("  sk-test-secret  ")

        XCTAssertTrue(credentials.hasAPIKey)
        XCTAssertEqual(try credentials.apiKey(), "sk-test-secret")
        XCTAssertNil(defaults.string(forKey: "openAIAPIKey"))
        XCTAssertNil(defaults.string(forKey: "apiKey"))
        XCTAssertEqual(OpenAIKeychainStore.service, "app.foliance.mac.openai")
        XCTAssertEqual(OpenAIKeychainStore.account, "api-key")
        try credentials.remove()
        XCTAssertFalse(credentials.hasAPIKey)
    }

    func testInvalidAPIKeysAreRejectedBeforeSecretStoreWrite() throws {
        let store = MemoryOpenAISecretStore()
        let credentials = OpenAICredentials(store: store)
        let invalidValues = [
            "key with space",
            "key\nAuthorization: Bearer injected",
            "key\tvalue",
            String(repeating: "x", count: OpenAICredentials.maximumKeyLength + 1)
        ]
        for invalid in invalidValues {
            XCTAssertThrowsError(try credentials.save(invalid)) { error in
                XCTAssertEqual(error.localizedDescription, "Enter a valid API key without spaces or control characters.")
                XCTAssertFalse(error.localizedDescription.contains(invalid))
            }
            XCTAssertNil(try credentials.apiKey())
            XCTAssertFalse(credentials.hasAPIKey)
        }
        try credentials.save("  vendor-key-without-prefix  ")
        XCTAssertEqual(try credentials.apiKey(), "vendor-key-without-prefix")
    }

    func testConsentCanBeGrantedAndRevokedWithoutPersistingDocumentContent() throws {
        let suite = "Foliance-OpenAIConsent-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(OpenAIConsent.isGranted(defaults: defaults))
        OpenAIConsent.grant(defaults: defaults)
        XCTAssertTrue(OpenAIConsent.isGranted(defaults: defaults))
        XCTAssertEqual(defaults.integer(forKey: OpenAIConsent.defaultsKey), OpenAIConsent.version)
        XCTAssertNil(defaults.string(forKey: "documentText"))
        OpenAIConsent.revoke(defaults: defaults)
        XCTAssertFalse(OpenAIConsent.isGranted(defaults: defaults))
    }

    func testResponsesRequestUsesBearerKeyStructuredOutputAndStoreFalse() async throws {
        OpenAIURLProtocolFixture.reset(responseCode: 200, body: Self.completedEvent)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
        let captured = PreparedRequestCollector()

        let result = try await ChatGPTService.responseForTesting(
            body: requestBody(), key: { "sk-test-secret" }, consent: { true },
            endpoint: ChatGPTService.endpoint, configuration: configuration,
            capturePreparedRequest: { await captured.save($0) })

        XCTAssertEqual(result, "{\"question\":\"What is the deadline?\",\"sourceID\":\"p1\"}")
        let preparedRequest = await captured.value
        let request = try XCTUnwrap(preparedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["store"] as? Bool, false)
        XCTAssertEqual(payload["stream"] as? Bool, true)
        XCTAssertEqual(payload["model"] as? String, "gpt-5.4-mini")
        XCTAssertNil(payload["api_key"])
        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        XCTAssertEqual(input.first?["content"] as? String, "Reader goal: compare the proposed dates.\nDocument source: exact source excerpt")
        let text = try XCTUnwrap(payload["text"] as? [String: Any])
        let format = try XCTUnwrap(text["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "apple_question")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("sk-test-secret"))
    }

    func testConsentAndKeyAreRequiredBeforeNetworkRequest() async {
        for (key, consent) in [(Optional<String>.some("sk-test"), false), (nil, true)] {
            OpenAIURLProtocolFixture.reset(responseCode: 200, body: Self.completedEvent)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
            do {
                _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { key }, consent: { consent },
                                                                endpoint: ChatGPTService.endpoint, configuration: configuration)
                XCTFail("A missing consent or key must block transmission.")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("API key"))
                XCTAssertTrue(OpenAIURLProtocolFixture.requests.isEmpty)
            }
        }
    }

    func testConsentIsCheckedAgainForEachNetworkRequest() async throws {
        OpenAIURLProtocolFixture.reset(responseCode: 200, body: Self.completedEvent)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
        var consent = true
        _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { "sk-test" }, consent: { consent },
                                                        endpoint: ChatGPTService.endpoint, configuration: configuration)
        consent = false
        do {
            _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { "sk-test" }, consent: { consent },
                                                            endpoint: ChatGPTService.endpoint, configuration: configuration)
            XCTFail("A revoked consent must block a subsequent request.")
        } catch {
            XCTAssertEqual(OpenAIURLProtocolFixture.requests.count, 1)
        }
    }

    func testUnauthorizedAndRateLimitedResponsesHaveEnglishRecoveryMessages() async {
        for (status, expected) in [(401, "rejected this API key"), (403, "denied access"), (429, "limited this request")] {
            OpenAIURLProtocolFixture.reset(responseCode: status, body: Data("{}".utf8), headers: ["Retry-After": "2"])
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
            do {
                _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { "sk-test" }, consent: { true },
                                                                endpoint: ChatGPTService.endpoint, configuration: configuration)
                XCTFail("Expected HTTP \(status).")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
                XCTAssertTrue(error.localizedDescription.range(of: #"[\u0600-\u06FF]"#, options: .regularExpression) == nil)
            }
        }
    }

    func testCancelledRequestNeverReachesTransport() async {
        OpenAIURLProtocolFixture.reset(responseCode: 200, body: Self.completedEvent)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
        let gate = OpenAIRequestGate()
        let task = Task {
            await gate.wait()
            _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { "sk-test" }, consent: { true },
                                                           endpoint: ChatGPTService.endpoint, configuration: configuration)
        }
        task.cancel()
        await gate.open()
        do { _ = try await task.value; XCTFail("Expected cancellation.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(OpenAIURLProtocolFixture.requests.isEmpty)
    }

    func testCrossHostRedirectIsRejected() async {
        OpenAIURLProtocolFixture.reset(responseCode: 302, body: Data(), headers: ["Location": "https://attacker.example/collect"])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIURLProtocolFixture.self]
        do {
            _ = try await ChatGPTService.responseForTesting(body: requestBody(), key: { "sk-test" }, consent: { true },
                                                            endpoint: ChatGPTService.endpoint, configuration: configuration)
            XCTFail("Expected redirect response to be rejected.")
        } catch {
            XCTAssertEqual(OpenAIURLProtocolFixture.requests.count, 1)
            XCTAssertEqual(OpenAIURLProtocolFixture.requests.first?.url?.host, "api.openai.com")
            XCTAssertFalse(OpenAIURLProtocolFixture.requests.contains { $0.url?.host == "attacker.example" })
        }
    }

    private func requestBody() -> [String: Any] {
        ["model": "chatgpt:gpt-5.4-mini:auto", "instructions": "Respond in English.",
         "input": "Reader goal: compare the proposed dates.\nDocument source: exact source excerpt",
         "text": ["format": ["name": "apple_question"]]]
    }

    private static let completedEvent = Data((
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"{\\\"question\\\":\\\"What is the deadline?\\\",\\\"sourceID\\\":\\\"p1\\\"}\"}\n\n" +
        "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
    ).utf8)
}

private final class MemoryOpenAISecretStore: OpenAISecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: String?
    func read() throws -> String? { lock.lock(); defer { lock.unlock() }; return secret }
    func contains() throws -> Bool { lock.lock(); defer { lock.unlock() }; return secret != nil }
    func save(_ value: String) throws { lock.lock(); defer { lock.unlock() }; secret = value }
    func delete() throws { lock.lock(); defer { lock.unlock() }; secret = nil }
}

private actor OpenAIRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor PreparedRequestCollector {
    private(set) var value: URLRequest?
    func save(_ request: URLRequest) { value = request }
}

private final class OpenAIURLProtocolFixture: URLProtocol {
    private static let lock = NSLock()
    private static var storedRequests: [URLRequest] = []
    private static var statusCode = 200
    private static var responseBody = Data()
    private static var responseHeaders: [String: String] = [:]
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storedRequests }

    static func reset(responseCode: Int, body: Data, headers: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        storedRequests = []; statusCode = responseCode; responseBody = body; responseHeaders = headers
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.storedRequests.append(Self.copyRequestWithCapturedBody(request))
        let status = Self.statusCode
        let body = Self.responseBody
        let headers = Self.responseHeaders
        Self.lock.unlock()

        guard let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
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
