import SwiftUI

struct PatchNotesView: View {
    @Environment(\.dismiss) private var dismiss
    static let version = "1.0.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foliance 1.0.0").font(.title2.bold())
                    Text("Saved ChatGPT sessions · build 4").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Divider()
            Text("Open and read PDFs, create summaries and source-linked findings, save notes and selected passages, search locally, and export a reviewable PDF.")
                .textSelection(.enabled)
            Text(UIStrings.text("Use on-device Apple Intelligence, your own OpenAI API key or an eligible ChatGPT plan. Cloud processing requires your explicit consent and a selected billing path. The interface and new explanations are English; source quotations stay unchanged. Check AI interpretations against the cited passages. The app uses one consistent icon in Finder and the Dock. ChatGPT sign-in is securely restored on launch, and eligible sessions renew without opening the browser again. OpenAI may still require you to reconnect after expiry or revocation."))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 300)
        .background(SPTheme.background)
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
