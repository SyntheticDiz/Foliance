import Foundation

struct InsightGroup: Identifiable, Sendable {
    let title: String
    let description: String
    var points: [Insight]
    var id: String { title }
}
enum InsightOrganization {
    private static func normalized(_ value: String) -> String { value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") }
    /// A reading aid, not a judgement about whether a proposal was adopted.
    /// Rank only what the point itself says; never infer facts from a source quote.
    static func priority(_ point: Insight) -> Int {
        if point.relevanceClass == "background" { return -1 }
        let text = " " + normalized(point.title + " " + point.summary) + " "
        let decisions = [" decision ", " decided ", " approved ", " confirmed ", " proposal ", " propose ", " proposes ", " proposed ", " commitment ", " committed ", " commits ", " intend ", " intends ", " besluit ", " besloten ", " vastgesteld ", " voorstel ", " voorgesteld ", " toegezegd ", " toezegging "]
        let actions = [" action ", " task ", " review ", " deliver ", " delivery ", " implement ", " assigned ", " owner ", " responsible ", " follow up ", " actie ", " taak ", " uitvoeren ", " eigenaar ", " verantwoordelijk "]
        let finances = [" cost ", " costs ", " eur ", " euro ", " euros ", " usd ", " dollar ", " dollars ", " gbp ", " pound ", " pounds ", " miljoen ", " miljard ", " budget ", " begroting ", " subsidie ", " funding ", " expense ", " financial ", " financiering "]
        let timing = [" deadline ", " timeline ", " milestone ", " due date ", " date ", " schedule ", " by ", " before ", " until ", " january ", " february ", " march ", " april ", " may ", " june ", " july ", " august ", " september ", " october ", " november ", " december ", " januari ", " februari ", " maart ", " mei ", " juni ", " juli ", " augustus ", " september ", " oktober ", " november ", " december ", " uiterlijk ", " termijn ", " planning ", " vanaf "]
        let consequences = [" impact ", " consequence ", " risk ", " dependency ", " constraint ", " blocker ", " risico ", " afhankelijkheid ", " beperking "]
        let raw = point.title + " " + point.summary
        let category = decisions.contains(where: text.contains) ? 5
            : actions.contains(where: text.contains) ? 4
            : (raw.contains("€") || raw.contains("$") || raw.contains("£") || finances.contains(where: text.contains)) ? 3
            : timing.contains(where: text.contains) ? 2
            : consequences.contains(where: text.contains) ? 1 : 0
        let specificity = (text.contains(where: \.isNumber) ? 2 : 0)
            + (point.otherSources?.isEmpty == false ? 1 : 0)
        return category * 10 + specificity + (point.relevanceClass == "main" ? 5 : 0)
    }

    /// Choose a bounded overview while leaving the complete, original points intact.
    /// One point per subject is considered first, then the strongest remaining points.
    static func featured(_ groups: [InsightGroup], maxTotal: Int = 12, maxPerGroup: Int = 3) -> [InsightGroup] {
        guard maxTotal > 0, maxPerGroup > 0 else { return [] }
        struct RankedPoint {
            let point: Insight
            let priority: Int
        }
        let ranked = groups.enumerated().map { groupIndex, group in
            (groupIndex, group.points.enumerated().compactMap { pointIndex, point -> (Int, RankedPoint)? in
                guard point.relevanceClass != "background" else { return nil }
                return (pointIndex, RankedPoint(point: point, priority: priority(point)))
            }.sorted {
                $0.1.priority == $1.1.priority ? $0.0 < $1.0 : $0.1.priority > $1.1.priority
            }.map(\.1))
        }
        var chosen: [Int: [Insight]] = [:]
        let groupOrder = ranked.sorted {
            let a = $0.1.first?.priority ?? -1, b = $1.1.first?.priority ?? -1
            return a == b ? $0.0 < $1.0 : a > b
        }
        for (index, points) in groupOrder where !points.isEmpty && chosen.count < maxTotal {
            chosen[index] = [points[0].point]
        }
        let remaining = ranked.flatMap { index, points in
            points.dropFirst().enumerated().map { (index, $0.offset, $0.element) }
        }.sorted {
            let a = $0.2.priority, b = $1.2.priority
            if a != b { return a > b }
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1 < $1.1
        }
        for (index, _, rankedPoint) in remaining {
            guard chosen.values.reduce(0, { $0 + $1.count }) < maxTotal else { break }
            if chosen[index, default: []].count < maxPerGroup { chosen[index, default: []].append(rankedPoint.point) }
        }
        return groups.enumerated().compactMap { index, group in
            guard let points = chosen[index] else { return nil }
            return InsightGroup(title: group.title, description: group.description, points: points)
        }
    }

    static func sortedForSelection(_ groups: [InsightGroup]) -> [InsightGroup] {
        struct RankedPoint {
            let offset: Int
            let point: Insight
            let priority: Int
        }
        var rankedGroups: [(index: Int, group: InsightGroup, priority: Int)] = []
        rankedGroups.reserveCapacity(groups.count)
        for (index, group) in groups.enumerated() {
            var rankedPoints: [RankedPoint] = []
            rankedPoints.reserveCapacity(group.points.count)
            for (offset, point) in group.points.enumerated() {
                rankedPoints.append(RankedPoint(offset: offset, point: point, priority: priority(point)))
            }
            rankedPoints.sort { lhs, rhs in
                if lhs.priority == rhs.priority { return lhs.offset < rhs.offset }
                return lhs.priority > rhs.priority
            }
            let orderedPoints = rankedPoints.map { $0.point }
            let groupPriority = rankedPoints.first?.priority ?? -1
            rankedGroups.append((index, InsightGroup(title: group.title, description: group.description, points: orderedPoints), groupPriority))
        }
        rankedGroups.sort { lhs, rhs in
            if lhs.priority == rhs.priority { return lhs.index < rhs.index }
            return lhs.priority > rhs.priority
        }
        return rankedGroups.map { $0.group }
    }
    private static func qualifiers(_ value: String) -> [String] {
        let words = normalized(value).split(separator: " ").map(String.init)
        let protected: Set<String> = [
            "niet", "geen", "tenzij", "mits", "alleen", "uitgezonderd", "mogelijk", "kan", "moet", "zal", "voorstel", "besloten", "maximaal", "minimaal", "voorlopig", "onder", "voorbehoud",
            "not", "never", "no", "unless", "only", "if", "except", "without", "after", "before", "until", "subject", "conditional", "contingent", "requires", "required", "may", "might", "must", "will", "would", "shall",
            "propose", "proposes", "proposal", "proposed", "plan", "plans", "planned", "intend", "intends", "intended", "commit", "commits", "committed", "commitment", "decided", "approved", "confirmed",
            "eur", "euro", "euros", "usd", "dollar", "dollars", "gbp", "pound", "pounds",
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
            "januari", "februari", "maart", "mei", "juni", "juli", "augustus", "oktober", "december"
        ]
        var result = words.filter { protected.contains($0) || $0.contains(where: \.isNumber) }
        let raw = value
        if raw.contains("€") { result.append("currency:eur") }
        if raw.contains("$") { result.append("currency:usd") }
        if raw.contains("£") { result.append("currency:gbp") }
        return result.sorted()
    }
    static func merged(_ points: [Insight]) -> [Insight] {
        var result: [Insight] = []
        // Conservative semantic matching: almost-identical wording, identical protected
        // facts and source qualifiers. Ambiguous near-duplicates remain separate.
        for point in points {
            // Passage-scoped outputs are intentionally never merged. Avoid scanning
            // every earlier point when recovery restores a large passage-based result.
            if point.passageID != nil {
                result.append(point)
                continue
            }
            let tokens = Set(normalized(point.summary).split(separator: " "))
            let match = result.firstIndex { other in
                // Passage-scoped outputs remain individually readable. Merging them
                // could erase the paragraph identity, part grouping or context trail.
                guard other.passageID == nil, point.passageID == nil,
                      other.relevanceClass == nil, point.relevanceClass == nil,
                      other.contextSources == nil, point.contextSources == nil,
                      other.relevanceReason == nil, point.relevanceReason == nil,
                      other.passagePartIndex == nil, point.passagePartIndex == nil,
                      other.passagePartCount == nil, point.passagePartCount == nil,
                      other.passageSources == nil, point.passageSources == nil,
                      normalized(other.relevance) == normalized(point.relevance), normalized(other.question) == normalized(point.question), other.programSource == point.programSource,
                      qualifiers(other.summary + " " + other.quote) == qualifiers(point.summary + " " + point.quote) else { return false }
                if normalized(other.summary) == normalized(point.summary) { return true }
                let otherTokens = Set(normalized(other.summary).split(separator: " "))
                return tokens.count >= 8 && Double(tokens.intersection(otherTokens).count) / Double(max(1, tokens.union(otherTokens).count)) >= 0.94
            }
            if let match {
                let old = result[match]
                let all = [Insight.Source(page: old.page, quote: old.quote)] + (old.otherSources ?? []) + [.init(page: point.page, quote: point.quote)] + (point.otherSources ?? [])
                var seen = Set<String>()
                let sources = all.filter { seen.insert("\($0.page):" + normalized($0.quote)).inserted }
                result[match] = Insight(title: old.title, summary: old.summary, relevance: old.relevance, question: old.question, quote: old.quote, page: old.page, programSource: old.programSource, otherSources: Array(sources.dropFirst()))
            } else { result.append(point) }
        }
        return result
    }
    static func groups(_ points: [Insight], readings: [PageReading]) -> [InsightGroup] {
        let frequencies = Dictionary(grouping: readings.flatMap(\.headings), by: { $0 }).mapValues(\.count)
        var chapter: [Int: String] = [:]; var current: String?
        for (i, reading) in readings.enumerated() {
            if let heading = reading.headings.first(where: { frequencies[$0, default: 0] <= 2 }) { current = heading }
            if let current { chapter[i + 1] = current }
        }
        let topics: [(String, [String], String)] = [
            ("Decisions", ["decision", "decided", "approved", "confirmed", "proposal", "proposed", "commitment", "besluit", "besloten", "vastgesteld", "voorstel", "voorgesteld", "toegezegd"], "Source statements about proposals, commitments, or confirmed decisions."),
            ("Actions", ["action", "task", "owner", "responsible", "follow up", "assigned", "deliver", "actie", "taak", "eigenaar", "verantwoordelijk", "opdracht", "uitvoeren"], "Explicit tasks, responsibilities, and follow-up actions."),
            ("Costs", ["cost", "budget", "funding", "expense", "financial", "€", "euro", "kosten", "begroting", "financiering", "uitgaven"], "Amounts, budgets, funding, and stated financial effects."),
            ("Deadlines", ["deadline", "due date", "timeline", "milestone", "by ", "before ", "starting", "uiterlijk", "termijn", "planning", "vanaf"], "Explicit dates, deadlines, and milestones."),
            ("Risks", ["risk", "dependency", "constraint", "uncertain", "issue", "blocker", "risico", "afhankelijkheid", "beperking", "onzeker", "knelpunt"], "Risks, constraints, dependencies, and unresolved issues."),
            ("Findings", ["finding", "result", "evidence", "observation", "shows", "indicates", "bevinding", "resultaat", "onderbouwing", "waarneming", "blijkt"], "Explicit findings, observations, and results."),
            ("Context", [], "Other source-supported context; the original passage remains available.")]
        var groups: [InsightGroup] = []
        var groupIndices: [String: Int] = [:]
        var passageGroup: [String: String] = [:]
        for point in points {
            let proposedTitle: String
            let defaultDescription: String
            let matched: Bool
            let hasChapter = chapter[point.page] != nil
            if let chapterTitle = chapter[point.page] {
                // The chapter always overrides topic matching and determines the
                // description. Keep passage title reuse below, but skip work that
                // cannot affect the result for chapter-assigned pages.
                proposedTitle = chapterTitle
                matched = false
                defaultDescription = "Aandachtspunten bij dit hoofdstuk; bronnen blijven per punt beschikbaar."
            } else {
                let content = normalized(point.title + " " + point.summary)
                // Calculate each topic's match count once. Recomputing both counts
                // in every max comparison, then rescanning the winning keywords for
                // `matched`, multiplied substring work for each point.
                let topicMatchCounts = topics.map { topic in
                    topic.1.reduce(into: 0) { count, keyword in
                        if content.contains(keyword) { count += 1 }
                    }
                }
                let topicIndex = topics.indices.max { lhs, rhs in
                    topicMatchCounts[lhs] < topicMatchCounts[rhs]
                }
                let topic = topicIndex.map { topics[$0] }
                matched = topicIndex.map { topicMatchCounts[$0] > 0 } ?? false
                proposedTitle = matched ? topic!.0 : "Context"
                defaultDescription = matched ? topic!.2 : "Other source-supported context; the original passage remains available."
            }
            let title: String
            if let passageID = point.passageID {
                title = passageGroup[passageID] ?? proposedTitle
                passageGroup[passageID] = title
            } else { title = proposedTitle }
            let description = hasChapter || (point.passageID != nil && title == proposedTitle && !matched)
                ? "Aandachtspunten bij dit hoofdstuk; bronnen blijven per punt beschikbaar."
                : defaultDescription
            if let index = groupIndices[title] { groups[index].points.append(point) }
            else {
                groupIndices[title] = groups.count
                groups.append(.init(title: title, description: description, points: [point]))
            }
        }
        return groups
    }
}
