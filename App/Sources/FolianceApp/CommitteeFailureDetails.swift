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
        case .legacyUnknown: "Oorzaak niet nader vastgelegd"
        case .notAttempted: "Nog niet verwerkt"
        case .noDecision: "AI kon geen oordeel geven"
        case .invalidRating: "Onbekende beoordeling teruggekregen"
        case .missingReason: "Uitleg ontbreekt"
        case .missingQuote: "Broncitaat ontbreekt"
        case .quoteMismatch: "Broncitaat niet teruggevonden"
        case .requestFailure: "Verwerking mislukt"
        }
    }
    static func actionTitle(review: CommitteeAssessmentService.Review?, model: String) -> String {
        guard let review else { return "Beoordeel voor dit profiel" }
        if review.model != model { return "Beoordeel met huidig model" }
        return review.complete ? "Vernieuw profielbeoordeling" : "Hervat profielbeoordeling"
    }
    static func explanation(_ code: FailureCode) -> String {
        switch code {
        case .legacyUnknown: "Een eerdere versie bewaarde alleen een algemene foutmelding. De precieze oorzaak is daardoor niet meer vast te stellen."
        case .notAttempted: "Voor deze passages is nog geen antwoord verwerkt."
        case .noDecision: "De AI heeft geen bruikbaar oordeel gegeven. De passage blijft beschikbaar en wordt niet als onbelangrijk aangemerkt."
        case .invalidRating: "Het antwoord bevatte geen herkenbare beoordeling."
        case .missingReason: "Het antwoord miste een uitleg bij de beoordeling."
        case .missingQuote: "Het antwoord miste een letterlijk citaat uit de beoordeelde passage."
        case .quoteMismatch: "Het aangeleverde citaat kon niet veilig in de oorspronkelijke passage worden teruggevonden. De broncontrole is niet versoepeld."
        case .requestFailure: "De verwerking leverde geen bruikbaar antwoord op. Bekijk de opgeslagen melding bij de betreffende passage."
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
        DisclosureGroup(UIStrings.text("Waarom ontbreken beoordelingen?") + " (\(groups.reduce(0) { $0 + $1.entries.count }))") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(otherIssues, id: \.self) { Text($0).foregroundStyle(.orange).textSelection(.enabled) }
                ForEach(groups) { group in
                    DisclosureGroup(UIStrings.text(CommitteeFailurePresentation.title(group.code)) + " (\(group.entries.count))") {
                        Text(UIStrings.text(CommitteeFailurePresentation.explanation(group.code))).foregroundStyle(.secondary)
                        ForEach(Array(group.entries.prefix(visibleLimits[group.id] ?? 8)), id: \.passageID) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                if group.code == .requestFailure { Text(entry.reason).textSelection(.enabled) }
                                ForEach(Array(entry.sources.enumerated()), id: \.offset) { _, source in
                                    Button(UIStrings.text("Toon in PDF · p. \(source.page)")) { showSource(source.page, source.quote) }.buttonStyle(FocusQuietActionStyle())
                                }
                            }.padding(.top, 3)
                        }
                        if group.entries.count > (visibleLimits[group.id] ?? 8) {
                            Button(UIStrings.text("Toon meer passages")) { visibleLimits[group.id] = (visibleLimits[group.id] ?? 8) + 12 }
                        }
                    }
                }
                if groups.isEmpty && otherIssues.isEmpty {
                    Text(UIStrings.text("De eerdere beoordeling is als onvolledig opgeslagen. Er is geen nadere foutreden bewaard.")).foregroundStyle(.secondary)
                }
            }.padding(.top, 6)
        }.font(.caption)
    }
}
