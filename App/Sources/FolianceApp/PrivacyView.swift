import SwiftUI

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "Privacy", withExtension: "md"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            return "Your saved documents, analyses and notes remain on this Mac. Apple Intelligence runs on device. Optional OpenAI analysis requires your own API key and consent to send task content to OpenAI. There is no tracking or developer backend. You choose where exports and work documents are saved."
        }
        return value.replacingOccurrences(of: "# Foliance privacy policy\n\n", with: "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(UIStrings.text("Privacy"), systemImage: "hand.raised").font(.title2.bold())
                Spacer()
                Button(UIStrings.text("Gereed")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 20) {
                Link(UIStrings.text("Support"), destination: URL(string: "https://syntheticdiz.github.io/Foliance/support.html")!)
                Link(UIStrings.text("Public privacy policy"), destination: URL(string: "https://syntheticdiz.github.io/Foliance/privacy.html")!)
            }
            ScrollView { Text(policy).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(width: 620, height: 560)
    }
}
