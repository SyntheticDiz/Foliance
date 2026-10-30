import SwiftUI

struct ChosenPassagesView: View {
    @ObservedObject var workspace: SimpleWorkspace
    var showSource: (Int, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(UIStrings.text("Zelf gekozen"), systemImage: "text.quote")
                    .font(.headline)
                Text("\(workspace.chosenPassages.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(UIStrings.text("Letterlijke passages uit de PDF"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if workspace.chosenPassages.isEmpty {
                Text(UIStrings.text("Kies tekst in de PDF en neem die op in je selectie."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(workspace.chosenPassages.enumerated()), id: \.element.id) { index, passage in
                        ChosenPassageCard(passage: passage, index: index, count: workspace.chosenPassages.count,
                                          workspace: workspace, showSource: showSource)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readingSurface()
    }
}

private struct ChosenPassageCard: View {
    let passage: ChosenPassage
    let index: Int
    let count: Int
    @ObservedObject var workspace: SimpleWorkspace
    var showSource: (Int, String) -> Void
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var showingReader = false
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    private let uiLanguage = "en"
    private var canModify: Bool { !workspace.exporting && !(workspace.busy && workspace.processingPresented && !workspace.processingDocumentReady) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(passage.title.isEmpty ? UIStrings.text("Gekozen passage") : passage.title)
                    .font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Menu {
                    Button(UIStrings.text("Omhoog"), systemImage: "arrow.up") {
                        workspace.moveChosenPassage(id: passage.id, by: -1)
                    }.disabled(index == 0 || !canModify)
                    Button(UIStrings.text("Omlaag"), systemImage: "arrow.down") {
                        workspace.moveChosenPassage(id: passage.id, by: 1)
                    }.disabled(index >= count - 1 || !canModify)
                    Divider()
                    Button(UIStrings.text("Wijzig"), systemImage: "pencil") { beginEditing() }
                        .help(UIStrings.text("Titel en notitie wijzigen")).disabled(editing || !canModify)
                    Button(UIStrings.text("Verwijder"), systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }.help(UIStrings.text("Verwijder passage")).disabled(!canModify)
                } label: {
                    Label(UIStrings.text("Meer"), systemImage: "ellipsis")
                }
                .focusMenu()
                .controlSize(.small)
            }

            FadingPreviewText(text: passage.text, font: .caption, color: .secondary,
                              collapsedLines: 3, language: uiLanguage)

            if editing {
                TextField(UIStrings.text("Titel"), text: $titleDraft)
                    .textFieldStyle(FocusInputFieldStyle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIStrings.text("Eigen notitie")).font(.caption.bold())
                    TextEditor(text: $noteDraft).frame(minHeight: 52, maxHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                HStack {
                    Button(UIStrings.text("Annuleer")) { editing = false }
                    Button(UIStrings.text("Bewaar")) { save() }
                        .buttonStyle(FocusPrimaryButtonStyle()).disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canModify)
                }
            } else if !passage.note.isEmpty {
                if passage.note.count <= 180 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(UIStrings.text("Eigen notitie")).font(.caption.bold())
                        Text(passage.note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } else {
                    DisclosureGroup(UIStrings.text("Eigen notitie")) {
                        Text(passage.note).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.top, 4)
                    }
                }
            }

            Button {
                showingReader = true
            } label: {
                Label(UIStrings.text("Lees passage"), systemImage: "text.alignleft")
            }
            .buttonStyle(FocusSecondaryButtonStyle())
            sourceActions
        }
        .padding(12)
        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .id("chosen-\(passage.id.uuidString)")
        .confirmationDialog(UIStrings.text("Passage verwijderen?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(UIStrings.text("Verwijder passage"), role: .destructive) {
                workspace.removeChosenPassage(id: passage.id)
            }
            Button(UIStrings.text("Annuleer"), role: .cancel) {}
        } message: { Text(UIStrings.text("De passage en eigen notitie worden uit Mijn selectie verwijderd.")) }
        .sheet(isPresented: $showingReader) {
            PassageReaderView(chosenPassage: passage) { page, quote in showSource(page, quote) }
        }
    }

    private func beginEditing() {
        titleDraft = passage.title
        noteDraft = passage.note
        editing = true
    }

    private func save() {
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        workspace.updateChosenPassage(id: passage.id, title: title, note: noteDraft)
        editing = false
    }

    @ViewBuilder private var sourceActions: some View {
        let sources = sourcePageEntries
        if sources.count > 2 {
            Menu {
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    Button(UIStrings.text("PDF-pagina \(source.page)")) { showSource(source.page, source.quote) }
                }
            } label: { Label(UIStrings.text("Bronnen"), systemImage: "doc.text.magnifyingglass").foregroundStyle(Color.primary) }
                .focusMenu()
        } else {
            HStack(spacing: 8) {
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    Button(UIStrings.text("Bron · PDF-pagina \(source.page)")) {
                        showSource(source.page, source.quote)
                    }.buttonStyle(FocusQuietActionStyle()).controlSize(.small)
                }
            }
        }
    }

    private var sourcePageEntries: [ChosenPassage.Source] {
        let byPage = Dictionary(passage.sources.map { ($0.page, $0) }, uniquingKeysWith: { first, _ in first })
        return passage.pages.map { byPage[$0] ?? ChosenPassage.Source(page: $0, quote: "") }
            + passage.sources.filter { !passage.pages.contains($0.page) }
    }
}

struct ChosenPassagesOverviewLink: View {
    let count: Int
    var openSelection: () -> Void

    var body: some View {
        if count > 0 {
            Button(action: openSelection) {
                Label("\(count) " + UIStrings.text("zelf gekozen passages in Mijn selectie"), systemImage: "text.quote")
                    .font(.caption.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }
}
