import Foundation

/// A literal excerpt chosen by the user from the active PDF.
struct ChosenPassage: Codable, Sendable, Equatable, Identifiable {
    struct Source: Codable, Sendable, Equatable {
        var page: Int
        var quote: String

        init(page: Int, quote: String) {
            self.page = page
            self.quote = quote
        }
    }

    var id: UUID
    var title: String
    var note: String
    /// The exact string returned by PDF text selection; never normalized or rewritten.
    var text: String
    /// One-based physical PDF page numbers, in selection order, without duplicates.
    var pages: [Int]
    var sources: [Source]

    init(id: UUID = UUID(), title: String = "Gekozen passage", note: String = "", text: String,
         pages: [Int], sources: [Source] = []) {
        self.id = id
        self.title = title
        self.note = note
        self.text = text
        var seen = Set<Int>()
        self.pages = pages.filter { seen.insert($0).inserted }
        self.sources = sources
    }
}
