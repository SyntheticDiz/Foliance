import Foundation
import SwiftUI

enum SearchKind: String, CaseIterable, Hashable, Sendable {
    case summary = "Document overview"
    case point = "Finding"
    case table = "Table explanation"
    case glossary = "Abbreviation"
    case pdf = "PDF text"
    case chosenPassage = "Selected passage"
    case annotation = "Personal note"
}

enum SearchAction: Hashable, Sendable {
    case page(Int, quote: String?)
    case point(id: String, page: Int, quote: String)
    case chosenPassage(UUID)
    case table(id: String, page: Int?)
    case summary
    case glossary(String)
}

struct SearchRecord: Identifiable, Sendable {
    let id: String
    let kind: SearchKind
    let title: String
    let content: String
    let pageLabel: String?
    let action: SearchAction
    let searchable: String
    let foldedSearchable: String
    let revision: Int
    init(id: String, kind: SearchKind, title: String, content: String, pageLabel: String?, action: SearchAction) {
        self.id = id; self.kind = kind; self.title = title; self.content = content
        self.pageLabel = pageLabel; self.action = action
        let source = (kind == .pdf || kind == .summary) ? content : title + " " + content
        self.searchable = source.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        self.foldedSearchable = self.searchable.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var hasher = Hasher()
        hasher.combine(id); hasher.combine(kind); hasher.combine(title); hasher.combine(content)
        hasher.combine(pageLabel); hasher.combine(action)
        self.revision = hasher.finalize()
    }
}

struct SearchHit: Identifiable, Sendable {
    let record: SearchRecord
    let excerpt: String
    var id: String { record.id }
}

enum UnifiedSearch {
    struct Request: Hashable, Sendable {
        let query: String
        let recordsRevision: Int
        var includeWordForms = false
    }

    static func request(query: String, records: [SearchRecord], includeWordForms: Bool = false) -> Request {
        var hasher = Hasher()
        for record in records { hasher.combine(record.revision) }
        return Request(query: query, recordsRevision: hasher.finalize(), includeWordForms: includeWordForms)
    }

    static func isCurrent(_ request: Request, query: String, records: [SearchRecord], includeWordForms: Bool = false) -> Bool {
        request == self.request(query: query, records: records, includeWordForms: includeWordForms)
    }

    static func documentRecords(pages: [String], documentKey: String) -> [SearchRecord] {
        var records: [SearchRecord] = []
        let personal = (try? PersonalGlossary.read()) ?? PersonalGlossary()
        let online = (try? OnlineGlossaryStore.read(documentKey)) ?? [:]
        let documentTerms = personal.documents[documentKey].map { Array($0.keys) } ?? []
        let terms = Set(Array(personal.general.keys) + documentTerms)
        for entry in Glossary.extract(pages: pages, personalTerms: terms) {
            let key = Glossary.key(entry.abbreviation)
            let web = online[key]
            var meaning = personal.meaning(entry.abbreviation, document: documentKey)
            if meaning == nil { meaning = entry.definitions.first?.text }
            if meaning == nil { meaning = entry.reference?.meaning }
            if meaning == nil, web?.certain == true { meaning = web?.fullName }
            let definition = meaning ?? "Meaning not established"
            var explanation = entry.reference?.explanation ?? ""
            if explanation.isEmpty, web?.certain == true { explanation = web?.explanation ?? "" }
            let pageLabel: String? = entry.occurrences.first.map { occurrence in "PDF page \(occurrence.page)" }
            let record = SearchRecord(id: "glossary-" + key, kind: .glossary,
                                      title: entry.abbreviation, content: definition + " " + explanation,
                                      pageLabel: pageLabel, action: .glossary(entry.abbreviation))
            records.append(record)
        }
        for (index, page) in pages.enumerated() {
            let blocks = page.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for (blockIndex, block) in blocks.enumerated() {
                records.append(.init(id: "pdf-\(index)-\(blockIndex)", kind: .pdf,
                                     title: "PDF page \(index + 1)", content: block,
                                     pageLabel: "PDF page \(index + 1)", action: .page(index + 1, quote: block)))
            }
        }
        return records
    }

    static func analysisRecords(summary: DocumentSummary?, points: [Insight], tables: [DocumentTable],
                                chosenPassages: [ChosenPassage] = [], annotations: [String: PointAnnotation] = [:]) -> [SearchRecord] {
        var records: [SearchRecord] = []
        if let summary {
            records.append(.init(id: "summary-all", kind: .summary, title: "Document overview",
                                 content: summary.digest.overview + " " + summary.digest.bullets.joined(separator: " "),
                                 pageLabel: nil, action: .summary))
            for section in summary.pageSections {
                records.append(.init(id: "summary-\(section.page)", kind: .summary,
                                     title: "Overview · PDF page \(section.page)",
                                     content: section.digest.overview + " " + section.digest.bullets.joined(separator: " "),
                                     pageLabel: "PDF page \(section.page)", action: .page(section.page, quote: nil)))
            }
        }
        for point in points {
            let content = [point.title, point.summary, point.relevance, point.question].joined(separator: " ")
            records.append(.init(id: "point-" + point.id, kind: .point, title: point.title,
                                 content: content, pageLabel: "PDF page \(point.page)",
                                 action: .point(id: point.id, page: point.page, quote: point.quote)))
            if let note = annotations[SimpleWorkspace.selectionKey(point)]?.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                records.append(.init(id: "point-note-" + point.id, kind: .annotation,
                                     title: UIStrings.text("Personal note") + " · " + point.title, content: note,
                                     pageLabel: "PDF page \(point.page)",
                                     action: .point(id: point.id, page: point.page, quote: point.quote)))
            }
        }
        for passage in chosenPassages {
            records.append(.init(id: "chosen-" + passage.id.uuidString, kind: .chosenPassage,
                                 title: passage.title, content: passage.text + " " + passage.note,
                                 pageLabel: passage.pages.first.map { "PDF page \($0)" },
                                 action: .chosenPassage(passage.id)))
        }
        for table in tables {
            let content = ([table.title, table.overview] + table.bullets + table.notes + table.headers + table.rows.flatMap { $0 }).joined(separator: " ")
            let firstPage = table.pages.first
            let label = table.pages.count == 1 ? firstPage.map { "PDF page \($0)" } : firstPage.map { "From PDF page \($0)" }
            records.append(.init(id: "table-" + table.id, kind: .table, title: table.displayTitle,
                                 content: content, pageLabel: label,
                                 action: .table(id: table.id, page: firstPage)))
        }
        return records
    }

    static func matches(_ query: String, records: [SearchRecord]) -> [SearchHit] {
        (try? matchesCancellable(query, records: records, cancellationCheck: { false })) ?? []
    }

    static func matchesCancellable(_ query: String, records: [SearchRecord],
                                   cancellationCheck: @Sendable () -> Bool = { Task.isCancelled }) throws -> [SearchHit] {
        let term = normalized(query)
        guard !term.isEmpty else { return [] }
        let foldedTerm = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var hits: [SearchHit] = []
        hits.reserveCapacity(min(records.count, 128))
        for (index, record) in records.enumerated() {
            if index & 63 == 0, cancellationCheck() { throw CancellationError() }
            guard record.foldedSearchable.range(of: foldedTerm) != nil,
                  let originalRange = record.searchable.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            hits.append(SearchHit(record: record, excerpt: excerpt(in: record.searchable, around: originalRange)))
        }
        if cancellationCheck() { throw CancellationError() }
        return hits
    }

    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func excerpt(in text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -55, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 100, limitedBy: text.endIndex) ?? text.endIndex
        return (start == text.startIndex ? "" : "…") + text[start..<end] + (end == text.endIndex ? "" : "…")
    }

}

struct UnifiedSearchView: View {
    @Binding var query: String
    var focusRequest = 0
    let records: [SearchRecord]
    let indexing: Bool
    let open: (SearchRecord) -> Void
    @State private var limitsByKind: [SearchKind: Int] = [:]
    @State private var selectedKind: SearchKind?
    @State private var hits: [SearchHit] = []
    @State private var completedRequest: UnifiedSearch.Request?
    @State private var includeWordForms = false
    @State private var wordFormHits: [SearchHit] = []
    @State private var suggestions: [String] = []
    @State private var completedAssistanceRequest: UnifiedSearch.Request?
    @State private var assistanceIndex: SearchAssistanceIndex?
    @State private var assistanceRevision: Int?
    @State private var preparingAssistance = false
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    init(query: Binding<String>, focusRequest: Int = 0, records: [SearchRecord], indexing: Bool,
         includeWordForms: Bool = false, open: @escaping (SearchRecord) -> Void) {
        self._query = query
        self.focusRequest = focusRequest
        self.records = records
        self.indexing = indexing
        self.open = open
        self._includeWordForms = State(initialValue: includeWordForms)
    }

    private var searchRequest: UnifiedSearch.Request {
        UnifiedSearch.request(query: query, records: records, includeWordForms: includeWordForms)
    }
    var body: some View {
        let request = searchRequest
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(UIStrings.text("Search PDF, summary, findings, tables, abbreviations and your notes…"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel(UIStrings.text("Search the entire document and analysis"))
                    .tutorialTarget("search")
                if !query.isEmpty { Button(UIStrings.text("Clear search"), systemImage: "xmark.circle.fill") { query = "" }.labelStyle(.iconOnly) }
            }.padding(12).modifier(GlassSurface())
            Toggle(UIStrings.text("Include other word forms"), isOn: $includeWordForms)
                .toggleStyle(.checkbox)
                .font(.callout)
                .help(UIStrings.text("Show additional matches with another Dutch word form. Exact results remain first."))
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let found = completedRequest == request ? hits : []
                let extra = includeWordForms && completedAssistanceRequest == request ? wordFormHits : []
                let hints = completedAssistanceRequest == request ? suggestions : []
                if !found.isEmpty || !extra.isEmpty {
                    searchKindPicker(for: found + extra)
                }
                if !hints.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UIStrings.text("Did you mean:")).font(.callout).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack { suggestionButtons(hints) }
                            VStack(alignment: .leading) { suggestionButtons(hints) }
                        }
                    }
                }
                if found.isEmpty {
                    Text((isSearching ? "Searching…" : indexing ? "Searching PDF text and abbreviations…" : includeWordForms ? "No exact matches found." : "No results found."))
                        .foregroundStyle(.secondary)
                }
                else {
                    let count = selectedKind.map { kind in found.filter { $0.record.kind == kind }.count } ?? found.count
                    Text("\(count) results" + (selectedKind == nil ? "" : " " + UIStrings.text("of") + " \(found.count)") + (indexing ? UIStrings.text(" · ") + UIStrings.text("PDF text and abbreviations are still loading") : "")).font(.caption).foregroundStyle(.secondary)
                    resultGroups(found)
                }
                if !extra.isEmpty {
                    Divider()
                    Text(UIStrings.text("Other word forms") + " · \(extra.count)").font(.headline)
                    Text(UIStrings.text("Additional matches; the meaning may differ. The original source is preserved."))
                        .font(.caption).foregroundStyle(.secondary)
                    resultGroups(extra)
                }
                if preparingAssistance {
                    Text(UIStrings.text("Preparing search assistance…")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .onChange(of: query) { _, _ in limitsByKind = [:]; selectedKind = nil }
            .onChange(of: includeWordForms) { _, _ in limitsByKind = [:] }
            .onChange(of: focusRequest) { _, _ in searchFocused = true }
            .task(id: request) {
                if assistanceRevision != request.recordsRevision {
                    assistanceIndex = nil; assistanceRevision = nil
                }
                preparingAssistance = false
                guard !UnifiedSearch.normalized(request.query).isEmpty else {
                    hits = []; completedRequest = request; isSearching = false
                    suggestions = []; wordFormHits = []; completedAssistanceRequest = request
                    return
                }
                isSearching = true
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let recordSnapshot = records
                    let worker = Task.detached(priority: .userInitiated) {
                        try UnifiedSearch.matchesCancellable(request.query, records: recordSnapshot)
                    }
                    let result = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled, searchRequest == request else { return }
                    hits = result
                    completedRequest = request
                    isSearching = false
                    guard SearchAssistanceIndex.needsIndex(query: request.query, includeWordForms: request.includeWordForms) else {
                        suggestions = []; wordFormHits = []; completedAssistanceRequest = request
                        return
                    }
                    // Exact retrieval stays independent and visible while the optional local index is prepared.
                    preparingAssistance = true
                    let index: SearchAssistanceIndex
                    if let cached = assistanceIndex, assistanceRevision == request.recordsRevision {
                        index = cached
                    } else {
                        let indexWorker = Task.detached(priority: .utility) {
                            try SearchAssistanceIndex.build(records: recordSnapshot)
                        }
                        index = try await withTaskCancellationHandler {
                            try await indexWorker.value
                        } onCancel: { indexWorker.cancel() }
                        guard !Task.isCancelled, searchRequest == request else { return }
                        assistanceIndex = index
                        assistanceRevision = request.recordsRevision
                    }
                    let assistanceWorker = Task.detached(priority: .userInitiated) {
                        try index.search(query: request.query, includeWordForms: request.includeWordForms)
                    }
                    let response = try await withTaskCancellationHandler {
                        try await assistanceWorker.value
                    } onCancel: { assistanceWorker.cancel() }
                    guard !Task.isCancelled, searchRequest == request else { return }
                    let exactIDs = Set(result.map(\.id))
                    wordFormHits = response.wordFormHits.filter { !exactIDs.contains($0.id) }
                    suggestions = response.suggestions
                    completedAssistanceRequest = request
                    preparingAssistance = false
                } catch is CancellationError {
                    // A newer query or record set owns the visible results.
                } catch {
                    if !Task.isCancelled, searchRequest == request {
                        isSearching = false; preparingAssistance = false
                    }
                }
            }
    }

    @ViewBuilder private func suggestionButtons(_ hints: [String]) -> some View {
        ForEach(hints, id: \.self) { suggestion in
            Button(suggestion) { query = suggestion }
                .buttonStyle(FocusSecondaryButtonStyle())
                .help(UIStrings.text("Search with this spelling"))
        }
    }

    @ViewBuilder private func resultGroups(_ found: [SearchHit]) -> some View {
        let counts = Dictionary(grouping: found, by: { $0.record.kind }).mapValues(\.count)
        ForEach(SearchKind.allCases, id: \.self) { kind in
            let kindHits = found.filter { $0.record.kind == kind }
            let limit = limitsByKind[kind, default: 3]
            let inKind = Array(kindHits.prefix(limit))
            if (selectedKind == nil || selectedKind == kind), !kindHits.isEmpty {
                Text(kind.rawValue + " · \(counts[kind, default: 0])").font(.headline)
                ForEach(inKind) { hit in
                    Button { open(hit.record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text((hit.record.kind == .pdf || hit.record.kind == .summary) ? UIStrings.text(hit.record.title) : hit.record.title).font(.callout.bold())
                                Spacer()
                                if let page = hit.record.pageLabel { Text(UIStrings.text(page)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(hit.excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }.buttonStyle(.plain).tutorialTarget("searchResult")
                        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if kindHits.count > limit {
                    Button(UIStrings.text("More results") + " · " + kind.rawValue) {
                        limitsByKind[kind] = limit + 30
                    }.buttonStyle(FocusQuietActionStyle())
                }
            }
        }
    }

    private func searchKindPicker(for found: [SearchHit]) -> some View {
        let counts = Dictionary(grouping: found, by: { $0.record.kind }).mapValues(\.count)
        let selectedCount = selectedKind.map { counts[$0, default: 0] } ?? found.count
        return FocusMenuPicker(UIStrings.text("Result type"), selection: $selectedKind,
                               selectedTitle: (selectedKind.map { $0.rawValue } ?? UIStrings.text("All results")) + " · \(selectedCount)") {
                Text(UIStrings.text("All results") + " · \(found.count)").tag(Optional<SearchKind>.none)
                ForEach(SearchKind.allCases, id: \.self) { kind in
                    let count = counts[kind, default: 0]
                    if count > 0 || selectedKind == kind {
                        Text(kind.rawValue + " · \(count)").tag(Optional(kind))
                    }
                }
            }
            .controlSize(.small)
            .help(UIStrings.text("Choose a type to jump to its results"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.text("Result type"))
    }

}
