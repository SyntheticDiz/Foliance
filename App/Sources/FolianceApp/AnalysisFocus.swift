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
            Text("Reading goal").font(.title2.bold())
            Text("What do you want to learn from this document? Add topics or questions such as costs, dependencies, and commitments. A reference document is optional.").foregroundStyle(.secondary)
            TextEditor(text: $topics).font(.body).frame(height: 160).padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Additional reading goals")
            Toggle("Save for future documents and app launches", isOn: $saveForLater)
            Text("\(topics.utf8.count) / 1000 bytes").font(.caption)
            HStack {
                Button("Clear saved reading goals", role: .destructive) { savedFocus = ""; topics = "" }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if saveForLater { savedFocus = topics }
                    apply(.init(topics: topics)); dismiss()
                }.disabled(topics.utf8.count > 1000).buttonStyle(FocusPrimaryButtonStyle())
            }
        }.padding(24).frame(width: 570)
        .onAppear { topics = initial }
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
