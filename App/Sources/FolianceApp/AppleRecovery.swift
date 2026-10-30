import Foundation
import FoundationModels

enum AppleFailure: Error, LocalizedError, Equatable {
    case context, refusal, temporary, unavailable, invalid, other(String)
    var errorDescription: String? {
        switch self {
        case .context: return "Apple Intelligence ran out of room for the source and response."
        case .refusal: return "Apple Intelligence declined this content. This part was not processed."
        case .temporary: return "Apple Intelligence is temporarily busy or did not respond in time."
        case .unavailable: return "Apple Intelligence or the required language or model files are unavailable."
        case .invalid: return "AI returned invalid output or unknown source references."
        case .other(let detail): return detail
        }
    }
    static func classify(_ error: Error) -> AppleFailure {
        if let error = error as? AppleFailure { return error }
        if error is DecodingError { return .invalid }
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .context
            case .guardrailViolation, .refusal: return .refusal
            case .rateLimited, .timeout: return .temporary
            case .unsupportedLanguageOrLocale: return .unavailable
            default: return .other(error.localizedDescription)
            }
        }
        if #available(macOS 27.0, *), error is SystemLanguageModel.Error { return .unavailable }
        if #available(macOS 26.0, *), let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .context
            case .guardrailViolation, .refusal: return .refusal
            case .rateLimited, .concurrentRequests: return .temporary
            case .assetsUnavailable, .unsupportedLanguageOrLocale: return .unavailable
            case .decodingFailure: return .invalid
            default: return .other(error.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
}

enum AppleRecovery {
    /// Retry only transient failures and invalid structured output. Refusals are never retried automatically.
    static func perform<T>(_ operation: () async throws -> T) async throws -> T {
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do { return try await operation() }
            catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                if error is ChatGPTError { throw error }
                let failure = AppleFailure.classify(error)
                guard attempt == 0 && (failure == .temporary || failure == .invalid) else { throw failure }
                AnalysisMetrics.current?.retry(AnalysisMetrics.phase)
                if failure == .temporary { try await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
        throw AppleFailure.invalid
    }
}

struct AppleAnalysisIncomplete: LocalizedError {
    let points: [Insight]
    let completed: Int
    let total: Int
    let issues: [String]
    var errorDescription: String? {
        "Analysis incomplete: processed \(completed) of \(total) steps.\n" + issues.joined(separator: "\n")
    }
}
