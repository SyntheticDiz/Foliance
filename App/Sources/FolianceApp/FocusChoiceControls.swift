import SwiftUI

struct FocusChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let count: Int?

    init(value: Value, title: String, count: Int? = nil) {
        self.value = value
        self.title = title
        self.count = count
    }

    var id: Value { value }
}

/// Compact menu selection with a persistent field label and an explicit current value.
struct FocusMenuPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    let selectedTitle: String
    let content: () -> Content

    init(_ title: String, selection: Binding<Value>, selectedTitle: String,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._selection = selection
        self.selectedTitle = selectedTitle
        self.content = content
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection, content: content).pickerStyle(.menu)
        } label: {
            // AppKit-backed Menu may serialize only the first Text in an HStack.
            // One label keeps both the field name and current choice visible.
            Text(title + " · " + selectedTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .focusToolbarMenu()
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
        .help(title + ": " + selectedTitle)
    }
}

/// Quiet, full-width selection tabs that preserve button keyboard and VoiceOver behavior.
struct FocusChoiceTabs<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [FocusChoiceOption<Value>]
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focusedValue: Value?
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: String, selection: Binding<Value>, options: [FocusChoiceOption<Value>]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let selected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 5) {
                        Text(option.title).lineLimit(1).minimumScaleFactor(0.85)
                        if let count = option.count {
                            Text(count, format: .number)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(selected ? Color.primary.opacity(0.7) : Color.secondary)
                        }
                    }
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                }
                .buttonStyle(FocusChoiceTabButtonStyle(selected: selected))
                .focused($focusedValue, equals: option.value)
                .accessibilityLabel(option.title)
                .accessibilityValue(option.count.map { String($0) } ?? "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(SPTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(contrast == .increased ? Color.primary.opacity(0.62) : SPTheme.border.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onMoveCommand { direction in
            guard isEnabled, !options.isEmpty,
                  direction == .left || direction == .right,
                  let index = options.firstIndex(where: { $0.value == (focusedValue ?? selection) }) else { return }
            let next = min(options.count - 1, max(0, index + (direction == .right ? 1 : -1)))
            selection = options[next].value
            focusedValue = options[next].value
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct FocusInputFieldStyle: TextFieldStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorSchemeContrast) private var contrast

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(isEnabled ? SPTheme.surface : SPTheme.buttonDisabled,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused && isEnabled ? SPTheme.focusRing : contrast == .increased ? Color.primary.opacity(0.62) : SPTheme.border.opacity(0.7),
                                  lineWidth: isFocused && isEnabled ? (contrast == .increased ? 3 : 2) : 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct FocusChoiceTabButtonStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 8)
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(selected && isEnabled ? SPTheme.buttonSurface : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if isFocused && isEnabled {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(SPTheme.focusRing, lineWidth: contrast == .increased ? 3 : 2)
                        .allowsHitTesting(false)
                } else if selected || contrast == .increased {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(contrast == .increased ? Color.primary.opacity(0.55) : SPTheme.border.opacity(0.65), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed && isEnabled ? 0.78 : 1)
    }
}
