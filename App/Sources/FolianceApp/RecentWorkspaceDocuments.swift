import Foundation
import Combine

/// Stores pointers to recently used workdocuments, not copies of their contents.
@MainActor
final class RecentWorkspaceDocuments: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable, Sendable {
        let path: String
        let displayName: String
        let lastUsed: Date
        let bookmarkData: Data?

        var id: String { path }
    }

    enum Availability: Equatable {
        case available
        case missing
        case inaccessible
    }

    enum RecentDocumentError: LocalizedError {
        case unsupportedFile
        case missing
        case inaccessible

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                "Choose an existing Foliance work document (.foliance)."
            case .missing:
                "This work document is no longer at this location. Move it back or open it from its new location."
            case .inaccessible:
                "Foliance cannot access this work document. Open it in the file picker to grant access again."
            }
        }
    }

    static let maximumEntries = 5
    static let shared = RecentWorkspaceDocuments()

    @Published private(set) var entries: [Entry] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "recentWorkspaceDocuments.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        _ = read()
    }

    /// Loads the current list. Missing or inaccessible files stay in the list so the user can find them.
    @discardableResult
    func read() -> [Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            entries = []
            return entries
        }
        var seen = Set<String>()
        entries = Array(decoded.enumerated()
            .filter { !$0.element.path.isEmpty && !$0.element.displayName.isEmpty }
            .sorted { left, right in
                left.element.lastUsed == right.element.lastUsed
                    ? left.offset < right.offset
                    : left.element.lastUsed > right.element.lastUsed
            }
            .map(\.element)
            .filter { seen.insert(Self.canonicalPath(URL(fileURLWithPath: $0.path))).inserted }
            .prefix(Self.maximumEntries))
        return entries
    }

    /// Call only after the document has been successfully opened or saved.
    func record(_ url: URL) throws {
        let fresh = try makeEntry(for: url)
        let canonicalPath = Self.canonicalPath(URL(fileURLWithPath: fresh.path))
        let updated = [fresh] + entries.filter { Self.canonicalPath(URL(fileURLWithPath: $0.path)) != canonicalPath }
        try replaceEntries(with: Array(updated.prefix(Self.maximumEntries)))
    }

    /// Replaces an unavailable/relocated pointer only after the new workdocument is validated.
    /// An existing entry at the destination is deduplicated and promoted to the front.
    func replace(_ oldEntry: Entry, with newURL: URL) throws {
        let fresh = try makeEntry(for: newURL)
        let canonicalPath = Self.canonicalPath(URL(fileURLWithPath: fresh.path))
        var updated = [fresh]
        updated.append(contentsOf: entries.filter {
            $0.id != oldEntry.id && Self.canonicalPath(URL(fileURLWithPath: $0.path)) != canonicalPath
        })
        try replaceEntries(with: Array(updated.prefix(Self.maximumEntries)))
    }

    func resolve(_ entry: Entry) throws -> URL {
        if let bookmarkData = entry.bookmarkData {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale),
               resolved.isFileURL {
                // Resolving a bookmark does not itself grant sandbox access.
                let scoped = resolved.startAccessingSecurityScopedResource()
                defer { if scoped { resolved.stopAccessingSecurityScopedResource() } }
                if FileManager.default.fileExists(atPath: resolved.path) { return resolved }
            }
        }
        let fallback = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            let parent = fallback.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: parent.path),
                  FileManager.default.isReadableFile(atPath: parent.path) else {
                throw RecentDocumentError.inaccessible
            }
            throw RecentDocumentError.missing
        }
        guard fallback.isFileURL else { throw RecentDocumentError.inaccessible }
        return fallback
    }

    func availability(of entry: Entry) -> Availability {
        do {
            _ = try resolve(entry)
            return .available
        } catch RecentDocumentError.missing {
            return .missing
        } catch {
            return .inaccessible
        }
    }

    func statusMessage(for entry: Entry) -> String? {
        switch availability(of: entry) {
        case .available: nil
        case .missing: RecentDocumentError.missing.localizedDescription
        case .inaccessible: RecentDocumentError.inaccessible.localizedDescription
        }
    }

    func remove(_ entry: Entry) throws {
        try replaceEntries(with: entries.filter { $0.id != entry.id })
    }

    private func makeEntry(for url: URL) throws -> Entry {
        guard url.isFileURL, url.pathExtension.lowercased() == "foliance",
              FileManager.default.fileExists(atPath: url.path) else {
            throw RecentDocumentError.unsupportedFile
        }
        let canonicalURL = Self.canonicalURL(url)
        let canonicalPath = Self.canonicalPath(canonicalURL)
        let previous = entries.first { Self.canonicalPath(URL(fileURLWithPath: $0.path)) == canonicalPath }
        let bookmark = (try? canonicalURL.bookmarkData(options: .withSecurityScope,
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil)) ?? previous?.bookmarkData
        return Entry(path: canonicalURL.path, displayName: canonicalURL.lastPathComponent,
                     lastUsed: Date(), bookmarkData: bookmark)
    }

    private func replaceEntries(with replacement: [Entry]) throws {
        let previous = entries
        entries = replacement
        do { try persist() }
        catch { entries = previous; throw error }
    }

    private func persist() throws {
        defaults.set(try JSONEncoder().encode(entries), forKey: storageKey)
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func canonicalPath(_ url: URL) -> String { canonicalURL(url).path }
}
