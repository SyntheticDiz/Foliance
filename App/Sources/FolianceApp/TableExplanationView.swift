import SwiftUI

struct TableExplanationView: View {
    let tables: [DocumentTable]
    let showPage: (Int) -> Void
    var tutorialExpanded: Bool? = nil
    var tutorialTableExpanded: Bool? = nil
    var sourceData: Data? = nil
    var saveReview: ((DocumentTable) -> Void)? = nil
    var analyzeReview: ((String) -> Void)? = nil
    var stopAnalysis: (() -> Void)? = nil
    var reviewDisabled = false
    var analysisID: String? = nil
    var analysisError: String? = nil
    var externalOpenTableIDs: Binding<Set<String>>? = nil
    var targetTableID: String? = nil
    var onTargetTable: ((String) -> Void)? = nil
    @State private var expanded = false
    @State private var openTables: Set<String> = []
    @State private var handledTargetTableID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tables: [DocumentTable], showPage: @escaping (Int) -> Void,
         tutorialExpanded: Bool? = nil, tutorialTableExpanded: Bool? = nil,
         sourceData: Data? = nil, saveReview: ((DocumentTable) -> Void)? = nil,
         analyzeReview: ((String) -> Void)? = nil, stopAnalysis: (() -> Void)? = nil,
         reviewDisabled: Bool = false, analysisID: String? = nil, analysisError: String? = nil,
         openTableIDs: Binding<Set<String>>? = nil, targetTableID: String? = nil,
         onTargetTable: ((String) -> Void)? = nil) {
        self.tables = tables
        self.showPage = showPage
        self.tutorialExpanded = tutorialExpanded
        self.tutorialTableExpanded = tutorialTableExpanded
        self.sourceData = sourceData
        self.saveReview = saveReview
        self.analyzeReview = analyzeReview
        self.stopAnalysis = stopAnalysis
        self.reviewDisabled = reviewDisabled
        self.analysisID = analysisID
        self.analysisError = analysisError
        self.externalOpenTableIDs = openTableIDs
        self.targetTableID = targetTableID
        self.onTargetTable = onTargetTable
    }

    var body: some View {
        if !tables.isEmpty {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        animateDisclosure { expanded.toggle() }
                    } label: {
                        HStack {
                            Text(UIStrings.text("Table explanations · \(tables.count)"))
                                .font(.title3.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                    .tutorialTarget("table")

                    if expanded {
                        Text(UIStrings.text("Recognized tables and reading points. Image tables are read locally with OCR and must be checked against the source."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(tables) { table in
                            TableExplanationCard(
                                table: table,
                                isOpen: isTableOpen(table.id),
                                toggleOpen: { toggleTable(table.id) },
                                showPage: showPage,
                                sourceData: sourceData,
                                saveReview: saveReview,
                                analyzeReview: analyzeReview,
                                stopAnalysis: stopAnalysis,
                                reviewDisabled: reviewDisabled,
                                analysisID: analysisID,
                                analysisError: analysisError,
                                animateDisclosure: animateDisclosure
                            )
                            .id("table-card-\(table.id)")
                        }
                    }
                }
                .font(.body)
                .lineSpacing(5)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readingSurface()
                .onAppear { syncTutorialState() }
                .onChange(of: tutorialExpanded) { _, _ in syncTutorialState() }
                .onChange(of: tutorialTableExpanded) { _, _ in syncTutorialState() }
                .onAppear { navigateToTarget(targetTableID, proxy: proxy) }
                .onChange(of: targetTableID) { _, newValue in
                    if newValue == nil { handledTargetTableID = nil }
                    navigateToTarget(newValue, proxy: proxy)
                }
            }
        }
    }

    private func animateDisclosure(_ update: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24), update)
    }

    private func syncTutorialState() {
        if let tutorialExpanded { expanded = tutorialExpanded }
        if let tutorialTableExpanded {
            setOpenTableIDs(tutorialTableExpanded ? Set(tables.map(\.id)) : [])
        }
    }

    private func isTableOpen(_ id: String) -> Bool {
        (externalOpenTableIDs?.wrappedValue ?? openTables).contains(id)
    }

    private func toggleTable(_ id: String) {
        var current = externalOpenTableIDs?.wrappedValue ?? openTables
        if !current.insert(id).inserted { current.remove(id) }
        setOpenTableIDs(current)
    }

    private func setOpenTableIDs(_ ids: Set<String>) {
        if let externalOpenTableIDs { externalOpenTableIDs.wrappedValue = ids }
        else { openTables = ids }
    }

    private func navigateToTarget(_ id: String?, proxy: ScrollViewProxy) {
        guard let id, id != handledTargetTableID, tables.contains(where: { $0.id == id }) else { return }
        handledTargetTableID = id
        expanded = true
        var current = externalOpenTableIDs?.wrappedValue ?? openTables
        current.insert(id)
        setOpenTableIDs(current)
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                proxy.scrollTo("table-card-\(id)", anchor: .top)
            }
            onTargetTable?(id)
        }
    }
}

private struct TableExplanationCard: View {
    let table: DocumentTable
    let isOpen: Bool
    let toggleOpen: () -> Void
    let showPage: (Int) -> Void
    let sourceData: Data?
    let saveReview: ((DocumentTable) -> Void)?
    let analyzeReview: ((String) -> Void)?
    let stopAnalysis: (() -> Void)?
    let reviewDisabled: Bool
    let analysisID: String?
    let analysisError: String?
    let animateDisclosure: (() -> Void) -> Void
    @State private var reviewTable: DocumentTable?
    @State private var tableDataExpanded = false
    @State private var readingPointsExpanded = false
    @State private var controlsExpanded = false

    private var validation: OCRTableValidation.Report? {
        table.recognizedWithOCR == true ? OCRTableValidation.report(table) : nil
    }

    private var isAnalyzingThisTable: Bool { analysisID == table.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggleOpen) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(table.displayTitle).font(.headline)
                        if table.displayTitle != table.title {
                            Text(UIStrings.text("Table title in source: ") + table.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(UIStrings.text("Source page ") + table.pages.map(String.init).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if table.recognizedWithOCR == true {
                            OCRStatusLine(confirmed: table.isOCRConfirmed, unresolvedCount: validation?.unresolvedCells.count ?? 0)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            // Keep active work and the compact OCR status available even when the
            // detailed row is closed, without expanding every table in long lists.
            if isAnalyzingThisTable {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UIStrings.text("Selecting table findings…"))
                    Button(UIStrings.text("Stop")) { stopAnalysis?() }
                        .buttonStyle(FocusQuietActionStyle())
                }
                .font(.caption)
            }

            if table.recognizedWithOCR == true, let analysisError, !analysisError.isEmpty {
                Text(analysisError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if isOpen {
                Text(table.overview)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !table.cautions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(UIStrings.text("Notes for reading")).font(.subheadline.weight(.semibold))
                        ForEach(Array(table.cautions.enumerated()), id: \.offset) { _, caution in
                            Text(caution)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }

                sourcePageActions

                if table.recognizedWithOCR == true {
                    disclosureSection("Table details", isExpanded: $tableDataExpanded) {
                        OCRTableDataContent(table: table)
                    }
                    disclosureSection("Reading notes", isExpanded: $readingPointsExpanded) {
                        TableReadingPointsContent(table: table)
                    }
                    disclosureSection("Checks and corrections", isExpanded: $controlsExpanded) {
                        TableReviewControls(
                            table: table,
                            validation: validation,
                            reviewDisabled: reviewDisabled,
                            analysisID: analysisID,
                            analysisError: analysisError,
                            canReview: saveReview != nil,
                            canAnalyze: analyzeReview != nil,
                            review: { reviewTable = table },
                            analyze: { analyzeReview?(table.id) }
                        )
                    }
                } else {
                    disclosureSection("Reading notes", isExpanded: $readingPointsExpanded) {
                        TableReadingPointsContent(table: table)
                    }
                }
            }
        }
        .padding(14)
        .readingSurface()
        .sheet(item: $reviewTable) { table in
            OCRTableReviewView(table: table, data: sourceData) { corrected in
                saveReview?(corrected)
            }
        }
    }

    @ViewBuilder
    private var sourcePageActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(table.pages, id: \.self) { pageButton($0) } }
            VStack(alignment: .leading) { ForEach(table.pages, id: \.self) { pageButton($0) } }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private func pageButton(_ page: Int) -> some View {
        Button(UIStrings.text("Show in PDF · p. \(page)"), systemImage: "doc.text.magnifyingglass") {
            showPage(page)
        }
        .buttonStyle(FocusQuietActionStyle())
    }

    private func disclosureSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                animateDisclosure { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack {
                    Text(UIStrings.text(title)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(FocusQuietActionStyle())
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")

            if isExpanded.wrappedValue { content() }
        }
        .padding(.top, 4)
    }
}

private struct OCRStatusLine: View {
    let confirmed: Bool
    let unresolvedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(UIStrings.text(confirmed ? "OCR · checked by you" : "OCR · needs review"))
                .foregroundStyle(confirmed ? Color.secondary : Color.orange)
            Text("\(unresolvedCount) unresolved \(unresolvedCount == 1 ? "cell" : "cells")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct OCRTableDataContent: View {
    let table: DocumentTable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.text("Recognized cells — check figures, minus signs, and columns in the PDF. ‘Unreadable’ means a character is present that OCR could not read. Empty cells are not zero. The regular document analysis does not use this OCR text. After checking the source, you can select separate table findings."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { index in
                            Text(table.headers[index])
                                .bold()
                                .frame(width: index == 0 ? 220 : 145, alignment: .leading)
                        }
                    }
                    ForEach(table.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(table.headers.indices, id: \.self) { column in
                                Text(column < table.rows[row].count ? table.rows[row][column] : "")
                                    .frame(width: column == 0 ? 220 : 145, alignment: .leading)
                            }
                        }
                        Divider().gridCellColumns(table.headers.count)
                    }
                }
                .font(.caption)
                .textSelection(.enabled)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct TableReadingPointsContent: View {
    let table: DocumentTable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if table.isOCRConfirmed, let digest = table.ocrReview?.summary {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UIStrings.text("Reviewed table data")).font(.subheadline.weight(.semibold))
                    Text(digest.overview).font(.caption).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(digest.bullets.enumerated()), id: \.offset) { _, fact in
                        Text(UIStrings.text("• ") + fact).textSelection(.enabled)
                    }
                }
            }
            if !table.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UIStrings.text("Original reading points")).font(.subheadline.weight(.semibold))
                    ForEach(Array(table.bullets.enumerated()), id: \.offset) { _, text in
                        Text(UIStrings.text("• ") + text)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct TableReviewControls: View {
    let table: DocumentTable
    let validation: OCRTableValidation.Report?
    let reviewDisabled: Bool
    let analysisID: String?
    let analysisError: String?
    let canReview: Bool
    let canAnalyze: Bool
    let review: () -> Void
    let analyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let validation {
                Text("\(validation.unresolvedCells.count) unresolved \(validation.unresolvedCells.count == 1 ? "cell" : "cells") · \(validation.checks.filter { $0.state == .matched }.count) calculation checks match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !validation.checks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(validation.checks.enumerated()), id: \.offset) { _, check in
                            Text("\(check.label): \(check.detail)")
                                .font(.caption)
                                .foregroundStyle(check.state == .mismatch ? Color.orange : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if canReview {
                Button(UIStrings.text("Review or correct cells"), systemImage: "pencil.and.list.clipboard", action: review)
                    .buttonStyle(FocusSecondaryButtonStyle())
                    .disabled(reviewDisabled || analysisID != nil)
                Text(UIStrings.text("Save a workspace (⌘S) to restore corrections and source review later."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if canAnalyze {
                Button("Analyze reviewed table", systemImage: "sparkles", action: analyze)
                    .buttonStyle(FocusSecondaryButtonStyle())
                    .disabled(reviewDisabled || analysisID != nil || !table.isOCRConfirmed || !(validation?.canConfirm ?? false))
            }

        }
    }
}
