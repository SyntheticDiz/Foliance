import Foundation

struct ExportConfiguration: Codable, Sendable {
    /// Nil keeps historical and full-document exports unchanged.
    var committeePurpose: MeetingPurpose? = nil
    var summary = true
    var pagePoints = true
    var politics = true
    var questions = true
    var glossary = false
    private var includeTables: Bool? = true
    private var includeNotes: Bool? = false
    private var includeChosenPassages: Bool? = true
    var chosenPassages: Bool {
        get { includeChosenPassages ?? true }
        set { includeChosenPassages = newValue }
    }
    var tables: Bool {
        get { includeTables ?? true }
        set { includeTables = newValue }
    }
    var notes: Bool {
        get { includeNotes ?? false }
        set { includeNotes = newValue }
    }
    var sources = false
    var selectedPoints = false
    var selectedQuestions = false

    static func read(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "exportWizardChoices"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "exportWizardChoices") }
    }
    static func fileName(_ value: String) -> String {
        let clean = value.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = clean.lowercased().hasSuffix(".pdf") ? String(clean.dropLast(4)) : clean
        return (base.isEmpty ? "Foliance-export" : base) + ".pdf"
    }
}

enum ExportPreset: String, CaseIterable, Identifiable {
    case shortOverview
    case selectedWithSources
    case fullDossier

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shortOverview: "Brief overview"
        case .selectedWithSources: "My selection with sources"
        case .fullDossier: "Full report"
        }
    }
    var scopeDescription: String {
        switch self {
        case .shortOverview:
            "The document overview and passages you selected. Excludes findings, questions, tables, finding notes, and the source appendix."
        case .selectedWithSources:
            "Your selected findings and their available questions, with source passages, plus the passages you selected. Excludes the document overview, tables, reference comparison, abbreviations, and notes."
        case .fullDossier:
            "All available results within their stated page ranges, including findings, comparison, and questions. Your selected passages, tables, abbreviations, and notes cover the whole document; available source passages are included."
        }
    }

    func configuration() -> ExportConfiguration {
        var value = ExportConfiguration()
        switch self {
        case .shortOverview:
            value.summary = true
            value.pagePoints = false; value.politics = false; value.questions = false
            value.tables = false; value.glossary = false; value.sources = false
            value.selectedPoints = false; value.selectedQuestions = false; value.notes = false
        case .selectedWithSources:
            value.summary = false; value.pagePoints = true; value.politics = false; value.questions = true
            value.tables = false; value.glossary = false; value.sources = true
            value.selectedPoints = true; value.selectedQuestions = true; value.notes = false
        case .fullDossier:
            value.summary = true; value.pagePoints = true; value.politics = true; value.questions = true
            value.tables = true; value.glossary = true; value.sources = true
            value.selectedPoints = false; value.selectedQuestions = false; value.notes = true
        }
        return value
    }

    static func matching(_ configuration: ExportConfiguration) -> Self? {
        guard configuration.committeePurpose == nil else { return nil }
        return allCases.first { preset in
            let value = preset.configuration()
            return value.summary == configuration.summary
                && value.pagePoints == configuration.pagePoints
                && value.politics == configuration.politics
                && value.questions == configuration.questions
                && value.glossary == configuration.glossary
                && value.tables == configuration.tables
                && value.sources == configuration.sources
                && value.selectedPoints == configuration.selectedPoints
                && value.selectedQuestions == configuration.selectedQuestions
                && value.notes == configuration.notes
                && value.chosenPassages == configuration.chosenPassages
        }
    }
}

enum ExportScopeChoice: Hashable, Identifiable {
    case fullDocument
    case mySelection
    case committee(String)

    var id: String {
        switch self {
        case .fullDocument: "document"
        case .mySelection: "selection"
        case .committee(let purpose): "committee-\(purpose)"
        }
    }
}

/// Order in which optional sections are written to the PDF and listed in confirmation.
/// Keep this aligned with the section rendering order in BriefingPDF.
enum ExportSectionOrder {
    static let confirmation: [ExportSection] = [
        .summary, .chosenPassages, .pagePoints, .tables, .politics,
        .questions, .notes, .glossary, .sources
    ]
}

enum ExportSection: CaseIterable, Equatable {
    case summary
    case chosenPassages
    case pagePoints
    case tables
    case politics
    case questions
    case notes
    case glossary
    case sources
}

struct ExportFolderChoice: Equatable {
    let path: String
    let message: String?

    static func applying(_ result: Result<URL, Error>, currentPath: String) -> Self {
        switch result {
        case .success(let url): Self(path: url.path, message: nil)
        case .failure(let error) where ImportFailure.isCancellation(error): Self(path: currentPath, message: nil)
        case .failure(let error): Self(path: currentPath, message: error.localizedDescription)
        }
    }
}

struct ExportGlossaryItem: Sendable {
    let term: String
    let meaning: String
    let origin: String
    static func load(document: OpenPDF) throws -> [Self] {
        let personal = try PersonalGlossary.read()
        let key = LocalCache.key(document.pages)
        let online = try OnlineGlossaryStore.read(key)
        let terms = Set(personal.general.keys).union(personal.documents[key]?.keys.map { $0 } ?? [])
        return Glossary.extract(pages: document.pages, personalTerms: terms).map { entry in
            let own = personal.meaning(entry.abbreviation, document: key)
            if own == nil, entry.definitions.isEmpty, entry.reference == nil, let web = online[Glossary.key(entry.abbreviation)], web.certain, let source = web.source, source.kind == "Wikipedia-introductie" {
                return Self(term: entry.abbreviation, meaning: web.fullName + "\n" + web.explanation + (web.context.isEmpty ? "" : "\nIn this document: " + web.context), origin: "Online source · AI explanation · Wikipedia introduction · " + web.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))) + "\n" + source.url.absoluteString)
            }
            return Self(term: entry.abbreviation, meaning: own ?? entry.definitions.first?.text ?? entry.reference?.meaning ?? "Meaning not established", origin: own != nil ? "Custom definition" : entry.definitions.first.map { "From document, PDF page \($0.page)" } ?? entry.reference.map { "Glossary: \($0.url.absoluteString)" } ?? "Unknown")
        }
    }
}
