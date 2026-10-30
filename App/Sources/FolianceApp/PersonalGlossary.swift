import Foundation

struct PersonalGlossary: Codable {
    var general: [String: String] = [:]
    var documents: [String: [String: String]] = [:]
    static var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Foliance/afkortingen.json") }
    static func read(from url: URL = Self.url) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func write(to url: URL = Self.url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    func meaning(_ term: String, document: String) -> String? { documents[document]?[Glossary.key(term)] ?? general[Glossary.key(term)] }
    mutating func set(_ value: String, term: String, document: String, everywhere: Bool) {
        let key = Glossary.key(term); let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if everywhere { general[key] = value.isEmpty ? nil : value }
        else { documents[document, default: [:]][key] = value.isEmpty ? nil : value }
    }
}
