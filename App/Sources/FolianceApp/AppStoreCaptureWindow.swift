import AppKit
import SwiftUI

struct AppStoreCaptureWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> CaptureSizingView { CaptureSizingView() }

    func updateNSView(_ nsView: CaptureSizingView, context: Context) {
        nsView.scheduleWindowSizing()
    }

    final class CaptureSizingView: NSView {
        private var sizingScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleWindowSizing()
        }

        func scheduleWindowSizing() {
            guard window != nil, !sizingScheduled else { return }
            sizingScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window else {
                    self?.sizingScheduled = false
                    return
                }
                var frame = window.frame
                frame.size = NSSize(width: 1280, height: 800)
                window.setFrame(frame, display: true, animate: false)
            }
        }
    }
}
