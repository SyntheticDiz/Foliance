import SwiftUI
import AppKit

enum SPTheme {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let background = adaptive(.init(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), .init(red: 0.09, green: 0.11, blue: 0.14, alpha: 1))
    static let surface = adaptive(.init(white: 1, alpha: 1), .init(red: 0.15, green: 0.18, blue: 0.22, alpha: 1))
    static let border = adaptive(.init(red: 0.84, green: 0.86, blue: 0.89, alpha: 1), .init(red: 0.25, green: 0.29, blue: 0.34, alpha: 1))
    static let selection = adaptive(.init(red: 0.98, green: 0.94, blue: 0.95, alpha: 1), .init(red: 0.23, green: 0.15, blue: 0.18, alpha: 1))
    static let accent = adaptive(.init(red: 0.67, green: 0.12, blue: 0.20, alpha: 1), .init(red: 0.96, green: 0.57, blue: 0.62, alpha: 1))
    static let brand = adaptive(.init(red: 0.68, green: 0.14, blue: 0.21, alpha: 1), .init(red: 0.71, green: 0.17, blue: 0.25, alpha: 1))
    static let brandPressed = adaptive(.init(red: 0.52, green: 0.10, blue: 0.16, alpha: 1), .init(red: 0.57, green: 0.12, blue: 0.19, alpha: 1))
    static let buttonSurface = adaptive(.init(white: 1, alpha: 1), .init(red: 0.19, green: 0.22, blue: 0.27, alpha: 1))
    static let buttonHover = adaptive(.init(red: 0.88, green: 0.90, blue: 0.93, alpha: 1), .init(red: 0.27, green: 0.31, blue: 0.37, alpha: 1))
    static let buttonDisabled = adaptive(.init(red: 0.92, green: 0.93, blue: 0.95, alpha: 1), .init(red: 0.13, green: 0.15, blue: 0.18, alpha: 1))
    static let focusRing = adaptive(.init(red: 0.10, green: 0.35, blue: 0.72, alpha: 1), .init(red: 0.42, green: 0.67, blue: 1, alpha: 1))
    static let cardRadius: CGFloat = 18
}

struct SPWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("F").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(SPTheme.brand, in: RoundedRectangle(cornerRadius: 5))
            Text("Foliance").font(.headline)
        }.accessibilityElement(children: .combine)
    }
}

/// Shared reading surface; system contrast preferences retain a visible outline.
private struct ReadingSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(SPTheme.surface, in: RoundedRectangle(cornerRadius: SPTheme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: SPTheme.cardRadius)
                .strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : SPTheme.border.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false).accessibilityHidden(true) }
            .shadow(color: .black.opacity(contrast == .increased ? 0 : 0.045), radius: 7, x: 0, y: 2)
    }
}
extension View {
    func readingSurface() -> some View { modifier(ReadingSurface()) }
}
