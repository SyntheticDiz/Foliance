import SwiftUI

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    let document: OpenPDF
    var initialSearch = ""
    var tutorialPreview = false
    let showPage: (Int) -> Void
    @State private var online: [String: OnlineGlossaryResult] = [:]
    @State private var entries: [GlossaryEntry] = []
    @State private var search = ""
    @State private var loading = true
    @State private var personal = PersonalGlossary()
    @State private var editing: GlossaryEntry?
    @State private var definition = ""
    @State private var everywhere = false
    @State private var error: String?
    private var documentKey: String { LocalCache.key(document.pages) }
    private func own(_ entry: GlossaryEntry) -> String? { personal.meaning(entry.abbreviation, document: documentKey) }
    private func web(_ entry: GlossaryEntry) -> OnlineGlossaryResult? {
        guard let result = online[Glossary.key(entry.abbreviation)], result.source == nil || result.source?.isWikipediaIntroduction == true else { return nil }
        return result
    }
    private func meaning(_ entry: GlossaryEntry) -> String {
        own(entry) ?? entry.definitions.first?.text ?? entry.reference?.meaning ??
            (web(entry)?.certain == true ? web(entry)?.fullName : nil) ?? UIStrings.text("Meaning not established")
    }
    private func label(_ entry: GlossaryEntry) -> String { own(entry) != nil ? "Your definition" : !entry.definitions.isEmpty ? "From document" : entry.reference != nil ? "Glossary reference" : web(entry)?.certain == true ? "Online reference" : web(entry) != nil ? "Unverified meaning" : "Unknown" }
    var filtered: [GlossaryEntry] {
        entries.filter { search.isEmpty || ([$0.abbreviation, meaning($0), $0.reference?.meaning ?? ""] + $0.definitions.map(\.text)).joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(UIStrings.text("Glossary")).font(.title2.bold())
                Spacer()
                Button(UIStrings.text("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(document.name).font(.caption).foregroundStyle(.secondary)
            Text(UIStrings.text("Meanings from this document take precedence over the general glossary. Your own definition is labelled as such.")).font(.callout).foregroundStyle(.secondary)
            TextField(UIStrings.text("Search abbreviation or meaning…"), text: $search).textFieldStyle(FocusInputFieldStyle())
            Text(UIStrings.text("Definitions come from this document or your personal glossary. Document content stays on this Mac.")).font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView(UIStrings.text("Collecting abbreviations…")) }
            else { Text("\(filtered.count) abbreviations").font(.caption) }
            if let error { Text(UIStrings.text(error)).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !loading && filtered.isEmpty { Text(UIStrings.text("No abbreviations found.")) }
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(entry.abbreviation).font(.title3.bold())
                                Spacer()
                                Text(UIStrings.text(label(entry))).font(.caption).foregroundStyle(.secondary)
                            }
                            // Meanings are source or user content, so preserve their original language.
                            Text(meaning(entry)).textSelection(.enabled)
                            if let result = web(entry), own(entry) == nil && entry.definitions.isEmpty && entry.reference == nil {
                                Text(result.explanation).textSelection(.enabled)
                                if !result.context.isEmpty { Text("In this document: " + result.context).foregroundStyle(.secondary).textSelection(.enabled) }
                                if let source = result.source { Link(UIStrings.text("Wikipedia article and author history") + " · " + source.title, destination: source.url).font(.callout) }
                                Text(UIStrings.text("Retrieved") + ": " + result.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))) + (result.fresh ? "" : " · " + UIStrings.text("older than 30 days"))).font(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup(UIStrings.text("Sources and other meanings")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(entry.definitions.enumerated()), id: \.offset) { _, value in
                                        Text("In document · PDF page \(value.page): " + value.text).textSelection(.enabled)
                                    }
                                    if let reference = entry.reference {
                                        Text(UIStrings.text("Reference glossary") + ": \(reference.meaning)")
                                        Text(reference.explanation).foregroundStyle(.secondary)
                                        Link(UIStrings.text("Official explanation"), destination: reference.url)
                                    }
                                    if let result = web(entry), let source = result.source {
                                        Text(UIStrings.text(source.displayKind)).font(.caption).foregroundStyle(.secondary)
                                        if !result.quote.isEmpty { Text(UIStrings.text("Source quote") + ": ‘" + result.quote + "’").textSelection(.enabled) }
                                        Link(UIStrings.text("Wikipedia text and adapted explanation: CC BY-SA 4.0"), destination: GlossaryWebSource.wikipediaLicenseURL)
                                        Text(UIStrings.text("The AI explanation is a modified paraphrase, not reviewed by Wikipedia. Review the linked article and its licensing notices. CC BY-SA 4.0 applies to the Wikipedia text and its adapted explanation; your original PDF and notes keep their own terms."))
                                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    if let first = entry.occurrences.first { Text(first.excerpt).font(.callout).textSelection(.enabled) }
                                    ForEach(entry.occurrences, id: \.page) { occurrence in
                                        Button("PDF page \(occurrence.page)") { showPage(occurrence.page); dismiss() }
                                    }
                                }.padding(.top, 8)
                            }
                            HStack {
                                Button(own(entry) == nil ? "Add a definition" : "Edit definition") {
                                    definition = own(entry) ?? ""; everywhere = personal.documents[documentKey]?[Glossary.key(entry.abbreviation)] == nil && personal.general[Glossary.key(entry.abbreviation)] != nil
                                    editing = entry
                                }
                                Spacer()
                                Link(UIStrings.text("Look up meaning online"), destination: entry.searchURL)
                            }.font(.callout)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            Text(UIStrings.text("‘Look up online’ opens a separate browser search for the abbreviation. Your PDF is not included.")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 700, height: 650)
        .task(id: documentKey) {
            if !initialSearch.isEmpty { search = initialSearch }
            loading = true
            if tutorialPreview {
                entries = Glossary.extract(pages: document.pages)
                loading = false
                return
            }
            do { online = try OnlineGlossaryStore.read(documentKey) } catch { self.error = UIStrings.text("Cached glossary references could not be loaded") + ": " + error.localizedDescription }
            do { personal = try PersonalGlossary.read() } catch { self.error = UIStrings.text("Personal glossary could not be loaded") + ": " + error.localizedDescription }
            let pages = document.pages
            let terms = Set(personal.general.keys).union(personal.documents[documentKey]?.keys.map { $0 } ?? [])
            entries = await Task.detached { Glossary.extract(pages: pages, personalTerms: terms) }.value
            loading = false
        }
        .sheet(item: $editing) { entry in
            VStack(alignment: .leading, spacing: 18) {
                Text("Meaning of \(entry.abbreviation)").font(.title2.bold())
                TextField(UIStrings.text("Personal definition"), text: $definition, axis: .vertical).lineLimit(3...6)
                Toggle(UIStrings.text("Save for all documents"), isOn: $everywhere)
                Text(UIStrings.text("Off: this document only. A document definition takes precedence over your general glossary.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(UIStrings.text("Cancel")) { editing = nil }.keyboardShortcut(.cancelAction)
                    Button(UIStrings.text("Remove personal definition"), role: .destructive) { save(entry, value: "") }
                    Spacer()
                    Button(UIStrings.text("Bewaren")) { save(entry, value: definition) }
                        .disabled(definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 520)
                .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        }
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }
    private func save(_ entry: GlossaryEntry, value: String) {
        var revised = personal
        revised.set(value, term: entry.abbreviation, document: documentKey, everywhere: everywhere)
        do { try revised.write(); personal = revised; editing = nil; error = nil }
        catch { self.error = UIStrings.text("Could not save") + ": " + error.localizedDescription; editing = nil }
    }
}
