import Foundation

public struct Theme: Identifiable, Sendable {
    public let id: String
    public let keywords: [String]
    public let question: String

    public init(id: String, keywords: [String], question: String) {
        self.id = id; self.keywords = keywords; self.question = question
    }

    public static let coreValues: [Theme] = [
        Theme(id: "Findings", keywords: ["finding", "findings", "result", "results", "evidence", "observation", "outcome", "bevinding", "bevindingen", "resultaat", "resultaten", "onderbouwing", "waarneming", "uitkomst"], question: "What does the source report? / Wat meldt de bron?"),
        Theme(id: "Decisions", keywords: ["decision", "decisions", "decided", "approval", "approved", "proposal", "proposed", "commitment", "committed", "besluit", "besluiten", "besloten", "goedkeuring", "goedgekeurd", "voorstel", "voorgesteld", "toezegging", "toegezegd"], question: "What does the source say was proposed, committed to, or decided? / Wat staat er over voorstellen, toezeggingen of genomen besluiten?"),
        Theme(id: "Actions", keywords: ["action", "actions", "task", "tasks", "assigned", "owner", "responsible", "follow up", "follow-up", "actie", "acties", "taak", "taken", "toegewezen", "eigenaar", "verantwoordelijk", "uitvoerder", "opdracht"], question: "What action is explicitly assigned, and to whom? / Welke actie is expliciet toegewezen, en aan wie?"),
        Theme(id: "Costs", keywords: ["cost", "costs", "amount", "amounts", "budget", "funding", "estimate", "expenditure", "expense", "euro", "€", "kosten", "bedrag", "bedragen", "begroting", "financiering", "raming", "uitgaven"], question: "What costs or amounts does the source state? / Welke kosten of bedragen noemt de bron?"),
        Theme(id: "Deadlines", keywords: ["date", "dates", "due date", "deadline", "deadlines", "timeline", "milestone", "milestones", "no later than", "starting date", "end date", "datum", "data", "uiterlijk", "termijn", "termijnen", "planning", "mijlpaal", "mijlpalen", "vanaf"], question: "What dates or deadlines are stated? / Welke data of termijnen zijn genoemd?"),
        Theme(id: "Risks", keywords: ["risk", "risks", "uncertainty", "dependency", "constraint", "blocker", "issue", "risico", "risico's", "onzekerheid", "afhankelijkheid", "beperking", "knelpunt", "probleem"], question: "What risks or uncertainties are explicitly described? / Welke risico’s of onzekerheden worden expliciet beschreven?")
    ]

    public static let defaults: [Theme] = coreValues + [
        Theme(id: "Context", keywords: ["background", "scope", "purpose", "definition", "assumption", "context", "achtergrond", "reikwijdte", "doel", "definitie", "aanname", "context"], question: "What background is needed to understand the passage? / Welke achtergrond is nodig om de passage te begrijpen?")
    ]
}

public struct Finding: Identifiable, Sendable {
    public var id: String { "\(page)-\(theme)-\(excerpt)" }
    public let page: Int
    public let theme: String
    public let excerpt: String
    public let matchedKeywords: [String]
    public let question: String
}

public enum Analyzer {
    public static func analyze(pages: [String], themes: [Theme] = Theme.defaults) -> [Finding] {
        var findings: [Finding] = []
        for (index, page) in pages.enumerated() {
            // Preserve paragraphs where possible; normalize PDF line wrapping within them.
            let paragraphs = page.components(separatedBy: "\n\n")
                .map { $0.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
                .filter { !$0.isEmpty }
            for paragraph in paragraphs {
                for theme in themes {
                    let matches = theme.keywords.filter { keyword in
                        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: keyword) + "(?![\\p{L}\\p{N}])"
                        return paragraph.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
                    }
                    guard !matches.isEmpty else { continue }
                    let finding = Finding(page: index + 1, theme: theme.id, excerpt: paragraph, matchedKeywords: matches, question: theme.question)
                    if !findings.contains(where: { $0.id == finding.id }) { findings.append(finding) }
                }
            }
        }
        return findings
    }
}
