import SwiftUI

struct RecentWorkspacesList: View {
    let entries: [RecentWorkspaceDocuments.Entry]
    var disabled = false
    let open: (RecentWorkspaceDocuments.Entry) -> Void
    var removeFromList: ((RecentWorkspaceDocuments.Entry) -> Void)? = nil
    var relocate: ((RecentWorkspaceDocuments.Entry) -> Void)? = nil
    var statusMessage: ((RecentWorkspaceDocuments.Entry) -> String?)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIStrings.text("Recente werkdocumenten")).font(.subheadline.weight(.semibold))
            ForEach(entries) { entry in
                Button { open(entry) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName).lineLimit(1).truncationMode(.middle)
                            Text((entry.path as NSString).deletingLastPathComponent)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            if let status = status(for: entry) {
                                Text(status).font(.caption2).foregroundStyle(.orange).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.path)
                .accessibilityLabel(UIStrings.text("Werkdocument openen") + ": " + entry.displayName)
                .disabled(disabled)
                .contextMenu {
                    if let relocate {
                        Button(UIStrings.text("Verplaats of herstel…"), systemImage: "folder") { relocate(entry) }.disabled(disabled)
                    }
                    if let removeFromList {
                        Button(UIStrings.text("Verwijder uit lijst"), systemImage: "minus.circle", role: .destructive) { removeFromList(entry) }.disabled(disabled)
                    }
                }
            }
            Text(UIStrings.text("Opent de bewaarde resultaten zonder nieuwe AI-analyse."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: 440, alignment: .leading).padding(14)
            .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func status(for entry: RecentWorkspaceDocuments.Entry) -> String? {
        if let statusMessage { return statusMessage(entry) }
        return RecentWorkspaceDocuments.shared.statusMessage(for: entry)
    }
}
