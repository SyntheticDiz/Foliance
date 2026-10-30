import Foundation

enum SavedSelection {
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Foliance/selecties") }
    static func read(documentKey: String, directory: URL = directory) -> Set<String> {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(documentKey + ".json")) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }
    static func write(_ values: Set<String>, documentKey: String, directory: URL = directory) throws {
        guard !documentKey.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: directory.appendingPathComponent(documentKey + ".json"), options: .atomic)
    }
}
