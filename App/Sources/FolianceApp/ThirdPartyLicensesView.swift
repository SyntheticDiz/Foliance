import SwiftUI

enum ThirdPartyLicenses {
    static func bundledText(in bundle: Bundle = .main) -> String? {
        guard let folder = bundle.resourceURL?.appendingPathComponent("ThirdPartyLicenses", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        let notices = urls.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> String? in
                guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
                return url.deletingPathExtension().lastPathComponent + "\n\n" + text
            }
        return notices.isEmpty ? nil : notices.joined(separator: "\n\n————————————————————————\n\n")
    }
}

struct ThirdPartyLicensesView: View {
    @Environment(\.dismiss) private var dismiss
    private let text = ThirdPartyLicenses.bundledText()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(UIStrings.text("Opensourcelicenties")).font(.title2.bold())
                Spacer()
                Button(UIStrings.text("Gereed")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(text ?? UIStrings.text("De licentieteksten zijn niet beschikbaar in deze build."))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(minWidth: 540, idealWidth: 680, minHeight: 420, idealHeight: 640)
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
