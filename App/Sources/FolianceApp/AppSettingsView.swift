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

    private func checkApple() { appleStatus = AppleAIService.unavailability() ?? "Available · fully on this Mac" }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.largeTitle.bold())
            HStack {
                Text(UIStrings.text("Foliance · ") + PatchNotesView.version).foregroundStyle(.secondary)
                Spacer()
                Button("How Foliance works", systemImage: "questionmark.circle") { showingTutorial = true }
                Button("Patch notes", systemImage: "text.badge.star") { showingPatchNotes = true }
            }
            Button("Open-source licenses", systemImage: "doc.text") { showingLicenses = true }
                .font(.callout)
            Button(UIStrings.text("Privacy"), systemImage: "hand.raised") { showingPrivacy = true }
            Label(UIStrings.text("Apple Intelligence"), systemImage: "sparkles").font(.headline)
            GroupBox("On-device analysis") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text(appleStatus))
                    Button("Check availability") { checkApple() }
                    Text("Foliance uses Apple Intelligence on this Mac for analysis. A supported Apple Intelligence model must be available. Documents are processed in sections; source pages and full passages remain available for review.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            OpenAISettingsView()
            Divider()
            Label("Reference document", systemImage: "doc.text.magnifyingglass").font(.headline)
            PartyProgramSettings()
            Divider()
            Label("Appearance", systemImage: "circle.lefthalf.filled").font(.headline)
            FocusMenuPicker("Appearance", selection: $appearance,
                            selectedTitle: appearance == "light" ? "Light mode" : appearance == "dark" ? "Dark mode" : "System") {
                Text("System").tag("system")
                Text("Light mode").tag("light")
                Text("Dark mode").tag("dark")
            }
            Divider()
            Label(UIStrings.text("Export"), systemImage: "square.and.arrow.up").font(.headline)
            GroupBox("Default export folder") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(exportFolder.isEmpty ? "No default folder set" : exportFolder)
                        .font(.callout).lineLimit(3).truncationMode(.middle)
                    HStack {
                        Button("Choose folder…") { choosingFolder = true }
                        Button("Clear folder choice") { exportFolder = "" }.disabled(exportFolder.isEmpty)
                    }
                    Text("The export dialog opens in this folder. You can choose another location there.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if failed { Text(UIStrings.text(message)).foregroundStyle(.red) }
            HStack {
                Text("Your choices are saved automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
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
