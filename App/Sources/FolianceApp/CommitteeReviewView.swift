import SwiftUI

struct CommitteeCardContext {
    var label: String
    var reason: String? = nil
    var evidence: String? = nil
    var sources: [Insight.Source] = []
}

struct CommitteeReviewView<PointContent: View>: View {
    @ObservedObject var workspace: SimpleWorkspace
    @Binding var showAll: Bool
    @Binding var expandedCategories: Set<String>
    var hasStoredCategoryState = false
    var pageFilter = ""
    var reviewFilter = 0
    var pendingPointID: String? = nil
    let showSource: (Int, String) -> Void
    let pointContent: (Insight, CommitteeCardContext) -> PointContent
    @State private var visibleLimits: [String: Int] = [:]
    @State private var expandedPassages: Set<String> = []
    @State private var expandedSourceQuotes: Set<String> = []
    @State private var expandedSourceDetails: Set<String> = []
    @State private var expandedSubgroups: Set<String> = []
    @State private var categoryOrder: [String]?
    @State private var initialExpansionApplied = false
    @State private var checkingExpanded = false
    @State private var readerPoint: Insight?
    private let uiLanguage = "en"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: CommitteePresentationSnapshot? {
        workspace.committeePresentationSnapshot(for: workspace.meetingPurpose)
    }
    private var selectedPages: Set<Int>? {
        guard !pageFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Set((try? PageScope.parse(pageFilter, count: workspace.document?.pages.count ?? 0)) ?? [])
    }
    private func filtered(_ snapshot: CommitteePresentationSnapshot) -> CommitteePresentationSnapshot.Filtered {
        snapshot.filtered(pages: selectedPages, reviewFilter: reviewFilter, annotation: workspace.annotation)
    }
    private var allRows: [CommitteePointPresentation.Row] { presentation.map { filtered($0).rows } ?? [] }
    var body: some View {
        let snapshot = presentation
        let filteredRows = snapshot.map { filtered($0) }
        let rows = filteredRows?.rows ?? []
        let baseGroups = filteredRows?.categoryGroups ?? []
        let orderedIDs = CommitteeDisplayPresentation.stableCategoryOrder(existing: categoryOrder, groups: baseGroups, purpose: workspace.meetingPurpose)
        let mainByID = Dictionary(uniqueKeysWithValues: (showAll ? baseGroups : (filteredRows?.mainGroups ?? [])).map { ($0.id, $0) })
        let checkByID = Dictionary(uniqueKeysWithValues: (showAll ? [] : (filteredRows?.checkingGroups ?? [])).map { ($0.id, $0) })
        let mainGroups = orderedIDs.compactMap { mainByID[$0] }
        let checkGroups = orderedIDs.compactMap { checkByID[$0] }
        let importantCount = rows.filter { $0.assessment.rating == .important }.count
        return VStack(alignment: .leading, spacing: 16) {
            FocusChoiceTabs(UIStrings.text("Toon punten"), selection: $showAll, options: [
                FocusChoiceOption(value: false, title: UIStrings.text("Belangrijkste"), count: importantCount),
                FocusChoiceOption(value: true, title: UIStrings.text("Alle punten"), count: rows.count)
            ])
                .frame(maxWidth: 640)
                .help(UIStrings.text("Aantallen zijn bronpassages; een passage kan meerdere punten bevatten."))
            if workspace.committeeReviews[workspace.meetingPurpose.rawValue] != nil {
                ForEach(mainGroups) { group in
                    categoryGroup(group)
                }
                if !checkGroups.isEmpty {
                    DisclosureGroup(isExpanded: $checkingExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(checkGroups) { group in
                                if group.isUnassigned {
                                    unassignedGroups(group.rows, parentID: group.id)
                                } else {
                                    Text(UIStrings.text(group.title)).font(.headline).padding(.top, 8)
                                    Text("\(group.rows.count) " + UIStrings.text(group.rows.count == 1 ? "passage" : "passages"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    rowsDisclosure(group.rows, limitKey: "checking-\(group.id)")
                                }
                            }
                        }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack {
                            Text(UIStrings.text("Nog controleren")).font(.headline)
                            Spacer()
                            Text("\(checkGroups.reduce(0) { $0 + $1.rows.count }) " + UIStrings.text("passages"))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12)
                }
                if mainGroups.isEmpty && checkGroups.isEmpty {
                    Text(UIStrings.text(showAll
                        ? "Geen passages voor deze filters. Pas de filters aan om andere passages te bekijken."
                        : "Geen belangrijk bevonden passages in deze weergave. Bekijk Alle punten of pas de filters aan."))
                        .foregroundStyle(.secondary)
                }
                if showAll, let snapshot, !snapshot.presentation.unmatchedPoints.isEmpty {
                    DisclosureGroup(UIStrings.text("Overige bestaande punten") + " (\(snapshot.presentation.unmatchedPoints.count))") {
                        ForEach(snapshot.presentation.unmatchedPoints.filter { PointDisplayFilter.matches($0, pages: selectedPages, reviewFilter: reviewFilter, annotation: workspace.annotation(for: $0)) }) { point in
                            pointContent(point, .init(label: "Koppeling controleren"))
                        }
                    }
                }
            } else {
                Text(UIStrings.text("Nog geen gerichte beoordeling beschikbaar. De bron en bestaande analyse blijven behouden.")).foregroundStyle(.secondary)
                if showAll {
                    ForEach(workspace.organizedInsights.filter { PointDisplayFilter.matches($0, pages: selectedPages, reviewFilter: reviewFilter, annotation: workspace.annotation(for: $0)) }) { point in
                        pointContent(point, .init(label: "Nog niet beoordeeld"))
                    }
                }
            }
        }
        .onAppear {
            let currentOrder = updateCategoryOrder(baseGroups)
            applyInitialExpansionIfNeeded(groups: baseGroups, orderedIDs: currentOrder)
            revealPendingPoint()
        }
        .onChange(of: baseGroups.map { "\($0.id):\($0.importantCount):\($0.rows.count)" }) { _, _ in
            let currentOrder = updateCategoryOrder(baseGroups)
            applyInitialExpansionIfNeeded(groups: baseGroups, orderedIDs: currentOrder)
        }
        .onChange(of: pendingPointID) { _, _ in revealPendingPoint() }
        .onChange(of: workspace.meetingPurpose) { _, _ in
            visibleLimits = [:]; expandedPassages = []; expandedSubgroups = []; checkingExpanded = false
            categoryOrder = nil
            initialExpansionApplied = false
            let currentOrder = updateCategoryOrder(baseGroups)
            applyInitialExpansionIfNeeded(groups: baseGroups, orderedIDs: currentOrder)
        }
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        .sheet(item: $readerPoint) { point in
            CardPassageReaderView(point: point,
                                  sources: .forCard(point,
                                                   committeeContextSources: readerContextSources(for: point),
                                                   committeeEvidence: readerEvidence(for: point)),
                                  showSource: showSource)
        }
    }

    @discardableResult private func updateCategoryOrder(_ groups: [CommitteeDisplayPresentation.CategoryGroup]) -> [String] {
        guard !groups.isEmpty else { return categoryOrder ?? [] }
        let order = CommitteeDisplayPresentation.stableCategoryOrder(existing: categoryOrder, groups: groups, purpose: workspace.meetingPurpose)
        if categoryOrder != order { categoryOrder = order }
        return order
    }

    private func applyInitialExpansionIfNeeded(groups: [CommitteeDisplayPresentation.CategoryGroup], orderedIDs: [String]) {
        guard !initialExpansionApplied, !groups.isEmpty else { return }
        if let initialState = CommitteeDisplayPresentation.initialExpandedCategoryState(
            storedState: expandedCategories, hasStoredState: hasStoredCategoryState,
            orderedIDs: orderedIDs, groups: groups) {
            if !hasStoredCategoryState { expandedCategories = initialState }
        }
        initialExpansionApplied = true
    }

    private func categoryGroup(_ group: CommitteeDisplayPresentation.CategoryGroup) -> some View {
        let categoryRows = group.rows
        return DisclosureGroup(isExpanded: categoryBinding(group.id)) {
            VStack(alignment: .leading, spacing: 8) {
                if group.isUnassigned {
                    unassignedGroups(categoryRows, parentID: group.id)
                } else {
                    if group.importantCount > 0 {
                        Text("\(categoryRows.count) " + UIStrings.text(categoryRows.count == 1 ? "passage" : "passages"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    rowsDisclosure(categoryRows, limitKey: group.id)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(UIStrings.text(group.title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let count = group.importantCount
                if count > 0 {
                    Text("\(count) " + UIStrings.text("belangrijk")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("\(categoryRows.count) " + UIStrings.text(categoryRows.count == 1 ? "passage" : "passages")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(.top, 14)
    }

    @ViewBuilder private func unassignedGroups(_ rows: [CommitteePointPresentation.Row], parentID: String) -> some View {
        ForEach(CommitteeDisplayPresentation.unassignedSubgroups(rows)) { subgroup in
            let key = parentID + "-" + subgroup.id
            DisclosureGroup(isExpanded: subgroupBinding(key)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(subgroup.rows.count) " + UIStrings.text(subgroup.rows.count == 1 ? "passage" : "passages"))
                        .font(.caption).foregroundStyle(.secondary)
                    rowsDisclosure(subgroup.rows, limitKey: key)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack {
                    Text(UIStrings.text(subgroup.title)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(subgroup.rows.count) " + UIStrings.text(subgroup.rows.count == 1 ? "passage" : "passages"))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }.padding(.leading, 8)
        }
    }

    private func rowsDisclosure(_ rows: [CommitteePointPresentation.Row], limitKey: String) -> some View {
        let limit = visibleLimits[limitKey] ?? 12
        return VStack(alignment: .leading, spacing: 10) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rows.prefix(limit)), id: \.scrollID) { row in assessmentRow(row) }
            }
            if rows.count > limit {
                Button(UIStrings.text("Toon meer passages")) { visibleLimits[limitKey] = limit + 12 }.padding(.top, 8)
            }
        }.padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assessmentRow(_ row: CommitteePointPresentation.Row) -> some View {
        let assessment = row.assessment
        let context = CommitteeCardContext(label: ratingTitle(assessment.rating), reason: assessment.reason, evidence: assessment.evidenceQuote, sources: assessment.contextSources ?? [])
        return VStack(alignment: .leading, spacing: 20) {
            if let first = row.points.first {
                pointContent(first, context)
                if row.points.count > 1 {
                    DisclosureGroup(isExpanded: Binding(get: { expandedPassages.contains(row.id) }, set: { if $0 { expandedPassages.insert(row.id) } else { expandedPassages.remove(row.id) } })) {
                        ForEach(Array(row.points.dropFirst())) { point in pointContent(point, .init(label: context.label)) }
                    } label: { Text(UIStrings.text("Meer punten uit deze alinea") + " (\(row.points.count - 1))").font(.caption) }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        if let first = assessment.sources.first { showSource(first.page, first.quote) }
                        toggleSourceQuoteExpansion(assessment)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(UIStrings.text("Bronpassage") + " · p. " + assessment.sources.map { String($0.page) }.joined(separator: ", "))
                                .font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(UIStrings.text("Bronpassage") + " · p. " + assessment.sources.map { String($0.page) }.joined(separator: ", "))
                    .accessibilityHint(UIStrings.text("Open deze bronpassage in de PDF"))
                    sourceQuotePreview(assessment)
                    Text(UIStrings.text(context.label)).font(.caption.weight(.semibold)).foregroundStyle(assessment.rating == .unassessed || assessment.rating == .uncertain ? Color.orange : Color.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            sourceOnlyActions(assessment)
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            sourceOnlyActions(assessment)
                        }
                    }.controlSize(.regular)
                    if expandedSourceDetails.contains(assessment.passageID) {
                        sourceOnlyDetails(assessment)
                    }
                }.font(.body).lineSpacing(4).padding(22).readingSurface()
            }
            let tags = CommitteeCategorizationService.validatedSecondaryCategoryIDs(for: assessment, purpose: workspace.meetingPurpose)
            if !tags.isEmpty {
                Text(tags.map { CommitteeCategory.title(for: $0, purpose: workspace.meetingPurpose) }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func sourceQuotePreview(_ assessment: CommitteeAssessmentService.Assessment) -> some View {
        let quote = assessment.sources.map(\.quote).joined(separator: "\n")
        return FadingPreviewText(text: quote, font: .system(size: 14), color: .secondary,
                                 lineSpacing: 4, collapsedLines: 4, language: uiLanguage,
                                 isExpanded: sourceQuoteExpansion(assessment),
                                 onTextTap: {
                                    if let first = assessment.sources.first { showSource(first.page, first.quote) }
                                 })
    }
    private func sourceQuoteExpansion(_ assessment: CommitteeAssessmentService.Assessment) -> Binding<Bool> {
        let passageID = assessment.passageID
        return Binding(
            get: { expandedSourceQuotes.contains(passageID) },
            set: { isExpanded in
                if isExpanded { expandedSourceQuotes.insert(passageID) }
                else { expandedSourceQuotes.remove(passageID) }
            }
        )
    }
    private func toggleSourceQuoteExpansion(_ assessment: CommitteeAssessmentService.Assessment) {
        let passageID = assessment.passageID
        if expandedSourceQuotes.contains(passageID) { expandedSourceQuotes.remove(passageID) }
        else { expandedSourceQuotes.insert(passageID) }
    }
    @ViewBuilder private func sourceOnlyActions(_ assessment: CommitteeAssessmentService.Assessment) -> some View {
        Button(UIStrings.text("Lees passage")) { readerPoint = sourcePoint(assessment) }
            .buttonStyle(FocusQuietActionStyle())
        Button(UIStrings.text(expandedSourceDetails.contains(assessment.passageID) ? "Minder details" : "Details")) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                if expandedSourceDetails.contains(assessment.passageID) { expandedSourceDetails.remove(assessment.passageID) }
                else { expandedSourceDetails.insert(assessment.passageID) }
            }
        }.buttonStyle(FocusQuietActionStyle())
    }
    @ViewBuilder private func sourceOnlyDetails(_ assessment: CommitteeAssessmentService.Assessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Waarom is dit relevant voor het gekozen leesdoel?")).font(.caption.bold())
            Text(assessment.reason).textSelection(.enabled)
            Button(UIStrings.text("Opnemen in samenvatting"), systemImage: "plus") {
            _ = workspace.addChosenPassage(.init(text: assessment.sources.map(\.quote).joined(separator: "\n"), pages: assessment.sources.map(\.page), sources: assessment.sources.map { .init(page: $0.page, quote: $0.quote) }))
            }.buttonStyle(FocusQuietActionStyle()).disabled(workspace.exporting)
        }.font(.callout)
    }
    private func readerEvidence(for point: Insight) -> String? {
        readerAssessment(for: point)?.evidenceQuote
    }
    private func readerContextSources(for point: Insight) -> [Insight.Source] {
        readerAssessment(for: point)?.contextSources ?? []
    }
    private func readerAssessment(for point: Insight) -> CommitteeAssessmentService.Assessment? {
        guard let id = point.passageID else { return nil }
        return presentation?.presentation.rows.first(where: { $0.assessment.passageID == id })?.assessment
    }
    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expandedCategories.contains(id) }, set: { if $0 { expandedCategories.insert(id) } else { expandedCategories.remove(id) } })
    }
    private func subgroupBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expandedSubgroups.contains(id) }, set: { if $0 { expandedSubgroups.insert(id) } else { expandedSubgroups.remove(id) } })
    }
    private func revealPendingPoint() {
        guard let id = pendingPointID, let row = allRows.first(where: { $0.points.contains(where: { $0.id == id }) }) else { return }
        let allViewWillShow = showAll || [.relevant, .other].contains(row.assessment.rating)
        if allViewWillShow { showAll = true }
        let groupID = CommitteeCategorizationService.validatedPrimaryCategoryID(for: row.assessment, purpose: workspace.meetingPurpose) ?? CommitteeCategory.unassignedID
        let inCheckingFold = !allViewWillShow && [.uncertain, .unassessed].contains(row.assessment.rating)
        if inCheckingFold { checkingExpanded = true }
        expandedCategories.insert(groupID)
        expandedPassages.insert(row.id)
        let key: String
        if groupID == CommitteeCategory.unassignedID {
            let subgroup = CommitteeDisplayPresentation.unassignedSubgroups([row]).first?.id ?? "topic-missing"
            key = groupID + "-" + subgroup
            expandedSubgroups.insert(key)
        } else {
            key = inCheckingFold ? "checking-\(groupID)" : groupID
        }
        let within = allRows.filter { candidate in
            let candidateGroup = CommitteeCategorizationService.validatedPrimaryCategoryID(for: candidate.assessment, purpose: workspace.meetingPurpose) ?? CommitteeCategory.unassignedID
            guard candidateGroup == groupID else { return false }
            if groupID == CommitteeCategory.unassignedID {
                return CommitteeDisplayPresentation.unassignedSubgroups([candidate]).first?.id == CommitteeDisplayPresentation.unassignedSubgroups([row]).first?.id
            }
            return inCheckingFold ? [.uncertain, .unassessed].contains(candidate.assessment.rating) :
                (allViewWillShow || ![.uncertain, .unassessed].contains(candidate.assessment.rating))
        }
        if let index = within.firstIndex(where: { $0.id == row.id }) { visibleLimits[key] = max(12, index + 1) }
    }
    private func sourcePoint(_ assessment: CommitteeAssessmentService.Assessment) -> Insight {
        Insight(title: "Volledige bronpassage", summary: "", relevance: "", question: "", quote: assessment.sources.first?.quote ?? "", page: assessment.sources.first?.page ?? 1, passageID: assessment.passageID, passageSources: assessment.sources)
    }
    private func ratingTitle(_ rating: CommitteeAssessmentService.Rating) -> String {
        switch rating {
        case .important: "Belangrijk voor dit leesdoel"
        case .relevant: "Relevant voor dit leesdoel"
        case .other: "Andere onderwerpen"
        case .uncertain: "Twijfel: controleer de volledige alinea"
        case .unassessed: "Niet automatisch beoordeeld"
        }
    }
}
