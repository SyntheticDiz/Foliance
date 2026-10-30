import Foundation
import FolianceCore

struct Insight: Codable, Identifiable, Sendable {
    var id: String {
        let legacy = [String(page), title, quote, programSource ?? ""]
        guard passageID != nil || passagePartIndex != nil else { return LocalCache.key(legacy) }
        return LocalCache.key(legacy + [passageID ?? "", passagePartIndex.map(String.init) ?? ""])
    }
    let title: String
    let summary: String
    let relevance: String
    let question: String
    let quote: String
    let page: Int
    var programSource: String? = nil
    struct Source: Codable, Sendable { let page: Int; let quote: String }
    var otherSources: [Source]? = nil
    // Optional paragraph provenance. Keeping these fields optional lets older
    // saved work decode without migration while new results retain their source.
    var passageID: String? = nil
    var relevanceClass: String? = nil
    var relevanceReason: String? = nil
    var contextSources: [Source]? = nil
    var passagePartIndex: Int? = nil
    var passagePartCount: Int? = nil
    var passageSources: [Source]? = nil
}

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { UIStrings.text(message) }
}

enum AIService {
    typealias Request = ([String: Any]) async throws -> String

    static func analyzeLocal(pages: [String], model: String, context: String, program: PartyProgram? = nil, targeted: Bool = false,
                             update: @escaping @Sendable ([Insight]) async -> Void = { _ in },
                             warning: @escaping @Sendable (Int) async -> Void = { _ in },
                             progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in },
                             request: Request? = nil) async throws -> [Insight] {
        guard context.utf8.count <= 1000 else { throw AppError(message: "Beperk aanvullende aandachtspunten voor lokale AI tot ongeveer 1.000 tekens.") }
        guard let program else { throw AppError(message: "Voeg eerst een referentiedocument toe via Instellingen.") }
        if request == nil { _ = try await AIRouting.resolve(model) }
        if AIConfiguration.isChatGPT(model) {
            return try await ChatGPTProgramAnalysis.analyze(pages: pages, model: model, context: context, program: program, request: request, update: update, warning: warning, progress: progress)
        }
        return try await AppleAnalysis.analyze(pages: pages, program: program, focus: context, update: update, progress: progress,
                                              request: request ?? response(for: model), useCache: request == nil && !AIConfiguration.isChatGPT(model))
    }

    static func localResponse(body: [String: Any], request: Request? = nil) async throws -> String {
        try Task.checkCancellation()
        let perform = { try await AnalysisMetrics.request { try await performLocalResponse(body: body, request: request) } }
        guard (body["model"] as? String)?.hasPrefix("chatgpt:") == true else {
            return try await perform()
        }
        return try await ChatGPTRequestObservation.perform { try await perform() }
    }

    private static func performLocalResponse(body: [String: Any], request: Request?) async throws -> String {
        try Task.checkCancellation()
        let model = body["model"] as? String ?? AppleAIService.modelID
        var routedBody = body
        if model.hasPrefix("chatgpt:") {
            guard AIConfiguration.isChatGPT(model) else { throw ChatGPTError.invalidRequest }
        } else { routedBody["model"] = AppleAIService.modelID }
        let result: String
        if let request { result = try await request(routedBody) }
        else if model.hasPrefix("chatgpt:") {
            guard AIConfiguration.isChatGPT(model) else { throw ChatGPTError.invalidRequest }
            result = try await ChatGPTService.response(body: body)
        }
        else {
            var localBody = body; localBody["model"] = AppleAIService.modelID
            result = try await AppleAIService.response(body: localBody)
        }
        try Task.checkCancellation()
        return result
    }

    static func response(for model: String) -> Request {
        { body in
            var captured = body; captured["model"] = model
            return try await localResponse(body: captured)
        }
    }

    static func contains(quote: String, page: Int, pages: [String]) -> Bool {
        func normalize(_ text: String) -> String {
            text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }
        guard page > 0, page <= pages.count, !normalize(quote).isEmpty else { return false }
        return normalize(pages[page - 1]).contains(normalize(quote))
    }
}
