import Foundation
import ImageIO
import AppKit

struct SavedSelectionSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let selection: SelectedPDFText
    let summary: String
    let notice: String?
    let model: String

    init(id: UUID = UUID(), selection: SelectedPDFText, summary: String,
         notice: String? = nil, model: String) {
        self.id = id
        self.selection = selection
        self.summary = summary
        self.notice = notice
        self.model = model
    }

    static func validate(_ saved: SavedSelectionSummary, pageCount: Int) -> Bool {
        guard pageCount > 0,
              !saved.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !saved.selection.pages.isEmpty,
              Set(saved.selection.pages).count == saved.selection.pages.count,
              saved.selection.pages.allSatisfy({ 1...pageCount ~= $0 }),
              saved.selection.sources.allSatisfy({
                  saved.selection.pages.contains($0.page) &&
                  !$0.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              !saved.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !saved.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }
}

struct SavedChatThread: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let pages: [Int]
    let model: String
    let focus: String
    let wholeDocument: Bool
    let passage: String?
    let messages: [ChatMessage]

    static func validate(_ thread: SavedChatThread, pageCount: Int) -> Bool {
        guard !thread.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !thread.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pageCount > 0, !thread.pages.isEmpty,
              thread.pages == Array(Set(thread.pages)).sorted(),
              thread.pages.allSatisfy({ 1...pageCount ~= $0 }) else { return false }
        if thread.wholeDocument && thread.pages != Array(1...pageCount) { return false }
        if let passage = thread.passage,
           passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }

        for message in thread.messages {
            if message.isUser {
                guard message.citations.isEmpty, message.sources.isEmpty else { return false }
                continue
            }
            guard !message.citations.isEmpty else { return false }
            for source in message.sources {
                guard !source.id.isEmpty, !source.text.isEmpty, !source.name.isEmpty else { return false }
                if !source.isProgram && !thread.pages.contains(source.page) { return false }
            }
            for citation in message.citations {
                guard !citation.sourceID.isEmpty, !citation.quote.isEmpty,
                      let source = message.sources.first(where: { $0.id == citation.sourceID }),
                      AIService.contains(quote: citation.quote, page: 1, pages: [source.text]) else { return false }
            }
        }
        return true
    }

}

struct SavedChartAnalysis: Codable, Sendable, Identifiable {
    let id: UUID
    let page: Int
    let imagePNG: Data
    let explanation: ChartExplanation

    static func make(selected: SelectedChart, explanation: ChartExplanation) throws -> SavedChartAnalysis {
        let representation = NSBitmapImageRep(cgImage: selected.image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw AppError(message: "De geselecteerde diagramafbeelding kon niet als PNG worden bewaard.")
        }
        return SavedChartAnalysis(id: UUID(), page: selected.page, imagePNG: png, explanation: explanation)
    }

    static func validate(_ analysis: SavedChartAnalysis, pageCount: Int) -> Bool {
        guard pageCount > 0, (1...pageCount).contains(analysis.page),
              isPNG(analysis.imagePNG),
              !analysis.explanation.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.starts(with: signature),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return image.width > 0 && image.height > 0
    }
}
