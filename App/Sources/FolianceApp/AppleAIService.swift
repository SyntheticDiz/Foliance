import Foundation
import FoundationModels

/// Uses only Apple's on-device model. Never routes to Private Cloud Compute.
enum AppleAIService {
    static let modelID = "foliance-apple-on-device"

    static func unavailability() -> String? {
        guard #available(macOS 26.0, *) else { return "Apple Intelligence requires macOS 26 or later. AI analysis is unavailable on this version of macOS." }
        switch SystemLanguageModel.default.availability {
        case .available:
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: AnalysisLanguage.code)) ? nil : "The installed Apple model does not support English yet. Update macOS and its models."
        case .unavailable(.deviceNotEligible): return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.modelNotReady): return "The Apple model is not ready. Let macOS download its models, then check again."
        case .unavailable: return "Apple Intelligence is currently unavailable."
        }
    }

    static func response(body: [String: Any]) async throws -> String {
        if let reason = unavailability() { throw AppError(message: reason) }
        guard #available(macOS 26.0, *) else { throw AppError(message: "Apple Intelligence requires macOS 26.") }
        try Task.checkCancellation()
        let instructions = (body["instructions"] as? String ?? "") + "\n" + AnalysisLanguage.instruction
        let input = body["input"] as? String ?? ""
        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        switch format?["name"] as? String {
        case "key_point": return try await generate(AppleKeyPoint.self, instructions: instructions, input: input, limit: 250)
        case "apple_question": return try await generate(AppleOneQuestion.self, instructions: instructions, input: input, limit: 250)
        case "apple_program_evidence": return try await generate(AppleProgramEvidence.self, instructions: instructions, input: input, limit: 600)
        case "apple_evidence": return try await generate(AppleEvidence.self, instructions: instructions, input: input, limit: 500)
        case "passage_neutral": return try await generate(ApplePassageEvidence.self, instructions: instructions, input: input, limit: 650)
        case "passage_program": return try await generate(ApplePassageProgramEvidence.self, instructions: instructions, input: input, limit: 650)
        case "apple_review": return try await generate(AppleReview.self, instructions: instructions, input: input, limit: 500)
        case "passage_questions": return try await generate(AppleQuestions.self, instructions: instructions, input: input, limit: 650)
        case "glossary_web": return try await generate(AppleGlossaryWebAnswer.self, instructions: instructions, input: input, limit: 450)
        case "paragraph_summary": return try await generate(AppleParagraphDigest.self, instructions: instructions, input: input, limit: 500)
        case "neutral_outline": return try await generate(AppleNeutralOutline.self, instructions: instructions, input: input, limit: 650)
        case "document_chat": return try await generate(AppleChatAnswer.self, instructions: instructions, input: input, limit: 650)
        case "document_overview": return try await generate(AppleOverview.self, instructions: instructions, input: input, limit: 1600)
        case "document_summary": return try await generate(AppleDigest.self, instructions: instructions, input: input, limit: 400)
        case "program_matches": return try await generate(AppleProgramMatches.self, instructions: instructions, input: input, limit: 700)
        case "committee_categorization": return try await generateCommittee(format: format, assessment: false, instructions: instructions, input: input, limit: 250)
        case "committee_assessment": return try await generateCommittee(format: format, assessment: true, instructions: instructions, input: input, limit: 400)
        default: return try await generate(AppleInsights.self, instructions: instructions, input: input, limit: 700)
        }
    }

    /// Committee enums depend on the selected purpose. Constrain both fields to
    /// those IDs in the actual local schema; unassigned is never a secondary tag.
    @available(macOS 26.0, *)
    private static func generateCommittee(format: [String: Any]?, assessment: Bool, instructions: String, input: String, limit: Int) async throws -> String {
        guard let schemaJSON = format?["schema"] as? [String: Any],
              let properties = schemaJSON["properties"] as? [String: Any],
              let category = properties["categoryID"] as? [String: Any],
              let primaryIDs = category["enum"] as? [String],
              let secondary = properties["secondaryCategoryIDs"] as? [String: Any],
              let items = secondary["items"] as? [String: Any],
              let secondaryIDs = items["enum"] as? [String], !secondaryIDs.isEmpty else { throw AppleFailure.invalid }
        let primary = DynamicGenerationSchema(name: "CommitteePrimaryTopic", anyOf: primaryIDs)
        let secondaryTopic = DynamicGenerationSchema(name: "CommitteeSecondaryTopic", anyOf: secondaryIDs)
        var fields: [DynamicGenerationSchema.Property] = []
        if assessment {
            fields += [
                .init(name: "rating", description: "Exactly one importance rating from the instructions.", schema: .init(name: "CommitteeRating", anyOf: CommitteeAssessmentService.Rating.allCases.map(\.rawValue))),
                .init(name: "reason", description: "A concise reason in English based only on the source.", schema: .init(type: String.self)),
                .init(name: "evidenceQuote", description: "An exact, contiguous quotation copied from CORE.", schema: .init(type: String.self))
            ]
        }
        fields += [
            .init(name: "categoryID", description: "One primary category, or unassigned when uncertain.", schema: primary),
            .init(name: "secondaryCategoryIDs", description: "Return an empty list unless a clearly distinct topic applies. Never repeat the primary category.", schema: .init(arrayOf: secondaryTopic, minimumElements: 0, maximumElements: 7))
        ]
        do {
            let schema = try GenerationSchema(root: .init(name: assessment ? "CommitteeAssessment" : "CommitteeCategorization", properties: fields), dependencies: [])
            let model = SystemLanguageModel.default
            if #available(macOS 26.4, *) {
                let total = try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: Prompt(input)) + model.tokenCount(for: schema)
                guard total + limit + 256 <= 4096 else { throw AppleFailure.context }
            } else {
                guard instructions.utf8.count + input.utf8.count + limit + 900 <= 4096 else { throw AppleFailure.context }
            }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: input, schema: schema, options: GenerationOptions(temperature: 0, maximumResponseTokens: limit))
            try Task.checkCancellation()
            return response.content.jsonString
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw AppleFailure.classify(error)
        }
    }

    @available(macOS 26.0, *)
    private static func generate<T: Generable & Encodable>(_ type: T.Type, instructions: String, input: String, limit: Int) async throws -> String {
        do {
            if #available(macOS 26.4, *) {
                let model = SystemLanguageModel.default
                let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
                let inputTokens = try await model.tokenCount(for: Prompt(input))
                let schemaTokens = try await model.tokenCount(for: T.generationSchema)
                guard instructionTokens + inputTokens + schemaTokens + limit + 256 <= 4096 else { throw AppleFailure.context }
            } else {
                // Deliberately conservative byte upper bound, including schema overhead.
                guard instructions.utf8.count + input.utf8.count + limit + 900 <= 4096 else { throw AppleFailure.context }
            }
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let response = try await session.respond(to: input, generating: type, options: GenerationOptions(temperature: 0, maximumResponseTokens: limit))
            try Task.checkCancellation()
            return String(decoding: try JSONEncoder().encode(response.content), as: UTF8.self)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw error }
            throw AppleFailure.classify(error)
        }
    }

}

@available(macOS 26.0, *)
@Generable
private struct AppleInsights: Codable {
    @Guide(description: "At most three findings; use an empty list when none are supported.", .maximumCount(3))
    var insights: [AppleInsight]
}
@available(macOS 26.0, *)
@Generable
private struct AppleInsight: Codable {
    var title: String
    var summary: String
    var relevance: String
    var question: String
    @Guide(description: "A short, exact, contiguous quotation from the supplied source page.")
    var quote: String
    var page: Int
}
@available(macOS 26.0, *)
@Generable
private struct AppleQuestions: Codable {
    @Guide(description: "At most five distinct questions. When completing a partial set, return only the requested missing number.", .maximumCount(5))
    var questions: [AppleQuestion]
}
@available(macOS 26.0, *)
@Generable
private struct AppleQuestion: Codable {
    var question: String
    @Guide(description: "A short, exact source quote that identifies what the question concerns.")
    var quote: String
}

@available(macOS 26.0, *)
@Generable
private struct AppleProgramMatches: Codable {
    @Guide(description: "At most two supported comparisons; use an empty list when there are none.", .maximumCount(2))
    var matches: [AppleProgramMatch]
}
@available(macOS 26.0, *)
@Generable
private struct AppleProgramMatch: Codable {
    var title: String
    var summary: String
    var relevance: String
    var question: String
    var quote: String
    var programQuote: String
    var programPage: Int
}

@available(macOS 26.0, *)
@Generable
private struct AppleDigest: Codable {
    @Guide(description: "At most two concise, neutral sentences containing only explicit source facts. Keep a proposal or request identified as such.")
    var overview: String
    @Guide(description: "At most five explicit source facts, with no added assumptions or uncertainty; keep the total under 100 words.", .maximumCount(5))
    var bullets: [String]
}

@available(macOS 26.0, *)
@Generable private struct AppleChatAnswer: Codable {
    @Guide(description: "Answer in English using only the sources. State what information is missing. Maximum 180 words.")
    var answer: String
    @Guide(description: "At most three exact source quotations.", .maximumCount(3))
    var citations: [AppleChatCitation]
}
@available(macOS 26.0, *)
@Generable private struct AppleChatCitation: Codable {
    var sourceID: String
    var quote: String
}

@available(macOS 26.0, *)
@Generable private struct AppleNeutralOutline: Codable {
    @Guide(description: "At most three neutral summary findings, each with a source quote.", .maximumCount(3))
    var points: [AppleNeutralPoint]
}
@available(macOS 26.0, *)
@Generable private struct AppleNeutralPoint: Codable {
    var title: String
    var summary: String
    @Guide(description: "A short, exact, contiguous source quotation.")
    var quote: String
}

@available(macOS 26.0, *)
@Generable struct AppleEvidence: Codable {
    @Guide(description: "At most two findings. Use an empty list when no concrete finding is supported.", .maximumCount(2))
    var points: [AppleEvidencePoint]
}
@available(macOS 26.0, *)
@Generable struct AppleEvidencePoint: Codable {
    var title: String
    @Guide(description: "One concise English sentence containing only explicit document facts.")
    var summary: String
    @Guide(description: "Exactly one D source ID from the input, for example D1.")
    var documentID: String
    @Guide(description: "Exactly one P source ID for a comparison, or an empty string.")
    var programID: String
    @Guide(description: "One concise sentence about a match or difference; empty for neutral analysis.")
    var relevance: String
}

@available(macOS 26.0, *)
@Generable private struct ApplePassageEvidence: Codable {
    @Guide(description: "At most three source-grounded findings; use an empty list when the passage has no main or background finding.", .maximumCount(3))
    var points: [ApplePassagePoint]
}
@available(macOS 26.0, *)
@Generable private struct ApplePassagePoint: Codable {
    var title: String
    var summary: String
    @Guide(description: "Exact document ID from a CORE source, never from CONTEXT.") var documentID: String
    @Guide(description: "All CORE source IDs supporting this finding; documentID is required.", .maximumCount(8)) var sourceIDs: [String]
    @Guide(description: "main, background of uncertain.") var relevanceClass: String
    @Guide(description: "A concise reason based on explicit source information.") var relevanceReason: String
    @Guide(description: "Only CONTEXT IDs actually used; empty when context was not needed.") var contextIDs: [String]
}
@available(macOS 26.0, *)
@Generable private struct ApplePassageProgramEvidence: Codable {
    @Guide(description: "At most three concrete reference-document comparisons; use an empty list when no supported match or difference exists.", .maximumCount(3))
    var points: [ApplePassageProgramPoint]
}
@available(macOS 26.0, *)
@Generable private struct ApplePassageProgramPoint: Codable {
    var title: String
    var summary: String
    @Guide(description: "Exact document ID from a CORE source.") var documentID: String
    @Guide(description: "All CORE source IDs supporting this finding; documentID is required.", .maximumCount(8)) var sourceIDs: [String]
    @Guide(description: "Exact reference-document ID.") var programID: String
    @Guide(description: "A supported match or difference, separate from the finding's importance.") var relevance: String
    @Guide(description: "main, background of uncertain.") var relevanceClass: String
    @Guide(description: "A concise reason based on explicit source information.") var relevanceReason: String
    @Guide(description: "Only CONTEXT IDs actually used; empty when context was not needed.") var contextIDs: [String]
}
@available(macOS 26.0, *)
@Generable struct AppleReview: Codable {
    @Guide(description: "At most two concise English sentences using facts from D sources only. Do not include reference-document text or source codes.")
    var summary: String
    @Guide(description: "Only an explicitly supported match or difference, at most two sentences. Keep wishes as wishes. Do not invent uncertainty. Empty for neutral analysis.")
    var relevance: String
    @Guide(description: "D source IDs supporting the revision. D1 and every supplied passage source are required. Use supplied IDs only.", .maximumCount(16))
    var sourceIDs: [String]
}

@available(macOS 26.0, *)
@Generable struct AppleProgramEvidence: Codable {
    @Guide(description: "At most two concrete reference-document comparisons. Empty when there is no supported connection.", .maximumCount(2))
    var points: [AppleProgramEvidencePoint]
}
@available(macOS 26.0, *)
@Generable struct AppleProgramEvidencePoint: Codable {
    var title: String
    @Guide(description: "One concise English sentence containing only explicit document facts.")
    var summary: String
    @Guide(description: "Required exact D source ID from DOCUMENT, for example D1. Never empty.")
    var documentID: String
    @Guide(description: "Required exact P source ID from the reference document, for example P1. Never empty.")
    var programID: String
    @Guide(description: "One sentence stating an explicit match or difference. Keep a wish as a wish. An evaluation is not evidence of termination or uncertain continuation.")
    var relevance: String
}

@available(macOS 26.0, *)
@Generable struct AppleOneQuestion: Codable {
    @Guide(description: "One open follow-up question in English. Do not assume new facts.")
    var question: String
    @Guide(description: "Required exact D source ID from the passage, for example D1.")
    var sourceID: String
}

@available(macOS 26.0, *)
@Generable struct AppleOverview: Codable {
    @Guide(description: "Summarize only explicit source facts in English. Use at most 25 sentences and be as concise as the source allows. Never fill in missing information. Maximum 500 words.")
    var overview: String
    @Guide(description: "At most five concrete main findings.", .maximumCount(5))
    var bullets: [String]
}

@available(macOS 26.0, *)
@Generable struct AppleKeyPoint: Codable {
    var relevant: Bool
    @Guide(description: "A concise, concrete English title. Add no facts. Maximum 30 words.")
    var title: String
    @Guide(description: "Importance from 1 to 3.", .range(1...3))
    var importance: Int
    @Guide(description: "Use only proposal, commitment, confirmed_decision, or unknown.", .anyOf(["proposal", "commitment", "confirmed_decision", "unknown"]))
    var status: String
}

@available(macOS 26.0, *)
@Generable struct AppleParagraphDigest: Codable {
    @Guide(description: "A concise English title for the complete paragraph.")
    var title: String
    @Guide(description: "Two to four sentences about the complete paragraph, at most 100 words. Use only source facts, including conditions and exceptions.")
    var summary: String
}

@available(macOS 26.0, *)
@Generable private struct AppleGlossaryWebAnswer: Codable {
    var fullName: String
    var explanation: String
    var context: String
    var certain: Bool
    var sourceID: Int
    var quote: String
}

@available(macOS 26.0, *)
@Generable private struct AppleCommitteeAssessment: Codable {
    @Guide(description: "Exactly one value.", .anyOf(["important", "relevant", "other", "uncertain", "unassessed"]))
    var rating: String
    @Guide(description: "A concise English reason based only on CORE source text.")
    var reason: String
    @Guide(description: "A non-empty, exact, contiguous quotation from CORE.")
    var evidenceQuote: String
    @Guide(description: "Exactly one valid category ID from the instructions, or unassigned.")
    var categoryID: String
    @Guide(description: "Only other valid category IDs from the instructions; no duplicates.", .maximumCount(7))
    var secondaryCategoryIDs: [String]
}

@available(macOS 26.0, *)
@Generable private struct AppleCommitteeCategorization: Codable {
    @Guide(description: "Exactly one valid category ID from the instructions, or unassigned.")
    var categoryID: String
    @Guide(description: "Only other valid category IDs from the instructions; no duplicates.", .maximumCount(7))
    var secondaryCategoryIDs: [String]
}
