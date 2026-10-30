import SwiftUI
import AppKit

extension Notification.Name {
    static let folianceOpenPDF = Notification.Name("FolianceOpenPDF")
    static let folianceFind = Notification.Name("FolianceFind")
    static let folianceRequestTermination = Notification.Name("FolianceRequestTermination")
    static let folianceRequestWindowClose = Notification.Name("FolianceRequestWindowClose")
}

@MainActor enum WorkspaceWindowRegistry {
    private final class WeakWorkspace {
        weak var value: SimpleWorkspace?
        init(_ value: SimpleWorkspace) { self.value = value }
    }
    private static var workspaces: [ObjectIdentifier: WeakWorkspace] = [:]
    private static var authorizedTerminationRevisions: [ObjectIdentifier: UUID] = [:]
    static func register(_ workspace: SimpleWorkspace) { workspaces[ObjectIdentifier(workspace)] = WeakWorkspace(workspace) }
    static func unregister(_ workspace: SimpleWorkspace) {
        let id = ObjectIdentifier(workspace)
        workspaces.removeValue(forKey: id)
        authorizedTerminationRevisions.removeValue(forKey: id)
    }
    static var hasUnsavedChanges: Bool {
        workspaces = workspaces.filter { $0.value.value != nil }
        return workspaces.contains { id, item in
            guard let workspace = item.value, workspace.document != nil, workspace.hasUnsavedChanges else { return false }
            return authorizedTerminationRevisions[id] != workspace.revisionToken
        }
    }
    static func requestNextDirtyWorkspace() -> Bool {
        workspaces = workspaces.filter { $0.value.value != nil }
        guard let match = workspaces.first(where: { id, item in
            guard let workspace = item.value, workspace.document != nil, workspace.hasUnsavedChanges else { return false }
            return authorizedTerminationRevisions[id] != workspace.revisionToken
        }), let workspace = match.value.value else { return false }
        NotificationCenter.default.post(name: .folianceRequestTermination, object: ObjectIdentifier(workspace))
        return true
    }
    static func autosaveOpenedWorkdocuments() async -> [String] {
        workspaces = workspaces.filter { $0.value.value != nil }
        let eligible = workspaces.values.compactMap(\.value).filter {
            $0.document != nil && $0.hasUnsavedChanges && $0.isOpenedWorkdocument
        }
        var failures: [String] = []
        for workspace in eligible {
            do { try await workspace.autosaveOpenedWorkdocument() }
            catch {
                let name = workspace.openedWorkdocumentURL?.lastPathComponent ?? "Werkdocument"
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return failures
    }
    static func authorizeTerminationRevision(for workspace: SimpleWorkspace) {
        authorizedTerminationRevisions[ObjectIdentifier(workspace)] = workspace.revisionToken
    }
    static func cancelTerminationSequence() { authorizedTerminationRevisions.removeAll() }
}

@MainActor final class SavedWorkTerminationCoordinator {
    private(set) var isWaitingForDrain = false

    func begin(
        drain: @escaping () async -> [String],
        autosaveOpenedWorkdocuments: @escaping () async -> [String] = { [] },
        hasUnsavedChanges: @escaping () -> Bool,
        requestNextDirtyWorkspace: @escaping () -> Void,
        presentSaveFailures: @escaping ([String]) -> Void,
        reply: @escaping (Bool) -> Void
    ) -> NSApplication.TerminateReply {
        guard !isWaitingForDrain else { return .terminateLater }
        isWaitingForDrain = true
        Task { @MainActor in
            var failures: [String] = []
            while true {
                while true {
                    let generation = SavedWork.scheduledGeneration
                    failures.append(contentsOf: await drain())
                    if SavedWork.scheduledGeneration == generation { break }
                }
                guard failures.isEmpty else { break }
                let generationBeforeAutosave = SavedWork.scheduledGeneration
                let autosaveFailures = await autosaveOpenedWorkdocuments()
                failures.append(contentsOf: autosaveFailures)
                guard autosaveFailures.isEmpty,
                      SavedWork.scheduledGeneration != generationBeforeAutosave else { break }
            }
            guard failures.isEmpty else {
                presentSaveFailures(failures)
                isWaitingForDrain = false
                reply(false)
                return
            }
            guard !hasUnsavedChanges() else {
                requestNextDirtyWorkspace()
                isWaitingForDrain = false
                reply(false)
                return
            }
            isWaitingForDrain = false
            reply(true)
        }
        return .terminateLater
    }
}

@MainActor final class FolianceAppDelegate: NSObject, NSApplicationDelegate {
    private let terminationCoordinator: SavedWorkTerminationCoordinator
    private let replyToTermination: (NSApplication, Bool) -> Void
    private let presentTerminationFailures: ([String]) -> Void

    override init() {
        terminationCoordinator = SavedWorkTerminationCoordinator()
        replyToTermination = { application, shouldTerminate in
            if shouldTerminate { WorkspaceWindowRegistry.cancelTerminationSequence() }
            application.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        presentTerminationFailures = { failures in
            let alert = NSAlert()
            alert.messageText = "Unsaved changes"
            alert.informativeText = failures.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: UIStrings.text("OK"))
            alert.runModal()
        }
        super.init()
    }

    init(
        terminationCoordinator: SavedWorkTerminationCoordinator,
        replyToTermination: @escaping (NSApplication, Bool) -> Void,
        presentTerminationFailures: @escaping ([String]) -> Void
    ) {
        self.terminationCoordinator = terminationCoordinator
        self.replyToTermination = replyToTermination
        self.presentTerminationFailures = presentTerminationFailures
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationCoordinator.isWaitingForDrain { return .terminateLater }
        return terminationCoordinator.begin(
            drain: { await SavedWork.drain() },
            autosaveOpenedWorkdocuments: { await WorkspaceWindowRegistry.autosaveOpenedWorkdocuments() },
            hasUnsavedChanges: { WorkspaceWindowRegistry.hasUnsavedChanges },
            requestNextDirtyWorkspace: { _ = WorkspaceWindowRegistry.requestNextDirtyWorkspace() },
            presentSaveFailures: presentTerminationFailures,
            reply: { shouldTerminate in self.replyToTermination(sender, shouldTerminate) }
        )
    }
}

@main
struct FolianceApp: App {
    @NSApplicationDelegateAdaptor(FolianceAppDelegate.self) private var appDelegate
    private var screenshotCaptureEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FolianceScreenshotCapture") as? Bool == true
    }
    @ViewBuilder
    private var mainReaderContent: some View {
        let reader = SimpleView().frame(minWidth: 900, minHeight: 620).tint(SPTheme.accent)
            .environment(\.locale, Locale(identifier: "en_US"))
            .buttonStyle(FocusSecondaryButtonStyle())
            .disclosureGroupStyle(FullRowDisclosureGroupStyle())
        if screenshotCaptureEnabled {
            reader.background(AppStoreCaptureWindow().frame(width: 0, height: 0)
                .allowsHitTesting(false).accessibilityHidden(true))
        } else {
            reader
        }
    }
    init() {
        ForkSetup.migrate()
        AppleAISettings.migrate()
    }
    var body: some Scene {
        WindowGroup("Foliance") {
            mainReaderContent
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }.windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open PDF…") { NotificationCenter.default.post(name: .folianceOpenPDF, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            WorkspaceFileCommands()
            CommandGroup(after: .textEditing) {
                Button("Search document") { NotificationCenter.default.post(name: .folianceFind, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

struct WorkspaceFileMenuActions {
    let canOpen: Bool
    let canSave: Bool
    let open: () -> Void
    let save: () -> Void
}

private struct WorkspaceFileMenuActionsKey: FocusedValueKey {
    typealias Value = WorkspaceFileMenuActions
}

extension FocusedValues {
    var folianceWorkspaceFileMenuActions: WorkspaceFileMenuActions? {
        get { self[WorkspaceFileMenuActionsKey.self] }
        set { self[WorkspaceFileMenuActionsKey.self] = newValue }
    }
}

private struct WorkspaceFileCommands: Commands {
    @FocusedValue(\.folianceWorkspaceFileMenuActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if let actions {
                Button("Open workspace…") { actions.open() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(!actions.canOpen)
                Button("Save workspace…") { actions.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!actions.canSave)
            }
        }
    }
}
