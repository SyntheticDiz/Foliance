import Foundation

/// Minimal text-only Responses transport using the user's OpenAI API key.
enum ChatGPTService {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    struct PreparedRequest {
        let model: String
        let effort: String
        let payload: [String: Any]
    }

    enum ChatGPTError: LocalizedError {
        case signInRequired
        case usageLimit
        case unclassified429(errorCode: String?, errorType: String?, retryAfter: TimeInterval?)
        case rateLimited(retryAfter: TimeInterval?)
        case temporarilyUnavailable(retryAfter: TimeInterval?)
        case planUsageLimit
        case quotaExceeded
        case http(Int)
        case invalidRequest
        case refused
        case incomplete
        case streamFailed
        case network

        var errorDescription: String? {
            switch self {
            case .signInRequired:
                return "OpenAI API is not ready. Add an API key in Settings and grant consent to send document content to OpenAI."
            case .usageLimit:
                return "OpenAI API usage or rate limit was reached. Check your API account usage and try again later."
            case .unclassified429(_, _, let retryAfter):
                let delay = retryAfter.map { " The server suggested waiting about \(String(format: "%.0f", ceil($0))) seconds." } ?? ""
                return "OpenAI API limited this request. The response does not identify whether this is temporary rate limiting or an account usage limit.\(delay) Try again later."
            case .rateLimited(let retryAfter):
                return retryMessage("OpenAI API is processing too many requests right now.", retryAfter: retryAfter)
            case .temporarilyUnavailable(let retryAfter):
                return retryMessage("OpenAI API is temporarily unavailable.", retryAfter: retryAfter)
            case .planUsageLimit:
                return "The OpenAI API account's configured usage limit was reached. Check the API account's usage settings."
            case .quotaExceeded:
                return "The OpenAI API account has insufficient quota or credit. Check API billing and usage limits."
            case .http(401):
                return "OpenAI rejected this API key (HTTP 401). Replace it in Settings with a valid key for your API account."
            case .http(403):
                return "OpenAI denied access (HTTP 403). Check the API key's project permissions and model access."
            case .http(400):
                return "OpenAI could not process this request. Check the model ID and request format."
            case .http(404):
                return "This model ID was not found or is not available to this API key. Check the exact model ID and account access."
            case .http(let status):
                return "OpenAI API returned an HTTP error (\(status)). Try again later."
            case .invalidRequest:
                return "Foliance could not prepare a supported OpenAI request or structured-output schema. Check the model ID and retry."
            case .refused:
                return "OpenAI declined this request. Review the question and source content, then try again."
            case .incomplete:
                return "OpenAI did not complete the response. Retry this analysis step."
            case .streamFailed:
                return "OpenAI could not finish the response. Check API key access and usage limits, then retry."
            case .network:
                return "The connection to OpenAI API failed. Check your internet connection and retry."
            }
        }

        private func retryMessage(_ message: String, retryAfter: TimeInterval?) -> String {
            guard let retryAfter else { return message + " Try again later." }
            return message + " Retry in about \(String(format: "%.0f", ceil(retryAfter))) seconds."
        }
    }

    static func response(body: [String: Any]) async throws -> String {
        if let model = body["model"] as? String, AIConfiguration.usesChatGPTPlan(model) {
            guard OpenAIConsent.isGranted() else { throw AppError(message: "Grant document-sharing consent in Settings before using your ChatGPT plan.") }
            let token = try await ChatGPTSubscriptionConnection.shared.accessToken()
            do {
                return try await perform(body: body, key: { token }, consent: { OpenAIConsent.isGranted() },
                                         endpoint: endpoint, configuration: .ephemeral)
            } catch let error as ChatGPTError {
                switch error {
                case .http(401):
                    await ChatGPTSubscriptionAccount.shared.invalidateAfterUnauthorizedResponse()
                    throw AppError(message: "Your ChatGPT connection is no longer authorized. Continue with ChatGPT again in Settings.")
                case .http(403):
                    throw AppError(message: "ChatGPT plan access was denied for this account, workspace or region. Check the connection and plan permissions in Settings.")
                case .planUsageLimit:
                    throw AppError(message: "ChatGPT plan usage has reached a limit. Check ChatGPT Settings → Usage. Foliance will not switch to API-key billing.")
                case .http(404):
                    throw AppError(message: "This model is not available to your ChatGPT account. Refresh the model list in Settings and choose an available model.")
                default: throw error
                }
            }
        }
        return try await perform(body: body,
                          key: { try OpenAICredentials.shared.apiKey() },
                          consent: { OpenAIConsent.isGranted() },
                          endpoint: endpoint,
                          configuration: .ephemeral)
    }

    /// Injection seam for offline URLProtocol tests. Production calls `response`.
    static func responseForTesting(body: [String: Any],
                                   key: @escaping () throws -> String?,
                                   consent: @escaping () -> Bool,
                                   endpoint: URL = endpoint,
                                   configuration: URLSessionConfiguration,
                                   capturePreparedRequest: @escaping @Sendable (URLRequest) async -> Void = { _ in }) async throws -> String {
        try await perform(body: body, key: key, consent: consent, endpoint: endpoint,
                          configuration: configuration, capturePreparedRequest: capturePreparedRequest)
    }

    private static func perform(body: [String: Any], key: () throws -> String?, consent: () -> Bool,
                                endpoint: URL, configuration suppliedConfiguration: URLSessionConfiguration,
                                capturePreparedRequest: @Sendable (URLRequest) async -> Void = { _ in }) async throws -> String {
        try Task.checkCancellation()
        guard consent() else { throw ChatGPTError.signInRequired }
        let apiKey: String
        do {
            guard let savedKey = try key()?.trimmingCharacters(in: .whitespacesAndNewlines), !savedKey.isEmpty else {
                throw ChatGPTError.signInRequired
            }
            apiKey = savedKey
        } catch let error as ChatGPTError { throw error }
        catch { throw ChatGPTError.signInRequired }
        let prepared = try prepare(body: body)

        var request = URLRequest(url: endpoint, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: prepared.payload, options: [.sortedKeys])
        } catch {
            throw ChatGPTError.invalidRequest
        }
        await capturePreparedRequest(request)

        let configuration = suppliedConfiguration
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        let redirectDelegate = RedirectRefuser()
        let session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw ChatGPTError.network }
            guard (200..<300).contains(http.statusCode) else {
                let body = try await boundedBody(from: bytes)
                let error = httpError(http.statusCode, headers: http.allHeaderFields, body: body)
                ChatGPTLimitDiagnostics.record(error, status: http.statusCode,
                                               errorCode: ChatGPTLimitDiagnostics.errorCode(in: body),
                                               errorType: ChatGPTLimitDiagnostics.errorType(in: body),
                                               responseShape: ChatGPTLimitDiagnostics.responseShape(in: body),
                                               detailSignal: http.statusCode == 429 ? ChatGPTLimitDiagnostics.detailSignal(in: body) : nil,
                                               requestID: ChatGPTLimitDiagnostics.requestID(in: http.allHeaderFields),
                                               retryAfterSeconds: retryAfterValue(headers: http.allHeaderFields, now: Date()))
                throw error
            }
            do {
                return try await collect(bytes: bytes)
            } catch let error as ChatGPTError {
                ChatGPTLimitDiagnostics.record(error, status: http.statusCode,
                                               requestID: ChatGPTLimitDiagnostics.requestID(in: http.allHeaderFields))
                throw error
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChatGPTError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw ChatGPTError.network
        }
    }

    static func prepare(body: [String: Any]) throws -> PreparedRequest {
        guard let encodedModel = body["model"] as? String,
              let selection = AIConfiguration.chatGPTSelection(encodedModel),
              let instructions = body["instructions"] as? String,
              let input = body["input"] as? String,
              let text = body["text"] as? [String: Any],
              let inputFormat = text["format"] as? [String: Any],
              let formatName = inputFormat["name"] as? String, !formatName.isEmpty else {
            throw ChatGPTError.invalidRequest
        }

        let format: [String: Any]
        if let type = inputFormat["type"] as? String,
           type == "json_schema",
           let schema = inputFormat["schema"] as? [String: Any] {
            format = ["type": "json_schema", "name": formatName, "strict": true, "schema": schema]
        } else {
            format = ["type": "json_schema", "name": formatName, "strict": true, "schema": try defaultSchema(named: formatName)]
        }

        // Construct an allowlisted payload: OAuth plan inference rejects many
        // ordinary Responses fields, including temperature and token limits.
        var payload: [String: Any] = [
            "model": selection.model,
            "instructions": instructions,
            "input": [["role": "user", "content": input]],
            "store": false,
            "stream": true,
            "text": ["format": format]
        ]
        if selection.effort != "auto" { payload["reasoning"] = ["effort": selection.effort] }
        guard JSONSerialization.isValidJSONObject(payload) else { throw ChatGPTError.invalidRequest }
        return PreparedRequest(model: selection.model, effort: selection.effort, payload: payload)
    }

    private static func defaultSchema(named name: String) throws -> [String: Any] {
        func string(_ description: String? = nil) -> [String: Any] {
            var value: [String: Any] = ["type": "string"]
            if let description { value["description"] = description }
            return value
        }
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "required": properties.keys.sorted(), "properties": properties]
        }
        switch name {
        case "apple_question":
            return object(["question": string(), "sourceID": string()])
        case "apple_evidence", "apple_program_evidence":
            let point = object(["title": string(), "summary": string(), "documentID": string(), "programID": string(), "relevance": string()])
            return object(["points": ["type": "array", "items": point, "maxItems": 2]])
        case "passage_neutral":
            let point = object(["title": string(), "summary": string(), "documentID": string(), "sourceIDs": ["type": "array", "items": string(), "maxItems": 8],
                                "relevanceClass": string(), "relevanceReason": string(),
                                "contextIDs": ["type": "array", "items": string(), "maxItems": 2]])
            return object(["points": ["type": "array", "items": point, "maxItems": 3]])
        case "passage_program":
            let point = object(["title": string(), "summary": string(), "documentID": string(), "sourceIDs": ["type": "array", "items": string(), "maxItems": 8], "programID": string(),
                                "relevance": string(), "relevanceClass": string(), "relevanceReason": string(),
                                "contextIDs": ["type": "array", "items": string(), "maxItems": 2]])
            return object(["points": ["type": "array", "items": point, "maxItems": 3]])
        case "apple_review":
            return object(["summary": string(), "relevance": string(), "sourceIDs": ["type": "array", "items": string(), "maxItems": 16]])
        default:
            throw ChatGPTError.invalidRequest
        }
    }

    static let maximumErrorBodyBytes = 65_536

    private static func boundedBody<Bytes: AsyncSequence>(from bytes: Bytes) async throws -> Data where Bytes.Element == UInt8 {
        var body = Data()
        body.reserveCapacity(maximumErrorBodyBytes)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count < maximumErrorBodyBytes else { break }
            body.append(byte)
        }
        return body
    }

    static func httpError(_ status: Int, headers: [AnyHashable: Any] = [:], body: Data = Data(), now: Date = Date()) -> ChatGPTError {
        let retryAfter = retryAfterValue(headers: headers, now: now)
        switch status {
        case 401, 403: return .http(status)
        case 429: return classifyError(body: body, fallback: .unclassified429(errorCode: nil, errorType: nil, retryAfter: retryAfter), retryAfter: retryAfter, partialOutput: false)
        case 503: return classifyError(body: body, fallback: .temporarilyUnavailable(retryAfter: retryAfter), retryAfter: retryAfter, partialOutput: false)
        default: return .http(status)
        }
    }

    static func retryAfterValue(headers: [AnyHashable: Any], now: Date) -> TimeInterval? {
        guard let field = headers.first(where: { String(describing: $0.key).caseInsensitiveCompare("Retry-After") == .orderedSame })?.value,
              let value = field as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let seconds: TimeInterval?
        if let number = TimeInterval(trimmed), number.isFinite, number >= 0 {
            seconds = number
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            formatter.isLenient = false
            seconds = formatter.date(from: trimmed).map { max(0, $0.timeIntervalSince(now)) }
        }
        guard let seconds, seconds.isFinite else { return nil }
        return seconds
    }

    private static func classifyError(body: Data, fallback: ChatGPTError, retryAfter: TimeInterval?, partialOutput: Bool) -> ChatGPTError {
        guard body.count <= maximumErrorBodyBytes,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return fallback }
        let error = json["error"] as? [String: Any]
        let code = error?["code"] as? String ?? ""
        let type = error?["type"] as? String ?? ""
        let classified = error == nil
            ? fallback
            : classify(code: code, type: type, fallback: fallback, retryAfter: retryAfter, partialOutput: partialOutput)
        if case .unclassified429 = classified {
            let signal = ChatGPTLimitDiagnostics.detailSignal(in: body)
            // A legacy detail string must not overrule an unknown structured
            // error code or type that may require account action.
            if code.isEmpty, type.isEmpty,
               retryAfter?.isFinite == true, let retryAfter, retryAfter >= 0, signal?.isStrongRateLimit == true {
                return .rateLimited(retryAfter: retryAfter)
            }
            return .unclassified429(errorCode: ChatGPTLimitDiagnostics.sanitizedTechnicalField(code),
                                    errorType: ChatGPTLimitDiagnostics.sanitizedTechnicalField(type),
                                    retryAfter: retryAfter)
        }
        return classified
    }

    private static func classify(code: String, type: String, fallback: ChatGPTError, retryAfter: TimeInterval?, partialOutput: Bool) -> ChatGPTError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .planUsageLimit
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable",
             "service_unavailable", "server_is_overloaded":
            return partialOutput ? .streamFailed : .temporarilyUnavailable(retryAfter: retryAfter)
        case "rate_limit_exceeded", "rate_limit_error", "slow_down":
            return partialOutput ? .streamFailed : .rateLimited(retryAfter: retryAfter)
        case "insufficient_quota", "billing_hard_limit_reached", "quota_exceeded", "credit_balance_exhausted",
             "organization_spend_limit_exceeded", "project_spend_limit_exceeded": return .quotaExceeded
        default: break
        }
        switch type {
        case "rate_limit_exceeded", "rate_limit_error", "slow_down":
            return partialOutput ? .streamFailed : .rateLimited(retryAfter: retryAfter)
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable", "service_unavailable", "server_is_overloaded":
            return partialOutput ? .streamFailed : .temporarilyUnavailable(retryAfter: retryAfter)
        case "insufficient_quota", "billing_hard_limit_reached", "quota_exceeded", "credit_balance_exhausted",
             "organization_spend_limit_exceeded", "project_spend_limit_exceeded": return .quotaExceeded
        default: return fallback
        }
    }

    private struct EventStreamParser {
        private var dataLines: [String] = []
        private(set) var output = ""
        private(set) var completed = false

        mutating func append(_ line: String) throws {
            if line.isEmpty {
                try dispatchPending()
            } else if line.hasPrefix(":") {
                return
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.first == " " { value.removeFirst() }
                dataLines.append(value)
            }
        }

        mutating func finish() throws {
            try dispatchPending()
            guard completed else { throw ChatGPTError.incomplete }
        }

        private mutating func dispatchPending() throws {
            guard !dataLines.isEmpty else { return }
            let data = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            if data == "[DONE]" { return }
            guard let raw = data.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let type = event["type"] as? String else {
                throw ChatGPTError.incomplete
            }
            if type.contains("refusal") { throw ChatGPTError.refused }
            switch type {
            case "response.output_text.delta":
                guard let delta = event["delta"] as? String else { throw ChatGPTError.incomplete }
                guard output.utf8.count + delta.utf8.count <= 16_777_216 else { throw ChatGPTError.incomplete }
                output += delta
            case "response.completed":
                guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                    throw ChatGPTError.incomplete
                }
                guard !containsRefusal(response) else { throw ChatGPTError.refused }
                completed = true
            case "response.incomplete":
                throw ChatGPTError.incomplete
            case "response.failed", "error":
                let streamError = ChatGPTService.nestedError(event)
                let mapped = ChatGPTService.classify(code: streamError?.code ?? "", type: streamError?.type ?? "",
                                                     fallback: .streamFailed, retryAfter: nil, partialOutput: !output.isEmpty)
                if let streamError, ["invalid_api_key", "token_expired", "unauthorized", "invalid_token"].contains(streamError.code) {
                    throw ChatGPTService.errorForCode(streamError.code)
                }
                throw mapped
            default:
                break
            }
        }

        private func containsRefusal(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                if (dictionary["type"] as? String)?.contains("refusal") == true { return true }
                return dictionary.values.contains(where: containsRefusal)
            }
            if let array = value as? [Any] { return array.contains(where: containsRefusal) }
            return false
        }
    }

    private struct StreamError {
        let code: String
        let type: String
    }

    private static func nestedError(_ event: [String: Any]) -> StreamError? {
        let response = event["response"] as? [String: Any]
        let error = (event["error"] as? [String: Any]) ?? (response?["error"] as? [String: Any])
        return error.map { StreamError(code: $0["code"] as? String ?? "", type: $0["type"] as? String ?? "") }
    }

    private static func errorForCode(_ code: String) -> ChatGPTError {
        switch code {
        case "invalid_api_key", "token_expired", "unauthorized", "invalid_token": return .http(401)
        case "subscription_sharing_usage_limit_exceeded": return .planUsageLimit
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable", "service_unavailable", "server_is_overloaded":
            return .temporarilyUnavailable(retryAfter: nil)
        case "rate_limit_exceeded", "rate_limit_error", "slow_down": return .rateLimited(retryAfter: nil)
        case "insufficient_quota", "billing_hard_limit_reached", "quota_exceeded", "credit_balance_exhausted",
             "organization_spend_limit_exceeded", "project_spend_limit_exceeded": return .quotaExceeded
        default: return .streamFailed
        }
    }

    // AsyncBytes.lines drops empty lines. SSE uses those lines as frame
    // boundaries, so decode the bytes ourselves and retain every delimiter.
    static func collect<Bytes: AsyncSequence>(bytes: Bytes) async throws -> String where Bytes.Element == UInt8 {
        var parser = EventStreamParser()
        var line = Data()
        var previousWasCR = false
        func output() throws -> String {
            guard !parser.output.isEmpty else { throw ChatGPTError.incomplete }
            return parser.output
        }
        func appendLine() throws {
            guard let text = String(data: line, encoding: .utf8) else { throw ChatGPTError.incomplete }
            try parser.append(text)
            line.removeAll(keepingCapacity: true)
        }
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte == 10 && previousWasCR { previousWasCR = false; continue }
                previousWasCR = byte == 13
                if byte == 10 || byte == 13 {
                    try appendLine()
                    // A terminal event is sufficient; do not wait for a
                    // keep-alive connection to close after completed inference.
                    if parser.completed { return try output() }
                } else {
                    guard line.count < 4_194_304 else { throw ChatGPTError.incomplete }
                    line.append(byte)
                }
            }
            try Task.checkCancellation()
            if !line.isEmpty { try appendLine() }
            try parser.finish()
            return try output()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChatGPTError {
            throw error
        } catch {
            try Task.checkCancellation()
            throw ChatGPTError.network
        }
    }

    static func parseEventStream(_ fixture: String) throws -> String {
        var parser = EventStreamParser()
        for line in fixture.components(separatedBy: .newlines) { try parser.append(line) }
        try parser.finish()
        guard !parser.output.isEmpty else { throw ChatGPTError.incomplete }
        return parser.output
    }

    private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

typealias ChatGPTError = ChatGPTService.ChatGPTError
