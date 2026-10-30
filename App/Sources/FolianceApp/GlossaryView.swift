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
        guard let result = online[Glossary.key(entry.abbreviation)], result.source == nil || result.source?.kind == "Wikipedia-introductie" else { return nil }
        return result
    }
    private func meaning(_ entry: GlossaryEntry) -> String {
        own(entry) ?? entry.definitions.first?.text ?? entry.reference?.meaning ??
            (web(entry)?.certain == true ? web(entry)?.fullName : nil) ?? UIStrings.text("Betekenis niet vastgesteld")
    }
    private func label(_ entry: GlossaryEntry) -> String { own(entry) != nil ? "Eigen definitie" : !entry.definitions.isEmpty ? "Uit document" : entry.reference != nil ? "Woordenlijst" : web(entry)?.certain == true ? "Online aangevuld" : web(entry) != nil ? "Betekenis onzeker" : "Onbekend" }
    var filtered: [GlossaryEntry] {
        entries.filter { search.isEmpty || ([$0.abbreviation, meaning($0), $0.reference?.meaning ?? ""] + $0.definitions.map(\.text)).joined(separator: " ").localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(UIStrings.text("Afkortingenlijst")).font(.title2.bold())
                Spacer()
                Button(UIStrings.text("Gereed")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(document.name).font(.caption).foregroundStyle(.secondary)
            Text(UIStrings.text("Betekenissen uit dit document hebben voorrang op de algemene woordenlijst. Je eigen definitie wordt als zodanig gemarkeerd.")).font(.callout).foregroundStyle(.secondary)
            TextField(UIStrings.text("Zoek afkorting of betekenis…"), text: $search).textFieldStyle(FocusInputFieldStyle())
            Text(UIStrings.text("Definities komen uit dit document of je eigen woordenlijst. Documentinhoud blijft op deze Mac.")).font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView(UIStrings.text("Afkortingen verzamelen…")) }
            else { Text(UIStrings.text("\(filtered.count) afkortingen")).font(.caption) }
            if let error { Text(UIStrings.text(error)).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !loading && filtered.isEmpty { Text(UIStrings.text("Geen afkortingen gevonden.")) }
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
                                if !result.context.isEmpty { Text(UIStrings.text("In dit document") + ": " + result.context).foregroundStyle(.secondary).textSelection(.enabled) }
                                if let source = result.source { Link(UIStrings.text("Bron bekijken") + " · " + source.title, destination: source.url).font(.callout) }
                                Text(UIStrings.text("Opgehaald") + ": " + result.date.formatted(date: .abbreviated, time: .omitted) + (result.fresh ? "" : " · " + UIStrings.text("ouder dan 30 dagen"))).font(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup(UIStrings.text("Bronnen en andere betekenissen")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(entry.definitions.enumerated()), id: \.offset) { _, value in
                                        Text(UIStrings.text("In document · PDF-pagina \(value.page)") + ": " + value.text).textSelection(.enabled)
                                    }
                                    if let reference = entry.reference {
                                        Text(UIStrings.text("Woordenlijst") + ": \(reference.meaning)")
                                        Text(reference.explanation).foregroundStyle(.secondary)
                                        Link(UIStrings.text("Officiële toelichting"), destination: reference.url)
                                    }
                                    if let result = web(entry), let source = result.source {
                                        Text(UIStrings.text(source.kind)).font(.caption).foregroundStyle(.secondary)
                                        if !result.quote.isEmpty { Text(UIStrings.text("Broncitaat") + ": ‘" + result.quote + "’").textSelection(.enabled) }
                                        Link(source.title, destination: source.url)
                                    }
                                    if let first = entry.occurrences.first { Text(first.excerpt).font(.callout).textSelection(.enabled) }
                                    ForEach(entry.occurrences, id: \.page) { occurrence in
                                        Button(UIStrings.text("PDF-pagina \(occurrence.page)")) { showPage(occurrence.page); dismiss() }
                                    }
                                }.padding(.top, 8)
                            }
                            HStack {
                                Button(UIStrings.text(own(entry) == nil ? "Betekenis toevoegen" : "Betekenis aanpassen")) {
                                    definition = own(entry) ?? ""; everywhere = personal.documents[documentKey]?[Glossary.key(entry.abbreviation)] == nil && personal.general[Glossary.key(entry.abbreviation)] != nil
                                    editing = entry
                                }
                                Spacer()
                                Link(UIStrings.text("Zoek online naar betekenis"), destination: entry.searchURL)
                            }.font(.callout)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            Text(UIStrings.text("‘Zoek online’ opent een aparte browserzoekopdracht voor de afkorting. Je PDF wordt niet meegestuurd.")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 700, height: 650)
        .task(id: documentKey) {
            if !initialSearch.isEmpty { search = initialSearch }
            loading = true
            if tutorialPreview {
                entries = Glossary.extract(pages: document.pages)
                loading = false
                return
            }
            do { online = try OnlineGlossaryStore.read(documentKey) } catch { self.error = UIStrings.text("Online aanvullingen konden niet worden geladen") + ": " + error.localizedDescription }
            do { personal = try PersonalGlossary.read() } catch { self.error = UIStrings.text("Eigen woordenlijst kon niet worden geladen") + ": " + error.localizedDescription }
            let pages = document.pages
            let terms = Set(personal.general.keys).union(personal.documents[documentKey]?.keys.map { $0 } ?? [])
            entries = await Task.detached { Glossary.extract(pages: pages, personalTerms: terms) }.value
            loading = false
        }
        .sheet(item: $editing) { entry in
            VStack(alignment: .leading, spacing: 18) {
                Text(UIStrings.text("Betekenis van \(entry.abbreviation)")).font(.title2.bold())
                TextField(UIStrings.text("Eigen definitie"), text: $definition, axis: .vertical).lineLimit(3...6)
                Toggle(UIStrings.text("Bewaren voor alle documenten"), isOn: $everywhere)
                Text(UIStrings.text("Uitgeschakeld: alleen dit document. Een documentdefinitie heeft voorrang op je algemene woordenlijst.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(UIStrings.text("Annuleren")) { editing = nil }.keyboardShortcut(.cancelAction)
                    Button(UIStrings.text("Eigen definitie verwijderen"), role: .destructive) { save(entry, value: "") }
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
        catch { self.error = UIStrings.text("Bewaren mislukt") + ": " + error.localizedDescription; editing = nil }
    }
}
