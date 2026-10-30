import SwiftUI

/// ChatGPT plan model preferences are separate from the API-key model preferences.
/// The catalog is supplied by the selected subscription account; this view never
/// inserts a guessed model when a saved choice is absent.
struct ChatGPTSubscriptionSettingsView: View {
    @ObservedObject private var account = ChatGPTSubscriptionAccount.shared
    @AppStorage(ChatGPTPlanPreferences.modeKey) private var routingMode = AIConfiguration.ChatGPTMode.single.rawValue
    @AppStorage(ChatGPTPlanPreferences.modelKey) private var model = ChatGPTPlanPreferences.defaultOrchestrator
    @AppStorage(ChatGPTPlanPreferences.effortKey) private var effort = ChatGPTPlanPreferences.defaultEffort
    @AppStorage(ChatGPTPlanPreferences.workerModelKey) private var workerModel = ChatGPTPlanPreferences.defaultWorker
    @AppStorage(ChatGPTPlanPreferences.workerEffortKey) private var workerEffort = ChatGPTPlanPreferences.defaultEffort

    private var usesOrchestrator: Bool { routingMode == AIConfiguration.ChatGPTMode.orchestrated.rawValue }
    private var selected: ChatGPTSubscriptionModel? { account.models.first { $0.id == model } }
    private var worker: ChatGPTSubscriptionModel? { account.models.first { $0.id == workerModel } }
    private var hasSelection: Bool {
        Self.isValidSelection(model: model, effort: effort, catalog: account.models) &&
        (!usesOrchestrator || Self.isValidSelection(model: workerModel, effort: workerEffort, catalog: account.models))
    }

    private var selectedAccountTitle: String {
        guard let id = account.selectedAccountID,
              let saved = account.savedAccounts.first(where: { $0.id == id }) else {
            return account.savedAccounts.isEmpty ? "No saved account" : "Choose an account"
        }
        return safeAccountLabel(saved)
    }

    private var accountSelection: Binding<String> {
        Binding(get: { account.selectedAccountID ?? "" }, set: { id in
            guard !id.isEmpty else { return }
            Task { await account.selectAccount(id: id) }
        })
    }

    private var mainModelSelection: Binding<String> {
        Binding(get: { model }, set: { value in
            guard value != model else { return }
            model = value
            if let chosen = account.models.first(where: { $0.id == value }) {
                effort = ChatGPTPreferences.normalizeEffortAfterExplicitModelChoice(current: effort, available: chosen.reasoningEfforts)
            }
        })
    }

    private var workerModelSelection: Binding<String> {
        Binding(get: { workerModel }, set: { value in
            guard value != workerModel else { return }
            workerModel = value
            if let chosen = account.models.first(where: { $0.id == value }) {
                workerEffort = ChatGPTPreferences.normalizeEffortAfterExplicitModelChoice(current: workerEffort, available: chosen.reasoningEfforts)
            }
        })
    }

    var body: some View {
        GroupBox("ChatGPT subscription") {
            VStack(alignment: .leading, spacing: 12) {
                Text(account.status).font(.callout)
                if let error = account.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                if !account.didRestoreSession, account.error != nil, !account.busy {
                    Button("Retry account restore") { Task { await account.restoreSessionIfNeeded(loadCatalog: true) } }
                }

                HStack {
                    FocusMenuPicker("ChatGPT account", selection: accountSelection, selectedTitle: selectedAccountTitle) {
                        if account.savedAccounts.isEmpty { Text("No saved account").tag("").disabled(true) }
                        ForEach(account.savedAccounts) { saved in Text(safeAccountLabel(saved)).tag(saved.id) }
                    }
                    .disabled(account.savedAccounts.isEmpty || account.busy)
                    if !account.busy && !account.savedAccounts.isEmpty {
                        Button("Add another ChatGPT account") { Task { await account.addAccount() } }
                    }
                }

                HStack {
                    if account.isConnected && !account.busy {
                        if account.needsPlanConsent {
                            Button("Enable ChatGPT plan usage") { Task { await account.enablePlanUsage() } }
                        }
                        Button("Sign out") { Task { await account.signOut() } }
                        Button("Refresh models") { Task { await account.refreshModels() } }
                    } else if account.busy {
                        ProgressView().controlSize(.small)
                        Text(account.status).font(.callout)
                        if account.status == "Connecting to ChatGPT…" {
                            Button("Cancel") { account.cancelSignIn() }
                        }
                    } else {
                        Button("Continue with ChatGPT") { Task { await account.signIn() } }
                            .buttonStyle(FocusPrimaryButtonStyle())
                    }
                }

                if account.isConnected && account.canUsePlan {
                    FocusMenuPicker("ChatGPT workflow", selection: $routingMode, selectedTitle: selectedWorkflowTitle) {
                        Text("One model for all ChatGPT tasks").tag(AIConfiguration.ChatGPTMode.single.rawValue)
                        Text("Orchestrator and agents").tag(AIConfiguration.ChatGPTMode.orchestrated.rawValue)
                    }

                    modelPicker(title: usesOrchestrator ? "Orchestrator model" : "ChatGPT model",
                                model: mainModelSelection, effort: $effort, selectedModel: selected)
                    if usesOrchestrator {
                        modelPicker(title: "Agent model", model: workerModelSelection,
                                    effort: $workerEffort, selectedModel: worker)
                        Text("Agents process source passages independently. The orchestrator prepares the document overview and coordinates reference checks. Foliance assigns these tasks automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("The selected model and reasoning effort are used for all ChatGPT tasks, including passages, reference checks and the document overview.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if !hasSelection {
                        Text("Choose a model and supported reasoning effort from the connected account’s current catalog before using this provider. Saved choices remain unchanged when they are unavailable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("This ChatGPT account’s catalog controls which models are available. The plan and its usage limits remain account-specific.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    if !model.isEmpty { Text("Saved ChatGPT model: \(model)").font(.caption).foregroundStyle(.secondary) }
                    if usesOrchestrator && !workerModel.isEmpty { Text("Saved agent model: \(workerModel)").font(.caption).foregroundStyle(.secondary) }
                    Text("Connect an eligible account and grant plan usage permission to load its model catalog. No model is chosen automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            await account.restoreSessionIfNeeded(loadCatalog: true)
        }
        .buttonStyle(FocusSecondaryButtonStyle())
    }

    private var selectedWorkflowTitle: String {
        usesOrchestrator ? "Orchestrator and agents" : "One model for all ChatGPT tasks"
    }

    @ViewBuilder private func modelPicker(title: String, model: Binding<String>, effort: Binding<String>, selectedModel: ChatGPTSubscriptionModel?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusMenuPicker(title, selection: model, selectedTitle: selectedModel?.displayName ?? (model.wrappedValue.isEmpty ? "Choose a model" : "\(model.wrappedValue) · unavailable")) {
                if selectedModel == nil {
                    Text(model.wrappedValue.isEmpty ? "Choose a model" : "\(model.wrappedValue) · unavailable")
                        .tag(model.wrappedValue).disabled(true)
                }
                ForEach(account.models) { item in Text(item.displayName).tag(item.id) }
            }
            if let selectedModel, !selectedModel.reasoningEfforts.isEmpty {
                let available = selectedModel.reasoningEfforts
                FocusMenuPicker("Reasoning effort", selection: effort,
                                selectedTitle: available.contains(effort.wrappedValue) ? effort.wrappedValue.capitalized : "\(effort.wrappedValue) · unavailable") {
                    if !available.contains(effort.wrappedValue) {
                        Text("\(effort.wrappedValue) · unavailable").tag(effort.wrappedValue).disabled(true)
                    }
                    ForEach(available, id: \.self) { value in Text(value.capitalized).tag(value) }
                }
            } else if selectedModel != nil {
                Text("This model uses its default reasoning setting.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !model.wrappedValue.isEmpty {
                Text("Saved selection is unavailable in the current account catalog.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static func isValidSelection(model: String, effort: String, catalog: [ChatGPTSubscriptionModel]) -> Bool {
        guard !model.isEmpty, let selected = catalog.first(where: { $0.id == model }) else { return false }
        return selected.reasoningEfforts.isEmpty ? effort == "auto" : selected.reasoningEfforts.contains(effort)
    }

    private func safeAccountLabel(_ account: ChatGPTSubscriptionSavedAccount) -> String {
        let identifier = String(account.id.suffix(8))
        guard let separator = account.email.firstIndex(of: "@") else { return "ChatGPT account · \(identifier)" }
        let local = account.email[..<separator]
        let domain = account.email[account.email.index(after: separator)...]
        return "\(local.first.map(String.init) ?? "•")•••@\(domain) · \(identifier)"
    }
}
