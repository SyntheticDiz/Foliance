import Foundation

/// Best-effort local record of bounded ChatGPT transport failures. Technical
/// identifiers are sanitized before persistence; response bodies and request content never enter this type.
enum ChatGPTLimitDiagnostics {
    static let maximumEvents = 20
    static let maximumFileBytes = 65_536

    enum Category: String, Codable {
        case signInRequired, usageLimit, unclassified429, rateLimited, temporarilyUnavailable
        case planUsageLimit, quotaExceeded, http, invalidRequest, refused
        case incomplete, streamFailed, network
    }

    enum ResponseShape: String, Codable {
        case jsonErrorObject, jsonErrorString, jsonDetailObject, jsonDetailString
        case jsonOther, nonJSON, empty, oversized
    }

    /// Finite fingerprint for a root-level JSON `detail` string. The text itself is never retained.
    enum DetailSignal: String, Codable {
        case rateLimitReached, rateLimitExceeded, requestRateLimitExceeded
        case tooManyRequests, tooManyConcurrentRequests
        case quotaOrUsage, userAction, other

        var isStrongRateLimit: Bool {
            switch self {
            case .rateLimitReached, .rateLimitExceeded, .requestRateLimitExceeded, .tooManyRequests, .tooManyConcurrentRequests:
                return true
            case .quotaOrUsage, .userAction, .other:
                return false
            }
        }
    }

    struct Event: Codable, Equatable {
        let category: Category
        let status: Int?
        let errorCode: String?
        let errorType: String?
        let responseShape: ResponseShape?
        let detailSignal: DetailSignal?
        let requestID: String?
        let retryAfterSeconds: Double?
        let timestamp: Date
        let appVersion: String?

        init(category: Category, status: Int?, errorCode: String?, errorType: String? = nil, responseShape: ResponseShape? = nil,
             detailSignal: DetailSignal? = nil,
             requestID: String?, retryAfterSeconds: Double?,
             timestamp: Date = Date(), appVersion: String? = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? PatchNotesView.version) {
            self.category = category
            self.status = status.flatMap { (100...599).contains($0) ? $0 : nil }
            self.errorCode = ChatGPTLimitDiagnostics.sanitizedTechnicalField(errorCode)
            self.errorType = ChatGPTLimitDiagnostics.sanitizedTechnicalField(errorType)
            self.responseShape = responseShape
            self.detailSignal = detailSignal
            self.requestID = Self.sanitizedRequestID(requestID)
            self.retryAfterSeconds = retryAfterSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            self.timestamp = timestamp
            self.appVersion = appVersion.flatMap(Self.sanitizedAppVersion)
        }

        private static func sanitizedRequestID(_ value: String?) -> String? {
            guard let value, value.hasPrefix("req_"), value.utf8.count <= 128,
                  value.utf8.allSatisfy({
                      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 || $0 == 47
                  }) else { return nil }
            return value
        }

        private static func sanitizedAppVersion(_ value: String) -> String? {
            guard !value.isEmpty, value.utf8.count <= 32,
                  value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 45 || $0 == 43 }) else { return nil }
            return value
        }
    }

    private static let queue = DispatchQueue(label: "com.foliance.chatgpt-limit-diagnostics", qos: .utility)

    static var defaultFileURL: URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = AnalysisMetrics.isTestHost
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Foliance/chatgpt-limit-diagnostics-tests/\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            : cachesDirectory.appendingPathComponent("Foliance", isDirectory: true)
        return root.appendingPathComponent("chatgpt-limit-diagnostics.json")
    }

    static func record(_ error: ChatGPTError, status: Int?, errorCode: String? = nil, errorType: String? = nil,
                       responseShape: ResponseShape? = nil, detailSignal: DetailSignal? = nil, requestID: String? = nil,
                       retryAfterSeconds: Double? = nil, to fileURL: URL? = nil) {
        let event = Event(category: category(for: error), status: status, errorCode: errorCode, errorType: errorType,
                          responseShape: responseShape, detailSignal: detailSignal,
                          requestID: requestID, retryAfterSeconds: retryAfterSeconds)
        let destination = fileURL ?? defaultFileURL
        queue.async { append(event, to: destination) }
    }

    private static func technicalField(_ key: String, in body: Data) -> String? {
        guard body.count <= maximumFileBytes,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let error = json["error"] as? [String: Any]
        let detail = json["detail"] as? [String: Any]
        guard let value = (error?[key] as? String) ?? (detail?[key] as? String) else { return nil }
        return sanitizedTechnicalField(value)
    }

    static func errorCode(in body: Data) -> String? { technicalField("code", in: body) }
    static func errorType(in body: Data) -> String? { technicalField("type", in: body) }

    static func detailSignal(in body: Data) -> DetailSignal? {
        guard body.count <= maximumFileBytes,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let detail = json["detail"] as? String else { return nil }
        return detailSignal(for: detail)
    }

    private static func detailSignal(for detail: String) -> DetailSignal {
        guard !detail.isEmpty, detail.utf8.count <= 512, detail.utf8.allSatisfy({ $0 < 128 }) else { return .other }
        let words = detail.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return .other }

        let usageTerms: Set<String> = ["usage", "quota", "billing", "bill", "payment", "plan", "subscription", "credit", "balance", "spend", "exhausted"]
        if !usageTerms.isDisjoint(with: words) { return .quotaOrUsage }
        let actionTerms: Set<String> = ["upgrade", "contact", "check", "review", "manage", "renew", "update", "change", "administrator", "admin", "permission", "enable", "required", "action", "verify", "subscribe", "purchase", "buy", "owner", "user"]
        if !actionTerms.isDisjoint(with: words) { return .userAction }

        let phrases: [([String], DetailSignal)] = [
            (["rate", "limit", "reached"], .rateLimitReached),
            (["rate", "limit", "exceeded"], .rateLimitExceeded),
            (["request", "rate", "limit", "exceeded"], .requestRateLimitExceeded),
            (["too", "many", "requests"], .tooManyRequests),
            (["too", "many", "concurrent", "requests"], .tooManyConcurrentRequests),
            (["you", "have", "exceeded", "the", "rate", "limit"], .rateLimitExceeded)
        ]
        for (phrase, signal) in phrases where words.starts(with: phrase) {
            let suffix = Array(words.dropFirst(phrase.count))
            if isAllowedRateLimitSuffix(suffix) { return signal }
        }
        return .other
    }

    private static func isAllowedRateLimitSuffix(_ words: [String]) -> Bool {
        let fixed: Set<[String]> = [
            [], ["please", "try", "again", "later"], ["try", "again", "later"],
            ["please", "retry", "later"], ["please", "try", "again"], ["try", "again"]
        ]
        if fixed.contains(words) { return true }
        let templates: [([String], String)] = [
            (["retry", "after"], "seconds"), (["retry", "after"], "second"),
            (["please", "retry", "after"], "seconds"), (["please", "retry", "after"], "second"),
            (["please", "try", "again", "in"], "seconds"), (["please", "try", "again", "in"], "second"),
            (["try", "again", "in"], "seconds"), (["try", "again", "in"], "second")
        ]
        for (prefix, unit) in templates where words.count == prefix.count + 2 && Array(words.prefix(prefix.count)) == prefix {
            let number = words[prefix.count]
            if number.count <= 4, number.allSatisfy(\.isNumber), words.last == unit { return true }
        }
        return false
    }

    static func responseShape(in body: Data) -> ResponseShape {
        guard !body.isEmpty else { return .empty }
        guard body.count <= maximumFileBytes else { return .oversized }
        guard let object = try? JSONSerialization.jsonObject(with: body) else { return .nonJSON }
        guard let json = object as? [String: Any] else { return .jsonOther }
        if json["error"] is [String: Any] { return .jsonErrorObject }
        if json["error"] is String { return .jsonErrorString }
        if json["detail"] is [String: Any] { return .jsonDetailObject }
        if json["detail"] is String { return .jsonDetailString }
        return .jsonOther
    }

    static func sanitizedTechnicalField(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 64 else { return nil }
        let lower = value.lowercased()
        guard !["sk_", "sk-", "rk_", "rk-", "sess_", "sess-", "ghp_", "gho_", "bearer_"].contains(where: lower.hasPrefix) else { return nil }
        let privacySensitiveTerms: Set<String> = ["prompt", "secret", "password", "bearer", "document", "authorization"]
        var segmentLength = 0
        var segments = 1
        var currentSegment = ""
        var containsSensitiveTerm = false
        for byte in value.utf8 {
            if byte == 95 || byte == 45 || byte == 46 {
                guard segmentLength > 0 else { return nil }
                containsSensitiveTerm = containsSensitiveTerm || privacySensitiveTerms.contains(currentSegment.lowercased())
                segments += 1
                segmentLength = 0
                currentSegment = ""
            } else if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) {
                if segmentLength == 0 && segments == 1 && (48...57).contains(byte) { return nil }
                segmentLength += 1
                currentSegment.append(Character(UnicodeScalar(byte)))
                guard segmentLength <= 32 else { return nil }
            } else {
                return nil
            }
        }
        guard segmentLength > 0, (2...8).contains(segments),
              !containsSensitiveTerm, !privacySensitiveTerms.contains(currentSegment.lowercased()) else { return nil }
        return value
    }

    static func requestID(in headers: [AnyHashable: Any]) -> String? {
        headers.first(where: { String(describing: $0.key).caseInsensitiveCompare("x-request-id") == .orderedSame })?.value as? String
    }

    static func category(for error: ChatGPTError) -> Category {
        switch error {
        case .signInRequired: return .signInRequired
        case .usageLimit: return .usageLimit
        case .unclassified429: return .unclassified429
        case .rateLimited: return .rateLimited
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .planUsageLimit: return .planUsageLimit
        case .quotaExceeded: return .quotaExceeded
        case .http: return .http
        case .invalidRequest: return .invalidRequest
        case .refused: return .refused
        case .incomplete: return .incomplete
        case .streamFailed: return .streamFailed
        case .network: return .network
        }
    }

    /// Deterministic synchronization seam for tests and bounded snapshot reads.
    static func drainForTesting() { queue.sync {} }

    static func readEvents(from fileURL: URL) -> [Event] {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumFileBytes,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]), data.count <= maximumFileBytes else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? decoder.decode([Event].self, from: data)) ?? []
        let sanitized = loaded.map {
            Event(category: $0.category, status: $0.status, errorCode: $0.errorCode, errorType: $0.errorType,
                  responseShape: $0.responseShape, detailSignal: $0.detailSignal, requestID: $0.requestID,
                  retryAfterSeconds: $0.retryAfterSeconds, timestamp: $0.timestamp, appVersion: $0.appVersion)
        }
        return Array(sanitized.suffix(maximumEvents))
    }

    private static func append(_ event: Event, to fileURL: URL) {
        do {
            var events = readEvents(from: fileURL)
            events.append(event)
            if events.count > maximumEvents { events.removeFirst(events.count - maximumEvents) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(events)
            guard data.count <= maximumFileBytes else { return }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { /* Diagnostics must never affect analysis or response handling. */ }
    }
}
