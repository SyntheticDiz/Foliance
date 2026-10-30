import SwiftUI

/// Shows complete text when it fits and a soft, clipped preview when it does not.
/// Measurement uses the same font, spacing, and current width as the visible text.
struct FadingPreviewText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary
    var lineSpacing: CGFloat = 0
    var collapsedLines: Int = 4
    var showsExpansionControl = true
    var language = "en"
    var isExpanded: Binding<Bool>? = nil
    var onTextTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localExpanded = false
    @State private var measuredHeights: [Int: CGFloat] = [:]

    private var expanded: Bool { isExpanded?.wrappedValue ?? localExpanded }
    private var moreLabel: String { "Read more" }
    private var lessLabel: String { "Read less" }
    private var fullHeight: CGFloat? { measuredHeights[0] }
    private var previewHeight: CGFloat? { measuredHeights[1] }
    private var overflows: Bool {
        guard let fullHeight, let previewHeight else { return false }
        return fullHeight > previewHeight + 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            previewContent
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsExpansionControl && overflows {
                Button(expanded ? lessLabel : moreLabel) {
                    setExpanded(!expanded)
                }
                .buttonStyle(FocusQuietActionStyle())
                .controlSize(.small)
                .accessibilityHint(expanded ? "Shows the short preview again" : "Shows the full text")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    measuredText(lineLimit: nil, id: 0)
                    measuredText(lineLimit: max(1, collapsedLines), id: 1)
                }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geometry.size.width, height: 0, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onPreferenceChange(FadingPreviewHeightKey.self) { newHeights in
            guard measuredHeights != newHeights else { return }
            measuredHeights = newHeights
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var previewContent: some View {
        if expanded {
            styledText(lineLimit: nil).fixedSize(horizontal: false, vertical: true)
        } else {
            let preview = collapsedPreview
            if overflows {
                let faded = preview.mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: collapsedLines == 1 ? 0.3 : 0.78),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                if showsExpansionControl {
                    textActionButton(faded, expanded: false)
                } else {
                    faded
                }
            } else {
                preview
            }
        }
    }

    private var collapsedPreview: some View {
        styledText(lineLimit: max(1, collapsedLines))
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay(alignment: .topLeading) {
                styledText(lineLimit: nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(text)
                    .accessibilityValue("Collapsed")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private func textActionButton<Label: View>(_ label: Label, expanded: Bool) -> some View {
        Button {
            onTextTap?()
            setExpanded(!expanded)
        } label: {
            label.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).textSelection(.disabled)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint(expanded
                           ? "Shows the short preview again"
                           : "Shows the full text")
    }

    @ViewBuilder private func styledText(lineLimit: Int?) -> some View {
        let content = Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
        if showsExpansionControl && expanded { content.textSelection(.enabled) }
        else { content.textSelection(.disabled) }
    }

    private func measuredText(lineLimit: Int?, id: Int) -> some View {
        styledText(lineLimit: lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: FadingPreviewHeightKey.self, value: [id: proxy.size.height])
                }
            }
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            if let isExpanded { isExpanded.wrappedValue = value }
            else { localExpanded = value }
        }
    }
}

private struct FadingPreviewHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
