import SwiftUI

enum CommitteeFailurePresentation {
    typealias FailureCode = CommitteeAssessmentService.FailureCode
    struct Group: Identifiable {
        let code: FailureCode
        let entries: [CommitteeAssessmentService.Assessment]
        var id: String { code.rawValue }
    }
    static func groups(_ review: CommitteeAssessmentService.Review) -> [Group] {
        let order: [FailureCode] = [.notAttempted, .noDecision, .invalidRating, .missingReason, .missingQuote, .quoteMismatch, .requestFailure, .legacyUnknown]
        return order.compactMap { code in
            let entries = review.entries.filter { $0.rating == .unassessed && $0.effectiveFailureCode == code }
            return entries.isEmpty ? nil : Group(code: code, entries: entries)
        }
    }
    static func title(_ code: FailureCode) -> String {
        switch code {
        case .legacyUnknown: "Cause not recorded"
        case .notAttempted: "Not processed"
        case .noDecision: "No decision returned"
        case .invalidRating: "Unrecognized rating returned"
        case .missingReason: "Explanation missing"
        case .missingQuote: "Source quote missing"
        case .quoteMismatch: "Source quote not found"
        case .requestFailure: "Processing failed"
        }
    }
    static func actionTitle(review: CommitteeAssessmentService.Review?, model: String) -> String {
        guard let review else { return "Review this profile" }
        if review.model != model { return "Review with current model" }
        return review.complete ? "Refresh profile review" : "Resume profile review"
    }
    static func explanation(_ code: FailureCode) -> String {
        switch code {
        case .legacyUnknown: "An earlier version saved only a general error message, so the exact cause is no longer known."
        case .notAttempted: "No response has been processed for these passages yet."
        case .noDecision: "AI did not return a usable decision. The passage remains available and is not marked as unimportant."
        case .invalidRating: "The response did not contain a recognized rating."
        case .missingReason: "The response did not include an explanation for the rating."
        case .missingQuote: "The response did not include a literal quote from the assessed passage."
        case .quoteMismatch: "The supplied quote could not be matched safely to the original passage. Source verification was not relaxed."
        case .requestFailure: "Processing did not return a usable response. See the saved message for this passage."
        }
    }
}

struct CommitteeFailureDetails: View {
    let review: CommitteeAssessmentService.Review
    let showSource: (Int, String) -> Void
    @State private var visibleLimits: [String: Int] = [:]
    var body: some View {
        let groups = CommitteeFailurePresentation.groups(review)
        let entryReasons = Set(review.entries.filter { $0.rating == .unassessed }.map(\.reason))
        let otherIssues = Array(Set(review.issues.filter { !entryReasons.contains($0) })).sorted()
        DisclosureGroup("Why are assessments missing? (\(groups.reduce(0) { $0 + $1.entries.count }))") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(otherIssues, id: \.self) { Text($0).foregroundStyle(.orange).textSelection(.enabled) }
                ForEach(groups) { group in
                    DisclosureGroup(CommitteeFailurePresentation.title(group.code) + " (\(group.entries.count))") {
                        Text(CommitteeFailurePresentation.explanation(group.code)).foregroundStyle(.secondary)
                        ForEach(Array(group.entries.prefix(visibleLimits[group.id] ?? 8)), id: \.passageID) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                if group.code == .requestFailure { Text(entry.reason).textSelection(.enabled) }
                                ForEach(Array(entry.sources.enumerated()), id: \.offset) { _, source in
                                    Button("Show in PDF · p. \(source.page)") { showSource(source.page, source.quote) }.buttonStyle(FocusQuietActionStyle())
                                }
                            }.padding(.top, 3)
                        }
                        if group.entries.count > (visibleLimits[group.id] ?? 8) {
                            Button("Show more passages") { visibleLimits[group.id] = (visibleLimits[group.id] ?? 8) + 12 }
                        }
                    }
                }
                if groups.isEmpty && otherIssues.isEmpty {
                    Text("The previous review was saved as incomplete. No further failure reason was recorded.").foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
        }.font(.caption)
    }
}
