import Foundation
import CoreText
import CoreGraphics
import PDFKit
import FolianceCore

/// Lays out every line before drawing, so long passages continue without clipping.
enum BriefingPDF {
    private struct RenderInput: Sendable {
        let document: OpenPDF
        let insights: [Insight]
        let analyzed: Bool
        let date: Date
        let focus: String
        let neutral: Bool
        let summary: DocumentSummary?
        let summaryScope: String
        let includeSources: Bool
        let notice: String
        let configuration: ExportConfiguration?
        let title: String?
        let selectedIDs: Set<String>
        let selectedOrder: [String]
        let selectionStatuses: [String: SelectionMeetingStatus]
        let glossary: [ExportGlossaryItem]
        let tables: [DocumentTable]
        let readings: [PageReading]
        let annotations: [String: PointAnnotation]
        let chosenPassages: [ChosenPassage]
        let committeeLabels: [String: String]
    }

    static func render(document: OpenPDF, insights: [Insight], analyzed: Bool, date: Date = Date(), focus: String = "", neutral: Bool = false, summary: DocumentSummary? = nil, summaryScope: String = "Hele document", includeSources: Bool = false, notice: String = "", configuration: ExportConfiguration? = nil, title: String? = nil, selectedIDs: Set<String> = [], selectedOrder: [String] = [], selectionStatuses: [String: SelectionMeetingStatus] = [:], glossary: [ExportGlossaryItem] = [], tables: [DocumentTable] = [], readings: [PageReading] = [], annotations: [String: PointAnnotation] = [:], chosenPassages: [ChosenPassage] = [], committeeLabels: [String: String] = [:]) async throws -> Data {
        let input = RenderInput(document: document, insights: insights, analyzed: analyzed, date: date, focus: focus,
                                neutral: neutral, summary: summary, summaryScope: summaryScope, includeSources: includeSources,
                                notice: notice, configuration: configuration, title: title, selectedIDs: selectedIDs, selectedOrder: selectedOrder, selectionStatuses: selectionStatuses,
                                glossary: glossary, tables: tables, readings: readings, annotations: annotations, chosenPassages: chosenPassages,
                                committeeLabels: committeeLabels)
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try data(document: input.document, insights: input.insights, analyzed: input.analyzed, date: input.date,
                            focus: input.focus, neutral: input.neutral, summary: input.summary, summaryScope: input.summaryScope,
                            includeSources: input.includeSources, notice: input.notice, configuration: input.configuration,
                            title: input.title, selectedIDs: input.selectedIDs, selectedOrder: input.selectedOrder, selectionStatuses: input.selectionStatuses, glossary: input.glossary,
                            tables: input.tables, readings: input.readings, annotations: input.annotations, chosenPassages: input.chosenPassages,
                            committeeLabels: input.committeeLabels)
        }
        let data = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return data
    }

    private static let black = CGColor(gray: 0, alpha: 1)
    private static let darkGray = CGColor(gray: 0.36, alpha: 1)
    private static let white = CGColor(gray: 1, alpha: 1)

    private struct Point {
        let title: String
        let summary: String
        let relevance: String?
        let question: String
        let quote: String
        let sourcePage: Int
        var extraSources: [Insight.Source] = []
        var relevanceClass: String? = nil
        var relevanceReason: String? = nil
        var contextSources: [Insight.Source] = []
        var passagePartIndex: Int? = nil
        var passagePartCount: Int? = nil
        var passageSources: [Insight.Source] = []
        var passageID: String? = nil
        var committeeLabel: String? = nil
    }
    private struct Line {
        let text: CTLine
        let x: CGFloat
        let y: CGFloat
        let color: CGColor
    }
    private struct Link { let page: Int; let rect: CGRect; let point: Int }

    static func data(document: OpenPDF, insights: [Insight], analyzed: Bool, date: Date = Date(), focus: String = "", neutral: Bool = false, summary: DocumentSummary? = nil, summaryScope: String = "Hele document", includeSources: Bool = false, notice: String = "", configuration: ExportConfiguration? = nil, title: String? = nil, selectedIDs: Set<String> = [], selectedOrder: [String] = [], selectionStatuses: [String: SelectionMeetingStatus] = [:], glossary: [ExportGlossaryItem] = [], tables: [DocumentTable] = [], readings: [PageReading] = [], annotations: [String: PointAnnotation] = [:], chosenPassages: [ChosenPassage] = [], committeeLabels: [String: String] = [:]) throws -> Data {
        try Task.checkCancellation()
        let includedInsights = insights.filter { insight in
            guard let c = configuration else { return true }
            let selected = selectedIDs.contains(selectionKey(insight))
            return (c.notes && (!c.selectedPoints || selected) && annotations[selectionKey(insight)] != nil) || (c.pagePoints && (!c.selectedPoints || selected)) || (c.politics && !insight.relevance.isEmpty) || (c.questions && (!c.selectedQuestions || selected) && !insight.question.isEmpty)
        }
        let points: [Point] = (analyzed || configuration != nil) ? includedInsights.map {
            Point(title: $0.title, summary: $0.summary, relevance: $0.relevance, question: $0.question, quote: $0.quote, sourcePage: $0.page, extraSources: $0.otherSources ?? [],
                  relevanceClass: $0.relevanceClass, relevanceReason: $0.relevanceReason, contextSources: $0.contextSources ?? [],
                  passagePartIndex: $0.passagePartIndex, passagePartCount: $0.passagePartCount, passageSources: $0.passageSources ?? [], passageID: $0.passageID,
                  committeeLabel: committeeLabels[SimpleWorkspace.selectionKey($0)])
        } : document.findings.sorted {
            return rank($0.theme) < rank($1.theme)
        }.map {
            Point(title: $0.theme, summary: "Keywords: " + $0.matchedKeywords.joined(separator: ", "), relevance: nil, question: $0.question, quote: $0.excerpt, sourcePage: $0.page)
        }
        let layout = Layout()
        func paragraphMetadata(_ point: Point) {
            let label: String?
            switch point.relevanceClass {
            case "main": label = "Main finding"
            case "background": label = "Background"
            case "uncertain": label = "Uncertain"
            default: label = nil
            }
            if let label {
                let part = if let index = point.passagePartIndex, let count = point.passagePartCount, count > 1 { " · Paragraph part \(index) of \(count)" } else { "" }
                layout.paragraph("Paragraph assessment: \(label)\(part)", size: 9, color: darkGray)
            }
            if let reason = point.relevanceReason, !reason.isEmpty {
                layout.paragraph("Source-grounded reason: " + reason, size: 10)
            }
            if let label = point.committeeLabel, !label.isEmpty {
                layout.paragraph(UIStrings.text(label), size: 9, color: darkGray)
            }
        }
        layout.heading(title ?? (!chosenPassages.isEmpty ? "Document summary" : neutral ? "Document summary" : analyzed ? "Document brief" : "Keyword selection"), size: 28)
        layout.paragraph("Source document: " + document.name, size: 12)
        layout.paragraph("Foliance | Export date: " + date.formatted(date: .abbreviated, time: .shortened), size: 9, color: darkGray)
        if !focus.isEmpty { layout.paragraph(focus, size: 9, color: darkGray) }
        if !notice.isEmpty { layout.heading("Processing incomplete", size: 12); layout.paragraph(UIStrings.text(notice), size: 10) }
        var links: [Link] = []
        var targets: [(page: Int, y: CGFloat)] = []
        var targetTitles: [String] = []
        func chosenPassageSection(recordOutline: Bool) throws {
            guard configuration?.chosenPassages ?? true, !chosenPassages.isEmpty else { return }
            layout.ensure(100)
            if recordOutline {
                targets.append((layout.pages.count - 1, layout.y))
                targetTitles.append("Selected passages")
            }
            layout.heading("Selected passages", size: 18)
            for passage in chosenPassages {
                try Task.checkCancellation()
                layout.ensure(90)
                let passageTitle = passage.title.hasPrefix("Profielbeoordeling: ") ? UIStrings.text(passage.title) : passage.title
                layout.heading(passageTitle.isEmpty ? "Selected passage" : passageTitle, size: 13)
                layout.paragraph("Selected · physical PDF pages " + passage.pages.map(String.init).joined(separator: ", "), size: 9, color: darkGray)
                layout.paragraph(passage.text)
                if !passage.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    layout.heading("Your note", size: 10)
                    layout.paragraph(passage.note, size: 10)
                }
            }
        }
        if let c = configuration {
            func source(_ point: Point, index: Int) {
                layout.ensure(30)
                let top = layout.y, page = layout.pages.count - 1
                layout.paragraph("Source: physical PDF page " + ([point.sourcePage] + point.extraSources.map(\.page)).map(String.init).joined(separator: ", ") + (includeSources ? " · source quote \(index + 1) in appendix" : ""), size: 9, color: darkGray)
                if !point.contextSources.isEmpty {
                    layout.paragraph("Context sources: physical PDF page " + point.contextSources.map(\.page).map(String.init).joined(separator: ", "), size: 9, color: darkGray)
                }
                if !point.passageSources.isEmpty {
                    layout.paragraph("Full paragraph: physical PDF page " + point.passageSources.map(\.page).map(String.init).joined(separator: ", "), size: 9, color: darkGray)
                }
                if includeSources { links.append(Link(page: page, rect: CGRect(x: 48, y: top - 15, width: 499, height: 18), point: index)) }
            }
            func heading(_ text: String, keepWith height: CGFloat = 80) {
                layout.ensure(min(695, layout.height(text, size: 18) + height))
                targets.append((layout.pages.count - 1, layout.y)); targetTitles.append(text)
                layout.heading(text, size: 18)
            }
            if c.summary, let summary {
                heading("Document summary")
                layout.paragraph("Scope: " + UIStrings.text(summaryScope), size: 9, color: darkGray)
                layout.paragraph(summary.digest.overview)
                if let warning = summary.incompleteNotice, !notice.contains(warning) { layout.paragraph(UIStrings.text(warning), size: 10) }
            }
            try chosenPassageSection(recordOutline: true)
            if c.pagePoints {
                if c.selectedPoints {
                    let ordered = includedInsights.indices.sorted { a, b in
                        let ka = selectionKey(includedInsights[a]), kb = selectionKey(includedInsights[b])
                        let ia = selectedOrder.firstIndex(of: ka), ib = selectedOrder.firstIndex(of: kb)
                        if let ia, let ib { return ia < ib }
                        if ia != nil { return true }
                        if ib != nil { return false }
                        return a < b
                    }.filter { selectedIDs.contains(selectionKey(includedInsights[$0])) }
                    heading("My selection", keepWith: ordered.first.map { layout.height(points[$0].summary, size: 11) + layout.height(points[$0].title, size: 13) + 95 } ?? 80)
                    for index in ordered {
                        try Task.checkCancellation()
                        let point = points[index]
                        layout.ensure(min(695, layout.height(point.summary, size: 11) + layout.height(point.title, size: 13) + 95))
                        layout.heading(point.title, size: 13)
                        layout.paragraph("• " + point.summary)
                        paragraphMetadata(point)
                        let key = SimpleWorkspace.selectionKey(includedInsights[index])
                        layout.paragraph("Review status: " + selectionStatus(selectionStatuses[key] ?? .discuss), size: 9, color: darkGray)
                        source(point, index: index)
                    }
                } else {
                let first = points.indices.sorted { points[$0].sourcePage < points[$1].sourcePage }.first { !c.selectedPoints || selectedIDs.contains(selectionKey(includedInsights[$0])) }
                heading("Grouped findings", keepWith: first.map { layout.height(points[$0].summary, size: 11) + layout.height(points[$0].title, size: 13) + 95 } ?? 80)
                var previousPage: Int?
                let grouped = InsightOrganization.groups(includedInsights, readings: readings)
                for group in grouped {
                    try Task.checkCancellation()
                    let indices = group.points.compactMap { item in includedInsights.firstIndex(where: { $0.id == item.id }) }
                        .filter { !c.selectedPoints || selectedIDs.contains(selectionKey(includedInsights[$0])) }
                    if indices.isEmpty { continue }
                    layout.ensure(170); layout.heading(group.title, size: 16)
                    layout.paragraph(UIStrings.text(group.description), size: 9, color: darkGray)
                    previousPage = nil
                for index in indices.sorted(by: { points[$0].sourcePage < points[$1].sourcePage }) {
                    try Task.checkCancellation()
                    if c.selectedPoints && !selectedIDs.contains(selectionKey(includedInsights[index])) { continue }
                    let point = points[index]
                    layout.ensure(min(695, layout.height(point.summary, size: 11) + layout.height(point.title, size: 13) + 95))
                    if previousPage != point.sourcePage { layout.heading("PDF page \(point.sourcePage)", size: 15); previousPage = point.sourcePage }
                    layout.heading(point.title, size: 13)
                    layout.paragraph("• " + point.summary)
                    paragraphMetadata(point)
                    source(point, index: index)
                }
                }
                }
            }
            if c.tables && !tables.isEmpty {
                heading("Table explanations", keepWith: 160)
                for table in tables {
                    try Task.checkCancellation()
                    layout.ensure(140)
                    layout.heading(table.title, size: 14)
                    layout.paragraph("Source page " + table.pages.map(String.init).joined(separator: ", "), size: 9, color: darkGray)
                    layout.paragraph(table.overview)
                    if table.recognizedWithOCR == true {
                        layout.paragraph(table.isOCRConfirmed ? "OCR · checked against the source by the user. Figures may still contain errors." : "OCR — needs review. Recognized cells; figures and comparisons are not confirmed.", size: 10)
                        if table.isOCRConfirmed, let digest = table.ocrReview?.summary {
                            layout.paragraph(digest.overview, size: 10)
                            for fact in digest.bullets { try Task.checkCancellation(); layout.paragraph("• " + fact, size: 10) }
                        }
                        for row in table.rows {
                            try Task.checkCancellation()
                            layout.paragraph(zip(table.headers, row).map { $0 + ": " + ($1.isEmpty ? "[empty]" : $1) }.joined(separator: "; "), size: 9)
                        }
                    }
                    for bullet in table.bullets { try Task.checkCancellation(); layout.paragraph("• " + bullet) }
                    layout.heading("Reading note", size: 11)
                    for note in table.cautions { try Task.checkCancellation(); layout.paragraph(note, size: 10, color: darkGray) }
                }
            }
            if c.politics {
                heading("Reference comparison", keepWith: points.first(where: { !($0.relevance ?? "").isEmpty }).map { layout.height($0.relevance ?? "", size: 11) + 80 } ?? 80)
                for (index, point) in points.enumerated() {
                    try Task.checkCancellation()
                    guard let relevance = point.relevance, !relevance.isEmpty else { continue }
                    layout.ensure(min(695, layout.height(relevance, size: 11) + 80))
                    layout.heading(point.title, size: 13); layout.paragraph(relevance)
                    paragraphMetadata(point)
                    source(point, index: index)
                }
            }
            if c.questions {
                let first = points.indices.first { !points[$0].question.isEmpty && (!c.selectedQuestions || selectedIDs.contains(selectionKey(includedInsights[$0]))) }
                heading("Follow-up questions", keepWith: first.map { layout.height(points[$0].question, size: 11) + 80 } ?? 80)
                var number = 0
                let questionIndices = points.indices.filter { index in
                    !points[index].question.isEmpty && (!c.selectedQuestions || selectedIDs.contains(selectionKey(includedInsights[index])))
                }
                let orderedQuestionIndices = c.selectedQuestions ? questionIndices.sorted { a, b in
                    let ia = selectedOrder.firstIndex(of: selectionKey(includedInsights[a]))
                    let ib = selectedOrder.firstIndex(of: selectionKey(includedInsights[b]))
                    if let ia, let ib { return ia < ib }
                    if ia != nil { return true }
                    if ib != nil { return false }
                    return a < b
                } : questionIndices
                for index in orderedQuestionIndices {
                    let point = points[index]
                    try Task.checkCancellation()
                    number += 1
                    layout.ensure(min(695, layout.height(point.question, size: 11) + 80))
                    layout.heading("\(number). " + point.title, size: 13); layout.paragraph(point.question)
                    if c.selectedQuestions {
                        layout.paragraph("Review status: " + selectionStatus(selectionStatuses[SimpleWorkspace.selectionKey(includedInsights[index])] ?? .discuss), size: 9, color: darkGray)
                    }
                    source(point, index: index)
                }
            }
            if c.notes {
                let noted = includedInsights.filter { (!c.selectedPoints || selectedIDs.contains(selectionKey($0))) && annotations[selectionKey($0)] != nil }
                if !noted.isEmpty {
                    heading("Personal notes and review marks")
                    layout.paragraph("These are personal notes and review marks, not an automatic fact check.", size: 9, color: darkGray)
                    let orderedNoted = c.selectedPoints ? noted.sorted { a, b in
                        let ia = selectedOrder.firstIndex(of: selectionKey(a)), ib = selectedOrder.firstIndex(of: selectionKey(b))
                        if let ia, let ib { return ia < ib }
                        if ia != nil { return true }
                        if ib != nil { return false }
                        return false
                    } : noted
                    for point in orderedNoted {
                        try Task.checkCancellation()
                        guard let note = annotations[selectionKey(point)] else { continue }
                        layout.ensure(110); layout.heading(point.title, size: 13)
                        layout.paragraph("PDF page \(point.page) · " + (note.isChecked(point) ? "Checked by the user" : "Needs review"), size: 9, color: darkGray)
                        if c.selectedPoints { layout.paragraph("Review status: " + selectionStatus(selectionStatuses[selectionKey(point)] ?? .discuss), size: 9, color: darkGray) }
                        if !note.note.isEmpty { layout.paragraph(note.note) }
                    }
                }
            }
            if c.glossary {
                heading("Abbreviations and definitions", keepWith: glossary.first.map { layout.height($0.meaning, size: 11) + 85 } ?? 80)
                for item in glossary {
                    try Task.checkCancellation()
                    layout.ensure(min(695, layout.height(item.meaning, size: 11) + 85))
                    layout.heading(item.term, size: 13); layout.paragraph(item.meaning)
                    layout.paragraph(item.origin, size: 9, color: darkGray)
                }
            }
        } else {
        layout.heading("Summary", size: 18)
        layout.paragraph("Scope: " + UIStrings.text(summaryScope), size: 9, color: darkGray)
        if let summary {
            layout.paragraph(summary.digest.overview)
            if let warning = summary.incompleteNotice, !notice.contains(warning) { layout.paragraph(UIStrings.text(warning), size: 10) }
            layout.heading("Page summaries", size: 18)
            for section in summary.pageSections {
                try Task.checkCancellation()
                layout.heading("PDF page \(section.page)", size: 13)
                layout.paragraph(section.digest.overview)
                for bullet in section.digest.bullets { try Task.checkCancellation(); layout.paragraph("• " + bullet, size: 10) }
            }
            if summary.pageSections.isEmpty { layout.paragraph("No page summaries are available.") }
        } else { layout.paragraph("No document summary is available. Create one in the app to include it in the export.") }
        try chosenPassageSection(recordOutline: false)
        func pointHeight(_ point: Point, index: Int) -> CGFloat {
            var height = layout.height("\(index + 1). " + point.title, size: 14) + layout.height(point.summary, size: 11) + 42
            if !neutral, let relevance = point.relevance, !relevance.isEmpty {
                height += layout.height("Reference comparison", size: 10) + layout.height(relevance, size: 10)
            }
            if !point.question.isEmpty { height += layout.height("Follow-up question", size: 10) + layout.height(point.question, size: 11) }
            return height
        }
        if let first = points.first { layout.ensure(min(695, pointHeight(first, index: 0) + 50)) }
        layout.heading(neutral ? "Summary findings" : "Findings and questions", size: 18)
        if points.isEmpty { layout.paragraph("No findings were found in this selection.") }
        for (index, point) in points.enumerated() {
            try Task.checkCancellation()
            layout.ensure(min(695, pointHeight(point, index: index)))
            targets.append((layout.pages.count - 1, layout.y))
            layout.heading("\(index + 1). " + point.title, size: 14)
            layout.paragraph(point.summary)
            paragraphMetadata(point)
            if !neutral, let relevance = point.relevance, !relevance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                layout.heading("Reference comparison", size: 10)
                layout.paragraph(relevance, size: 10)
            }
            if !point.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                layout.heading(analyzed ? "Follow-up question" : "Example question (template)", size: 10)
                layout.paragraph(point.question)
            }
            layout.ensure(30)
            let top = layout.y
            let page = layout.pages.count - 1
            layout.paragraph("Source: physical PDF page \(([point.sourcePage] + point.extraSources.map(\.page)).map(String.init).joined(separator: ", "))" + (includeSources ? " · source quote \(index + 1) in appendix" : ""), size: 9, color: darkGray)
            if !point.contextSources.isEmpty {
                layout.paragraph("Context sources: physical PDF page " + point.contextSources.map(\.page).map(String.init).joined(separator: ", "), size: 9, color: darkGray)
            }
            if !point.passageSources.isEmpty {
                layout.paragraph("Full paragraph: physical PDF page " + point.passageSources.map(\.page).map(String.init).joined(separator: ", "), size: 9, color: darkGray)
            }
            if includeSources { links.append(Link(page: page, rect: CGRect(x: 48, y: top - 15, width: 499, height: 18), point: index)) }
            layout.y -= 8
        }
            targetTitles = points.map(\.title)
        }
        var sourceTargets: [(page: Int, y: CGFloat)] = []
        if includeSources && !points.isEmpty {
            layout.newPage()
            layout.heading("Source appendix", size: 20)
            var includedPassageIDs = Set<String>()
            for (index, point) in points.enumerated() {
                try Task.checkCancellation()
                layout.ensure(85)
                sourceTargets.append((layout.pages.count - 1, layout.y))
                layout.heading("\(index + 1). " + point.title, size: 13)
                layout.paragraph("Physical PDF page \(point.sourcePage)", size: 9, color: darkGray)
                layout.paragraph(point.quote, size: 10)
                for source in point.extraSources { try Task.checkCancellation(); layout.paragraph("Physical PDF page \(source.page)", size: 9); layout.paragraph(source.quote, size: 10) }
                for source in point.contextSources {
                    try Task.checkCancellation(); layout.paragraph("Context source · physical PDF page \(source.page)", size: 9, color: darkGray); layout.paragraph(source.quote, size: 10)
                }
                if !point.passageSources.isEmpty {
                    let isFirstPassagePart = point.passageID.map { includedPassageIDs.insert($0).inserted } ?? true
                    if isFirstPassagePart {
                        layout.heading("Sources for the complete paragraph", size: 10)
                        for source in point.passageSources {
                            try Task.checkCancellation(); layout.paragraph("Physical PDF page \(source.page)", size: 9, color: darkGray); layout.paragraph(source.quote, size: 10)
                        }
                    } else {
                        layout.paragraph("Sources for the complete paragraph are listed with its first part.", size: 9, color: darkGray)
                    }
                }
            }
        }
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else { throw AppError(message: "PDF export could not be started.") }
        var bounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw AppError(message: "PDF export could not be started.") }
        for (index, lines) in layout.pages.enumerated() {
            try Task.checkCancellation()
            context.beginPDFPage(nil)
            context.setFillColor(white); context.fill(bounds)
            draw("Foliance  /  " + (configuration != nil ? "DOCUMENT OVERVIEW" : neutral ? "DOCUMENT SUMMARY" : analyzed ? "DOCUMENT BRIEF" : "TREFWOORDSELECTIE"), x: 48, y: 812, size: 8, color: darkGray, context: context)
            for line in lines {
                if Task.isCancelled { throw CancellationError() }
                context.textPosition = CGPoint(x: line.x, y: line.y)
                context.setFillColor(line.color)
                CTLineDraw(line.text, context)
            }
            context.setStrokeColor(CGColor(gray: 0.78, alpha: 1));context.move(to: CGPoint(x: 48, y: 58));context.addLine(to: CGPoint(x: 547, y: 58));context.strokePath()
            draw("Foliance | Verify against the source | For personal use", x: 48, y: 40, size: 8, color: darkGray, context: context)
            draw("\(index + 1) / \(layout.pages.count)", x: 510, y: 40, size: 9, color: darkGray, context: context)
            context.endPDFPage()
        }
        context.closePDF()
        guard let rendered = PDFDocument(data: buffer as Data) else { throw AppError(message: "The generated PDF cannot be read.") }
        // A fresh document forces PDFKit to serialize page destinations and the outline.
        let pdf = PDFDocument()
        for index in 0..<rendered.pageCount {
            try Task.checkCancellation()
            if let page = rendered.page(at: index) { pdf.insert(page, at: index) }
        }
        pdf.documentAttributes = [PDFDocumentAttribute.titleAttribute: title ?? ("Foliance - " + document.name), PDFDocumentAttribute.authorAttribute: "Foliance"]
        let root = PDFOutline()
        root.label = configuration == nil ? (neutral ? "Summary findings" : "Findings") : "Contents"
        pdf.outlineRoot = root
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            guard let page = pdf.page(at: target.page) else { continue }
            let destination = PDFDestination(page: page, at: CGPoint(x: 0, y: target.y))
            let item = PDFOutline();item.label = String(format: "P%02d  ", index + 1) + targetTitles[index];item.destination = destination
            root.insertChild(item, at: index)
        }
        pdf.outlineRoot = root
        for link in links {
            try Task.checkCancellation()
            guard let source = pdf.page(at: link.page), let target = pdf.page(at: sourceTargets[link.point].page) else { continue }
            let annotation = PDFAnnotation(bounds: link.rect, forType: .link, withProperties: nil)
            annotation.destination = PDFDestination(page: target, at: CGPoint(x: 0, y: sourceTargets[link.point].y))
            let border = PDFBorder();border.lineWidth = 0;annotation.border = border;source.addAnnotation(annotation)
        }
        try Task.checkCancellation()
        guard let data = pdf.dataRepresentation() else { throw AppError(message: "The PDF could not be saved.") }
        try Task.checkCancellation()
        return data
    }

    private static func selectionStatus(_ status: SelectionMeetingStatus) -> String {
        switch status {
        case .discuss: "Discuss"
        case .askQuestion: "Ask a question"
        case .done: "Done"
        }
    }

    private static func selectionKey(_ point: Insight) -> String {
        SimpleWorkspace.selectionKey(point)
    }
    private static func rank(_ theme: String) -> Int { Theme.coreValues.contains { $0.id == theme } ? 0 : 1 }
    private static func font(size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    }
    private static func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y);CTLineDraw(line, context)
    }
    private final class Layout {
        var pages: [[Line]] = [[]]
        var y: CGFloat = 775
        func newPage() { pages.append([]);y = 775 }
        func ensure(_ height: CGFloat) { if y - height < 80 { newPage() } }
        func heading(_ text: String, size: CGFloat, color: CGColor = BriefingPDF.black) {
            ensure(size * 2 + 40)
            paragraph(text, size: size, color: color, bold: true)
        }
        func height(_ text: String, size: CGFloat) -> CGFloat {
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): BriefingPDF.font(size: size, bold: true)]
            let value = NSAttributedString(string: text, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(value)
            var start = 0; var lines = 0
            while start < value.length {
                if Task.isCancelled { break }
                start += max(1, CTTypesetterSuggestLineBreak(typesetter, start, 499)); lines += 1
            }
            return CGFloat(lines) * size * 1.45 + 12
        }
        func paragraph(_ text: String, size: CGFloat = 11, color: CGColor = BriefingPDF.black, bold: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): BriefingPDF.font(size: size, bold: bold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            let value = NSAttributedString(string: text, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(value)
            var start = 0
            let leading = size * 1.45
            while start < value.length {
                if Task.isCancelled { return }
                ensure(leading)
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, 499))
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                pages[pages.count - 1].append(Line(text: line, x: 48, y: y - size, color: color))
                y -= leading; start += count
            }
            y -= 12
        }
    }
}
