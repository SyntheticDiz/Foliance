import Foundation

/// Ephemeral extraction inputs kept only with the active in-memory PDF.
/// It contains no AI results and is never encoded in a workspace archive.
struct PageExtractionCache: Sendable {
    struct Page: Sendable {
        let reading: PageReading
        let rawTables: [DocumentTable]
        let hasTextLayer: Bool
        let appliedOverride: LayoutOverride

        func matches(_ override: LayoutOverride) -> Bool {
            appliedOverride.columns == override.columns && appliedOverride.region == override.region
        }
    }

    let sourceFingerprint: String
    let includesTables: Bool
    let pages: [Page]

    func isCompatible(sourceFingerprint: String, pageCount: Int, includesTables: Bool) -> Bool {
        self.sourceFingerprint == sourceFingerprint && self.pages.count == pageCount &&
            self.includesTables == includesTables
    }
}
