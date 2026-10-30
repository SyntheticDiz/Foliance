import CoreGraphics
import Foundation
import Vision

/// Bounded local OCR variants for visibly printed numeric cells. A value is
/// returned only when two differently rendered crops independently produce
/// the same complete numeric token. This is machine agreement, not review.
enum OCRNumericVariants {
    private struct Variant {
        var name: String
        var image: CGImage
        var sourceRect: CGRect
        var scale: CGFloat
        var padding: Int
    }

    private static let numericPattern = #"^[−-]?(?:\d+|\d{1,3}(?:\.\d{3})+)(?:,\d+)?$"#
    private static let darkThreshold: UInt8 = 155

    static func consensus(in source: CGImage, cell: CGRect, expectedNegative: Bool,
                          sourcePixels: [UInt8]? = nil) throws -> String? {
        try Task.checkCancellation()
        let pixelCount = source.width * source.height
        let pixels: [UInt8]
        if let sourcePixels {
            guard sourcePixels.count == pixelCount else { return nil }
            pixels = sourcePixels
        } else {
            guard let converted = grayscalePixels(source) else { return nil }
            pixels = converted
        }
        guard let ink = try inkBounds(cell: cell, pixels: pixels, width: source.width, height: source.height) else { return nil }

        let glyphHeight = max(1, ink.height)
        let tightMargin = max(3, min(12, Int(glyphHeight * 0.25)))
        let wideMargin = max(8, min(24, Int(glyphHeight * 0.65)))
        let specifications: [(String, Variant?)] = [
            ("tight-gray-accurate", render(source, content: ink, padding: 36, scale: 7, threshold: nil)),
            ("tight-contrast-fast", render(source, content: ink, padding: 44, scale: 6, threshold: 170)),
            ("margin-contrast-accurate", render(source, content: cell.insetBy(dx: -CGFloat(wideMargin), dy: -CGFloat(tightMargin)), padding: 40, scale: 4, threshold: 135))
        ]
        let variants = specifications.compactMap { name, image -> Variant? in
            guard var image else { return nil }
            image.name = name
            return image
        }

        var votes: [String: Set<String>] = [:]
        for variant in variants {
            try Task.checkCancellation()
            let candidates = try recognizedNumbers(in: variant, inside: cell)
            for candidate in candidates where hasExpectedSign(candidate, negative: expectedNegative) {
                votes[candidate, default: []].insert(variant.name)
            }
            let winners = votes.filter { $0.value.count >= 2 }.map(\.key)
            if winners.count == 1 { return winners[0] }
            if winners.count > 1 { return nil }
        }
        return nil
    }

    private static func hasExpectedSign(_ candidate: String, negative: Bool) -> Bool {
        let normalized = candidate.replacingOccurrences(of: "−", with: "-")
        guard normalized.range(of: numericPattern, options: .regularExpression) != nil,
              TableReader.number(normalized) != nil else { return false }
        return !negative || normalized.hasPrefix("-")
    }

    private static func recognizedNumbers(in variant: Variant, inside cell: CGRect) throws -> Set<String> {
        var result = Set<String>()
        for fast in [false, true] {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.recognitionLanguages = ["nl-NL", "en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.002
            try VNImageRequestHandler(cgImage: variant.image, options: [:]).perform([request])
            for observation in request.results ?? [] {
                let imageX = observation.boundingBox.midX * CGFloat(variant.image.width)
                let sourceX = variant.sourceRect.minX + (imageX - CGFloat(variant.padding)) / variant.scale
                let imageY = (1 - observation.boundingBox.midY) * CGFloat(variant.image.height)
                let sourceY = variant.sourceRect.minY + (imageY - CGFloat(variant.padding)) / variant.scale
                guard sourceX >= cell.minX, sourceX <= cell.maxX,
                      sourceY >= cell.minY, sourceY <= cell.maxY else { continue }
                for candidate in observation.topCandidates(3) {
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "−", with: "-")
                    if text.range(of: numericPattern, options: .regularExpression) != nil,
                       TableReader.number(text) != nil {
                        result.insert(text)
                    }
                }
            }
        }
        return result
    }

    private static func inkBounds(cell: CGRect, pixels: [UInt8], width: Int, height: Int) throws -> CGRect? {
        let bounds = cell.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        let x0 = Int(bounds.minX), x1 = Int(bounds.maxX), y0 = Int(bounds.minY), y1 = Int(bounds.maxY)
        var minX = x1, maxX = x0, minY = y1, maxY = y0
        for y in y0..<y1 {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in x0..<x1 where pixels[y * width + x] < darkThreshold {
                minX = min(minX, x); maxX = max(maxX, x + 1)
                minY = min(minY, y); maxY = max(maxY, y + 1)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func render(_ source: CGImage, content: CGRect, padding: Int, scale: CGFloat, threshold: UInt8?) -> Variant? {
        let clipped = content.integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard !clipped.isNull, !clipped.isEmpty, let crop = source.cropping(to: clipped) else { return nil }
        let factor = min(scale, 4096 / CGFloat(max(crop.width, crop.height)))
        guard factor >= 1 else { return nil }
        let contentWidth = max(1, Int((CGFloat(crop.width) * factor).rounded()))
        let contentHeight = max(1, Int((CGFloat(crop.height) * factor).rounded()))
        let width = contentWidth + padding * 2
        let height = contentHeight + padding * 2
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: padding, y: padding, width: contentWidth, height: contentHeight))
        guard let image = context.makeImage() else { return nil }
        guard let threshold else { return Variant(name: "", image: image, sourceRect: clipped, scale: factor, padding: padding) }
        guard let pixels = grayscalePixels(image) else { return nil }
        let binary = pixels.map { $0 < threshold ? UInt8(0) : UInt8(255) }
        guard let provider = CGDataProvider(data: Data(binary) as CFData) else { return nil }
        guard let binaryImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return Variant(name: "", image: binaryImage, sourceRect: clipped, scale: factor, padding: padding)
    }

    /// Uses the same DeviceGray draw path as table-grid detection.
    static func grayscalePixels(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        let success = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return success ? pixels : nil
    }
}
