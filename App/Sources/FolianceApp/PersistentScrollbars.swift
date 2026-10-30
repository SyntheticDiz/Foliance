import SwiftUI
import AppKit

/// Native scrolling and accessibility, with capsule-shaped track and thumb.
final class RoundedScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }

    private func capsule(_ rect: NSRect, inset: CGFloat) -> NSBezierPath {
        let area = rect.insetBy(dx: inset, dy: 2)
        return NSBezierPath(roundedRect: area, xRadius: area.width / 2, yRadius: area.width / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: bounds, highlight: false)
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        capsule(bounds, inset: 2).fill()
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        NSColor.secondaryLabelColor.setFill()
        capsule(knob, inset: 3).fill()
    }
}

/// Keep a native, accessible scrollbar visible without changing macOS preferences.
enum PersistentScrollbars {
    static func apply(to scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        if !(scrollView.verticalScroller is RoundedScroller) {
            scrollView.verticalScroller = RoundedScroller()
        }
        scrollView.verticalScroller?.controlSize = .small
    }
}

struct PersistentScrollbarsAttachment: NSViewRepresentable {
    final class Attachment: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }
        func install() {
            if let scrollView = enclosingScrollView { PersistentScrollbars.apply(to: scrollView) }
        }
    }
    func makeNSView(context: Context) -> Attachment { Attachment() }
    func updateNSView(_ view: Attachment, context: Context) {
        DispatchQueue.main.async { view.install() }
    }
}
