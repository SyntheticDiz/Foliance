import SwiftUI
import FolianceCore

struct AnalysisFocus {
    let topics: String
    var keywords: String = ""
    var exclusive: Bool = false
    var terms: [String] { [] }
    var prompt: String { topics.trimmingCharacters(in: .whitespacesAndNewlines) }
    var themes: [Theme] { [] }
}

struct FocusEditor: View {
    private let uiLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    @AppStorage("savedProgramFocus") private var savedFocus = ""
    @State private var topics = ""
    @State private var saveForLater = false
    var initial: String
    let apply: (AnalysisFocus) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UIStrings.text("Leesdoel")).font(.title2.bold())
            Text(UIStrings.text("Wat wil je uit dit document halen? Geef onderwerpen of vragen mee, zoals kosten, afhankelijkheden en toezeggingen. Een referentiedocument is optioneel.")).foregroundStyle(.secondary)
            TextEditor(text: $topics).font(.body).frame(height: 160).padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(UIStrings.text("Aanvullende aandachtspunten"))
            Toggle(UIStrings.text("Bewaar voor volgende documenten en appstarts"), isOn: $saveForLater)
            Text("\(topics.utf8.count) / 1000 bytes").font(.caption)
            HStack {
                Button(UIStrings.text("Wis bewaarde aandachtspunten"), role: .destructive) { savedFocus = ""; topics = "" }
                Spacer()
                Button(UIStrings.text("Annuleer")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(UIStrings.text("Toepassen")) {
                    if saveForLater { savedFocus = topics }
                    apply(.init(topics: topics)); dismiss()
                }.disabled(topics.utf8.count > 1000).buttonStyle(FocusPrimaryButtonStyle())
            }
        }.padding(24).frame(width: 570)
        .onAppear { topics = initial }
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
