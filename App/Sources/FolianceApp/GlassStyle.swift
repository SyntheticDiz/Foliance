import SwiftUI

struct GlassSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(SPTheme.surface, in: RoundedRectangle(cornerRadius: SPTheme.cardRadius))
            .overlay { RoundedRectangle(cornerRadius: SPTheme.cardRadius).strokeBorder(contrast == .increased ? Color.primary.opacity(0.62) : SPTheme.border.opacity(0.55), lineWidth: contrast == .increased ? 1.5 : 1).allowsHitTesting(false) }
    }
}

/// Compatibility wrapper for older call sites. New call sites should choose a
/// semantic button role with `FocusPrimaryButtonStyle` or `FocusSecondaryButtonStyle`.
struct GlassActionStyle: ViewModifier {
    var prominent = false
    var size: ControlSize = .regular
    @ViewBuilder func body(content: Content) -> some View {
        if prominent { content.buttonStyle(FocusPrimaryButtonStyle()).controlSize(size) }
        else { content.buttonStyle(FocusSecondaryButtonStyle()).controlSize(size) }
    }
}

/// Deliberate calls to action use the single red brand color.
struct FocusPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonLabel(configuration: configuration, role: .primary,
                         enabled: isEnabled, reduceMotion: reduceMotion, controlSize: controlSize)
    }
}

/// The default explicit button role: neutral, lightly surfaced and easy to scan.
struct FocusSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonLabel(configuration: configuration, role: .secondary,
                         enabled: isEnabled, reduceMotion: reduceMotion, controlSize: controlSize)
    }
}

/// Text-first action for inline controls. It does not turn selection or disclosure
/// buttons into generic actions; those should keep their existing `.plain` style.
struct FocusQuietActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonLabel(configuration: configuration, role: .quiet,
                         enabled: isEnabled, reduceMotion: reduceMotion, controlSize: controlSize)
    }
}

/// Compact icon-and-title actions for the main window toolbar. Use a descriptive
/// accessibility label and `.help` at the call site when the visible title is hidden.
struct FocusToolbarIconActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonLabel(configuration: configuration, role: .toolbar,
                         enabled: isEnabled, reduceMotion: reduceMotion, controlSize: controlSize)
    }
}

/// Kept as a source-compatible name for existing toolbar buttons.
typealias FocusToolbarActionStyle = FocusToolbarIconActionStyle

private enum FocusButtonRole: Equatable {
    case primary
    case secondary
    case quiet
    case toolbar
}

private struct FocusButtonLabel: View {
    let configuration: ButtonStyle.Configuration
    let role: FocusButtonRole
    let enabled: Bool
    let reduceMotion: Bool
    let controlSize: ControlSize
    var sourceAction = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false

    private var isDestructive: Bool {
        if #available(macOS 12.0, *) { return configuration.role == .destructive }
        return false
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: role == .primary ? 9 : role == .toolbar ? 7 : 8)
    }

    private var foreground: Color {
        guard enabled else { return Color.secondary }
        if isDestructive && role != .primary { return .red }
        switch role {
        case .primary:
            return .white
        case .secondary, .quiet, .toolbar:
            return Color.primary.opacity(configuration.isPressed ? 0.68 : 0.9)
        }
    }

    private var background: Color {
        guard enabled else {
            return SPTheme.buttonDisabled
        }
        switch role {
        case .primary:
            return configuration.isPressed ? SPTheme.brandPressed : SPTheme.brand
        case .secondary:
            if isDestructive && (configuration.isPressed || isHovered) {
                return Color.red.opacity(contrast == .increased ? 0.2 : 0.1)
            }
            if configuration.isPressed { return SPTheme.buttonHover.opacity(0.8) }
            return isHovered || isFocused ? SPTheme.buttonHover : SPTheme.buttonSurface
        case .quiet:
            if isDestructive && (configuration.isPressed || isHovered) {
                return Color.red.opacity(contrast == .increased ? 0.2 : 0.1)
            }
            return configuration.isPressed ? SPTheme.buttonHover : isHovered ? SPTheme.buttonHover.opacity(0.65) : .clear
        case .toolbar:
            return configuration.isPressed ? SPTheme.buttonHover : isHovered || isFocused ? SPTheme.buttonHover : .clear
        }
    }

    private var horizontalPadding: CGFloat {
        let base: CGFloat
        switch role { case .primary, .secondary: base = 12; case .quiet: base = 7; case .toolbar: base = 7 }
        switch controlSize {
        case .mini: return max(4, base - 5)
        case .small: return max(5, base - 3)
        case .large: return base + 2
        default: return base
        }
    }

    private var verticalPadding: CGFloat {
        let base: CGFloat
        switch role { case .primary, .secondary: base = 7; case .quiet: base = 6; case .toolbar: base = 6 }
        switch controlSize {
        case .mini: return max(2, base - 3)
        case .small: return max(3, base - 2)
        case .large: return base + 2
        default: return base
        }
    }

    var body: some View {
        configuration.label
            .font(role == .toolbar ? .system(size: 12, weight: .medium) : .callout.weight(role == .primary || sourceAction ? .semibold : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .contentShape(shape)
            .background(background, in: shape)
            .overlay {
                if isFocused && enabled {
                    shape.strokeBorder(SPTheme.focusRing, lineWidth: contrast == .increased ? 3 : 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else if contrast == .increased && role == .secondary {
                    shape.strokeBorder(Color.primary.opacity(0.68), lineWidth: 1.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onHover { hovered in
                guard !reduceMotion else { isHovered = hovered; return }
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
            }
    }
}

/// Native menu labels do not inherit ButtonStyle. This modifier gives them the
/// same neutral foreground and hover/focus feedback as toolbar actions.
private struct FocusToolbarMenuSurface: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .menuStyle(.borderlessButton)
            .tint(Color.primary)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(isEnabled && (isHovered || isFocused) ? SPTheme.buttonHover : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if isFocused && isEnabled {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(SPTheme.focusRing, lineWidth: contrast == .increased ? 3 : 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else if contrast == .increased {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.68), lineWidth: 1.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onHover { hovered in
                guard !reduceMotion else { isHovered = hovered; return }
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
            }
    }
}

/// Regular menus use the shared secondary surface around their native label.
/// Only callers style the label subtree, so native menu item roles keep their
/// own system colors and semantics.
private struct FocusMenuSurface: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize
    @State private var isHovered = false

    private var horizontalPadding: CGFloat {
        switch controlSize { case .mini: return 5; case .small: return 8; case .large: return 14; default: return 11 }
    }

    private var verticalPadding: CGFloat {
        switch controlSize { case .mini: return 3; case .small: return 5; case .large: return 9; default: return 7 }
    }

    func body(content: Content) -> some View {
        content
            .menuStyle(.borderlessButton)
            .tint(Color.primary)
            .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(!isEnabled ? SPTheme.buttonDisabled : isHovered || isFocused ? SPTheme.buttonHover : SPTheme.buttonSurface,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if isFocused && isEnabled {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(SPTheme.focusRing, lineWidth: contrast == .increased ? 3 : 2)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else if contrast == .increased {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.68), lineWidth: 1.5)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onHover { hovered in
                guard !reduceMotion else { isHovered = hovered; return }
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
            }
    }
}

extension View {
    func focusToolbarMenu() -> some View { modifier(FocusToolbarMenuSurface()) }
    func focusMenu() -> some View { modifier(FocusMenuSurface()) }
}

/// Existing quiet actions retain one shared implementation for focus, disabled,
/// hover and pressed states. Source actions no longer consume the red accent color.
struct QuietActionStyle: ButtonStyle {
    var sourceAction = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        FocusButtonLabel(configuration: configuration, role: .quiet,
                         enabled: isEnabled, reduceMotion: reduceMotion, controlSize: controlSize, sourceAction: sourceAction)
    }
}
