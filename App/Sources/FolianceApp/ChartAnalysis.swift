import AppKit
import FoundationModels
import PDFKit
import Vision

struct SelectedChart: Identifiable {
    let id = UUID()
    let page: Int
    let image: CGImage
}

enum ChartImageRenderer {
    static func render(page: PDFPage, region: CGRect, scale: CGFloat = 2) -> CGImage? {
        let pageBounds = page.bounds(for: .cropBox)
        let crop = region.standardized.intersection(pageBounds)
        guard !crop.isNull, crop.width >= 30, crop.height >= 30 else { return nil }
        let width = Int(ceil(crop.width * scale))
        let height = Int(ceil(crop.height * scale))
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}

struct ChartExplanation: Codable, Sendable {
    let kind: String
    let title: String
    let summary: String
    let observations: [String]
    let visibleValues: [String]
    let caution: String
}

enum ChartAnalysisService {
    static func unavailableReason() -> String? {
        guard #available(macOS 27.0, *) else { return "Apple Intelligence image analysis requires macOS 27 or later." }
        if let reason = AppleAIService.unavailability() { return reason }
        guard SystemLanguageModel.default.capabilities.contains(.vision) else {
            return "The installed Apple model cannot analyze images yet. Update macOS and Apple Intelligence."
        }
        return nil
    }

    static func analyze(_ image: CGImage) async throws -> ChartExplanation {
        if let reason = unavailableReason() { throw AppError(message: reason) }
        guard #available(macOS 27.0, *) else { throw AppError(message: "Image analysis requires macOS 27.") }
        try Task.checkCancellation()
        let recognized = try await Task.detached(priority: .userInitiated) { try recognizeText(in: image) }.value
        let instructions = """
        Analyze only the supplied crop as a pie chart or bar chart. Respond in English.
        If it is not a recognizable chart, set kind to 'no_chart'. Use only visible, readable labels,
        legends, and values. Do not infer exact values from bar height or pie slice size.
        Do not invent causes, trends outside the displayed categories, or missing percentages. State uncertainties.
        Write a concise explanation, at most four concrete observations, and at most six explicitly readable value-label pairs.
        """
        let prompt = Prompt {
            "Read this chart. Use the recognized text for checking: \(recognized.joined(separator: " | "))."
            Attachment(image).label("Selected chart from the PDF")
        }
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(to: prompt, generating: AppleChartDescription.self,
                                                 options: GenerationOptions(temperature: 0, maximumResponseTokens: 650))
        try Task.checkCancellation()
        let raw = response.content
        let described = ([raw.summary] + raw.observations).joined(separator: " ").lowercased()
        let kind: String
        if raw.kind.lowercased() == "no_chart" || raw.kind.lowercased() == "geen diagram" {
            if described.contains("bar chart") || described.contains("bar graph") || described.contains("bar-grafiek") { kind = "Bar chart" }
            else if described.contains("pie chart") || described.contains("pie graph") { kind = "Pie chart" }
            else { kind = "No chart" }
        } else if raw.kind.lowercased() == "bar_chart" || raw.kind.lowercased() == "staafdiagram" {
            kind = "Bar chart"
        } else if raw.kind.lowercased() == "pie_chart" || raw.kind.lowercased() == "cirkeldiagram" {
            kind = "Pie chart"
        } else { kind = "Chart" }
        guard kind != "No chart" else {
            throw AppError(message: "No clear pie chart or bar chart was recognized in this crop. Select the chart again, including its title and legend.")
        }
        let checked = ChartValueCheck.filter(raw.visibleValues, against: recognized)
        let observations = ChartValueCheck.filter(raw.observations, against: recognized)
        let summary = ChartValueCheck.isSupported(raw.summary, by: recognized)
            ? raw.summary : "Exact values cannot be read reliably from this crop. Check the chart in the PDF."
        let title = ChartValueCheck.isSupported(raw.title, by: recognized) ? raw.title : kind.capitalized
        let caution = ChartValueCheck.isSupported(raw.caution, by: recognized)
            ? raw.caution : "Check labels, values, and units against the source."
        return ChartExplanation(kind: kind, title: title, summary: summary,
                                observations: observations, visibleValues: checked,
                                caution: caution.isEmpty ? "Check labels, values, and units against the source." : caution)
    }

    private static func recognizeText(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

enum ChartValueCheck {
    private static let numberPattern = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*"#)

    static func isSupported(_ text: String, by recognized: [String]) -> Bool {
        let source = recognized.joined(separator: " ").replacingOccurrences(of: ",", with: ".")
        let candidate = text.replacingOccurrences(of: ",", with: ".")
        func numbers(in value: String) -> Set<String> {
            Set(numberPattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .compactMap { Range($0.range, in: value).map { String(value[$0]) } })
        }
        return numbers(in: candidate).isSubset(of: numbers(in: source))
    }

    static func filter(_ values: [String], against recognized: [String]) -> [String] {
        Array(values.filter { isSupported($0, by: recognized) }.prefix(6))
    }
}

@available(macOS 27.0, *)
@Generable
private struct AppleChartDescription {
    @Guide(description: "Choose bar_chart or pie_chart when visible. Use no_chart only when no recognizable chart is present.", .anyOf(["bar_chart", "pie_chart", "no_chart"]))
    var kind: String
    var title: String
    var summary: String
    @Guide(description: "At most four observations about visible proportions or categories.", .maximumCount(4))
    var observations: [String]
    @Guide(description: "At most six value-label pairs that can be read directly.", .maximumCount(6))
    var visibleValues: [String]
    var caution: String
}
