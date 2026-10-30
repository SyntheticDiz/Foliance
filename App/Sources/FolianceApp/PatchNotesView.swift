import SwiftUI

struct PatchNotesView: View {
    @Environment(\.dismiss) private var dismiss
    static let version = "1.0.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UIStrings.text("Foliance 1.0.0")).font(.title2.bold())
                    Text(UIStrings.text("Release preparation · build 2")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(UIStrings.text("Gereed")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Divider()
            Text(UIStrings.text("Open en lees PDF’s, maak samenvattingen en bevindingen met bronverwijzingen, bewaar notities en gekozen passages, zoek lokaal en exporteer een controleerbare PDF."))
                .textSelection(.enabled)
            Text(UIStrings.text("Use on-device Apple Intelligence, your own OpenAI API key or an eligible ChatGPT plan. Cloud processing requires your explicit consent and a selected billing path. The interface and new explanations are English; source quotations stay unchanged. Check AI interpretations against the cited passages."))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 300)
        .background(SPTheme.background)
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
