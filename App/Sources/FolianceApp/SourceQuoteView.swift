import SwiftUI

/// A complete, selectable source quote with conservative paragraph reflow.
struct SourceQuoteView: View {
    let text: String
    var evidence: String? = nil

    var body: some View {
        let layout = SourceQuoteLayout.make(text: text, evidence: evidence)
        VStack(alignment: .leading, spacing: 12) {
            if layout.evidenceIsMarked {
                Text(UIStrings.text("Onderbouwend citaat gemarkeerd"))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            ForEach(Array(layout.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(attributedText(for: paragraph))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(layout.evidenceIsMarked
            ? UIStrings.text("Onderbouwend citaat gemarkeerd") + ". " + text
            : text)
    }

    private func attributedText(for paragraph: SourceQuoteLayout.Paragraph) -> AttributedString {
        var result = AttributedString()
        for segment in paragraph.segments {
            var part = AttributedString(segment.text)
            if segment.isEvidence {
                part.backgroundColor = Color.accentColor.opacity(0.16)
            }
            result.append(part)
        }
        return result
    }
}
