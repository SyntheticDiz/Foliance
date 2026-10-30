import SwiftUI

/// A zero-impact marker on controls shared with the tutorial. Its geometry lets the
/// tutorial pointer follow the real control even when the layout or font changes.
struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

extension View {
    func tutorialTarget(_ name: String) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [name: $0] }
    }
}
