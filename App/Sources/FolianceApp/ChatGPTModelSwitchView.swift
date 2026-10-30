import SwiftUI

struct ChatGPTModelSwitchView: View {
    @ObservedObject var workspace: SimpleWorkspace
    @ObservedObject private var planAccount = ChatGPTSubscriptionAccount.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OpenAIConsent.defaultsKey) private var consentVersion = 0
    @State private var choice: ChatGPTModelChoice
    @State private var apiModelID: String
    @State private var apiEffort: String
    @State private var message = ""
    private let usesPlan: Bool

    private var planCatalog: [ChatGPTModel] {
        planAccount.models.map { ChatGPTModel(id: $0.id, displayName: $0.displayName, reasoningEfforts: $0.reasoningEfforts) }
    }
    private var selectedMain: ChatGPTModel? { planCatalog.first { $0.id == choice.orchestratorModel } }
    private var selectedWorker: ChatGPTModel? { planCatalog.first { $0.id == choice.workerModel } }
    private var canApplyPlanChoice: Bool {
        planAccount.isConnected && planAccount.canUsePlan && consentVersion == OpenAIConsent.version &&
        !planAccount.busy && choice.encoded(using: planCatalog) != nil
    }

    init(workspace: SimpleWorkspace) {
        self.workspace = workspace
        let active = workspace.activeModel
        let plan = AIConfiguration.usesChatGPTPlan(active)
        usesPlan = plan
        _choice = State(initialValue: Self.makeChoice(active, plan: plan))
        let current = AIConfiguration.chatGPTSelection(AIConfiguration.orchestratorModel(active))
        _apiModelID = State(initialValue: current?.model ?? ChatGPTPreferences.defaultOrchestrator)
        _apiEffort = State(initialValue: current?.effort ?? "auto")
    }

    private var mainModelSelection: Binding<String> {
        Binding(get: { choice.orchestratorModel }, set: { value in
            guard value != choice.orchestratorModel else { return }
            choice.orchestratorModel = value
            if let model = planCatalog.first(where: { $0.id == value }) {
                choice.orchestratorEffort = ChatGPTPreferences.normalizeEffortAfterExplicitModelChoice(
                    current: choice.orchestratorEffort, available: model.reasoningEfforts)
            }
        })
    }

    private var workerModelSelection: Binding<String> {
        Binding(get: { choice.workerModel }, set: { value in
            guard value != choice.workerModel else { return }
            choice.workerModel = value
            if let model = planCatalog.first(where: { $0.id == value }) {
                choice.workerEffort = ChatGPTPreferences.normalizeEffortAfterExplicitModelChoice(
                    current: choice.workerEffort, available: model.reasoningEfforts)
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(usesPlan ? "Switch ChatGPT plan models" : "Switch OpenAI API model")
                .font(.title2.weight(.semibold))
            Text(usesPlan
                 ? "Choose models and reasoning options from the selected account’s catalog. The current ChatGPT plan remains the billing source."
                 : "Enter the exact model ID available to your API key. Foliance does not guess model availability.")
                .font(.callout)
            Text("This restarts the current analysis phase with your choice. Completed phases, the full PDF and your selected passages remain available.")
                .foregroundStyle(.secondary)
            DisclosureGroup("Models used in completed phases") {
                VStack(alignment: .leading, spacing: 4) {
                    provenance("Findings", model: workspace.analysisModel)
                    provenance("Document overview", model: workspace.summaryModel)
                    provenance("Source passages", model: workspace.highlightModel)
                }.font(.caption)
            }.font(.caption)

            if usesPlan {
                if !planAccount.isConnected {
                    Label("Sign in to ChatGPT to load the selected account’s model catalog.", systemImage: "person.crop.circle.badge.exclamationmark")
                } else if planAccount.models.isEmpty {
                    HStack { ProgressView().controlSize(.small); Text(planAccount.busy ? planAccount.status : "Loading available account models…") }
                } else {
                    FocusChoiceTabs("ChatGPT workflow", selection: $choice.routing, options: [
                        .init(value: .single, title: "One model"),
                        .init(value: .orchestrated, title: "Orchestrator and agents")
                    ])
                    modelPicker(title: choice.routing == .single ? "ChatGPT model" : "Orchestrator model",
                                model: mainModelSelection, effort: $choice.orchestratorEffort, selected: selectedMain)
                    if choice.routing == .orchestrated {
                        modelPicker(title: "Agent model", model: workerModelSelection,
                                    effort: $choice.workerEffort, selected: selectedWorker)
                        Text("Agents process source passages independently. The orchestrator prepares the overview and coordinates reference checks.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("The selected model and reasoning effort are used for all tasks in this analysis.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !canApplyPlanChoice {
                        Text(consentVersion != OpenAIConsent.version
                             ? "Grant document-sharing consent in Settings before restarting a ChatGPT analysis."
                             : "Select current catalog models and supported reasoning efforts before applying. Unavailable saved choices are kept as-is until you choose replacements.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = planAccount.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                }
            } else {
                TextField("Model ID", text: $apiModelID).textFieldStyle(FocusInputFieldStyle())
            }

            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { workspace.showsChatGPTModelSwitch = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply and restart phase") { applyChoice() }
                    .buttonStyle(FocusPrimaryButtonStyle())
                    .disabled(!workspace.canSwitchChatGPTModel || (usesPlan && !canApplyPlanChoice) || (!usesPlan && !ChatGPTModelChoice.valid(slug: apiModelID)))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 470)
        .task {
            if usesPlan && planAccount.isConnected && planAccount.models.isEmpty { await planAccount.refreshModels() }
        }
        .buttonStyle(FocusSecondaryButtonStyle())
        .disclosureGroupStyle(FullRowDisclosureGroupStyle())
    }

    @ViewBuilder private func modelPicker(title: String, model: Binding<String>, effort: Binding<String>, selected: ChatGPTModel?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FocusMenuPicker(title, selection: model,
                            selectedTitle: selected?.displayName ?? (model.wrappedValue.isEmpty ? "Choose a model" : "\(model.wrappedValue) · unavailable")) {
                if selected == nil {
                    Text(model.wrappedValue.isEmpty ? "Choose a model" : "\(model.wrappedValue) · unavailable")
                        .tag(model.wrappedValue).disabled(true)
                }
                ForEach(planCatalog) { item in Text(item.displayName).tag(item.id) }
            }.disabled(planCatalog.isEmpty)

            if let selected, !selected.reasoningEfforts.isEmpty {
                FocusMenuPicker("Reasoning effort", selection: effort,
                                selectedTitle: selected.reasoningEfforts.contains(effort.wrappedValue) ? effort.wrappedValue.capitalized : "\(effort.wrappedValue) · unavailable") {
                    if !selected.reasoningEfforts.contains(effort.wrappedValue) {
                        Text("\(effort.wrappedValue) · unavailable").tag(effort.wrappedValue).disabled(true)
                    }
                    ForEach(selected.reasoningEfforts, id: \.self) { value in Text(value.capitalized).tag(value) }
                }
            } else if selected != nil {
                Text("This model uses its default reasoning setting.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func applyChoice() {
        if usesPlan {
            guard choice.encoded(using: planCatalog) != nil else {
                message = "Choose available models and supported reasoning options from the account catalog."
                return
            }
            workspace.applyChatGPTModelSwitch(choice, catalog: planCatalog)
        } else {
            guard ChatGPTModelChoice.valid(slug: apiModelID) else {
                message = "Choose a valid model ID."
                return
            }
            let apiCatalog = [ChatGPTModel(id: apiModelID, displayName: apiModelID, reasoningEfforts: [apiEffort])]
            let apiChoice = ChatGPTModelChoice(routing: .single, orchestratorModel: apiModelID,
                                               orchestratorEffort: apiEffort, workerModel: apiModelID, workerEffort: apiEffort)
            workspace.applyChatGPTModelSwitch(apiChoice, catalog: apiCatalog)
        }
    }

    private func provenance(_ title: String, model: String?) -> some View {
        Text("\(title): \(model.map(AIConfiguration.label) ?? "Not recorded")").textSelection(.enabled)
    }

    private static func makeChoice(_ encoded: String, plan: Bool) -> ChatGPTModelChoice {
        var identifier = encoded
        if plan, identifier.hasSuffix(":plan") { identifier.removeLast(5) }
        let parts = identifier.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let orchestrated = parts.count == 5 && parts[0] == "chatgpt"
        let mainSelection = AIConfiguration.chatGPTSelection(orchestrated ? "chatgpt:\(parts[1]):\(parts[2])" : identifier)
        let mainID = mainSelection?.model ?? ""
        let mainEffort = mainSelection?.effort ?? "auto"
        let savedWorkerKey = plan ? ChatGPTPlanPreferences.workerModelKey : ChatGPTPreferences.workerModelKey
        let savedWorkerEffortKey = plan ? ChatGPTPlanPreferences.workerEffortKey : ChatGPTPreferences.workerEffortKey
        let savedWorker = UserDefaults.standard.string(forKey: savedWorkerKey) ?? (plan ? ChatGPTPlanPreferences.defaultWorker : ChatGPTPreferences.defaultWorker)
        let savedWorkerEffort = UserDefaults.standard.string(forKey: savedWorkerEffortKey) ?? (plan ? ChatGPTPlanPreferences.defaultEffort : ChatGPTPreferences.defaultEffort)
        return ChatGPTModelChoice(
            routing: orchestrated ? .orchestrated : .single,
            orchestratorModel: mainID,
            orchestratorEffort: mainEffort,
            workerModel: orchestrated ? parts[3] : savedWorker,
            workerEffort: orchestrated ? parts[4] : savedWorkerEffort)
    }
}
