import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingPatchNotes = false
    @State private var showingTutorial = false
    @State private var showingLicenses = false
    @State private var showingPrivacy = false
    @State private var message = ""
    @State private var failed = false
    @State private var choosingFolder = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("exportFolder") private var exportFolder = ""

    @State private var appleStatus = ""

    private func checkApple() { appleStatus = AppleAIService.unavailability() ?? UIStrings.text("Beschikbaar · volledig op deze Mac") }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text(UIStrings.text("Instellingen")).font(.largeTitle.bold())
            HStack {
                Text(UIStrings.text("Foliance · ") + PatchNotesView.version).foregroundStyle(.secondary)
                Spacer()
                Button(UIStrings.text("Zo werkt Foliance"), systemImage: "questionmark.circle") { showingTutorial = true }
                Button(UIStrings.text("Versiegeschiedenis"), systemImage: "text.badge.star") { showingPatchNotes = true }
            }
            Button(UIStrings.text("Opensourcelicenties"), systemImage: "doc.text") { showingLicenses = true }
                .font(.callout)
            Button(UIStrings.text("Privacy"), systemImage: "hand.raised") { showingPrivacy = true }
            Label(UIStrings.text("Apple Intelligence"), systemImage: "sparkles").font(.headline)
            GroupBox(UIStrings.text("On-device analysis")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text(appleStatus))
                    Button(UIStrings.text("Controleer beschikbaarheid")) { checkApple() }
                    Text(UIStrings.text("Foliance gebruikt Apple Intelligence lokaal voor analyse. Op deze Mac moet een ondersteund Apple Intelligence-model beschikbaar zijn. Documenten worden in delen verwerkt; bronpagina’s en volledige passages blijven beschikbaar om te controleren."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            OpenAISettingsView()
            Divider()
            Label(UIStrings.text("Referentiedocument"), systemImage: "doc.text.magnifyingglass").font(.headline)
            PartyProgramSettings()
            Divider()
            Label(UIStrings.text("Weergave"), systemImage: "circle.lefthalf.filled").font(.headline)
            FocusMenuPicker(UIStrings.text("Weergave"), selection: $appearance,
                            selectedTitle: UIStrings.text(appearance == "light" ? "Lichte modus" : appearance == "dark" ? "Donkere modus" : "Systeeminstelling")) {
                Text(UIStrings.text("Systeeminstelling")).tag("system")
                Text(UIStrings.text("Lichte modus")).tag("light")
                Text(UIStrings.text("Donkere modus")).tag("dark")
            }
            Divider()
            Label(UIStrings.text("Export"), systemImage: "square.and.arrow.up").font(.headline)
            GroupBox(UIStrings.text("Standaardmap voor exports")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text(exportFolder.isEmpty ? "Geen vaste map ingesteld" : exportFolder))
                        .font(.callout).lineLimit(3).truncationMode(.middle)
                    HStack {
                        Button(UIStrings.text("Kies map…")) { choosingFolder = true }
                        Button(UIStrings.text("Wis mapkeuze")) { exportFolder = "" }.disabled(exportFolder.isEmpty)
                    }
                    Text(UIStrings.text("Het exportvenster opent in deze map. Je kunt daar nog een andere locatie kiezen."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if failed { Text(UIStrings.text(message)).foregroundStyle(.red) }
            HStack {
                Text(UIStrings.text("Keuzes worden automatisch bewaard."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(UIStrings.text("Gereed")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        }.frame(minWidth: 540, idealWidth: 600, minHeight: 500, idealHeight: 720)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .sheet(isPresented: $showingPatchNotes) { PatchNotesView() }
        .sheet(isPresented: $showingTutorial) { TutorialView() }
        .sheet(isPresented: $showingLicenses) { ThirdPartyLicensesView() }
        .sheet(isPresented: $showingPrivacy) { PrivacyView() }
        .task { checkApple() }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            let choice = ExportFolderChoice.applying(result, currentPath: exportFolder)
            exportFolder = choice.path
            message = choice.message ?? ""
            failed = choice.message != nil
        }
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
