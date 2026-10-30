import AppKit
import SwiftUI

@MainActor final class WorkspaceWindowCloseBridge: NSObject, ObservableObject, NSWindowDelegate {
    weak var workspace: SimpleWorkspace?
    weak var window: NSWindow?
    weak var previousDelegate: NSWindowDelegate?
    private var allowNextClose = false

    func install(on view: NSView) {
        guard let window = view.window else { return }
        if self.window === window, window.delegate === self { return }
        self.window = window
        previousDelegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowNextClose {
            allowNextClose = false
            return previousDelegate?.windowShouldClose?(sender) ?? true
        }
        if let workspace, workspace.document != nil, workspace.hasUnsavedChanges {
            NotificationCenter.default.post(name: .folianceRequestWindowClose, object: ObjectIdentifier(workspace))
            return false
        }
        return previousDelegate?.windowShouldClose?(sender) ?? true
    }

    func closeAfterAuthorization() {
        guard let window else { return }
        allowNextClose = true
        window.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let workspace {
            workspace.cancelAnalysis()
            workspace.stopTableAnalysis()
            workspace.closeOpenedWorkdocumentAccess()
            WorkspaceWindowRegistry.unregister(workspace)
        }
        previousDelegate?.windowWillClose?(notification)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (previousDelegate?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }
}

struct WorkspaceWindowCloseGuard: NSViewRepresentable {
    let bridge: WorkspaceWindowCloseBridge
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { bridge.install(on: view) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { bridge.install(on: view) }
    }
}
