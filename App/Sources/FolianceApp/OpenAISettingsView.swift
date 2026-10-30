import SwiftUI

struct OpenAISettingsView: View {
    @ObservedObject private var apiAccount = ChatGPTAccount.shared
    @ObservedObject private var planAccount = ChatGPTSubscriptionAccount.shared
    @AppStorage("localAIProvider") private var provider = "apple"
    @AppStorage(ChatGPTPreferences.modelKey) private var savedAPIModel = ChatGPTPreferences.defaultOrchestrator
    @AppStorage(ChatGPTPreferences.effortKey) private var savedAPIEffort = "auto"
    @AppStorage(ChatGPTPlanPreferences.modelKey) private var planModel = ""
    @AppStorage(ChatGPTPlanPreferences.effortKey) private var planEffort = "auto"
    @AppStorage(ChatGPTPlanPreferences.modeKey) private var planRoutingMode = AIConfiguration.ChatGPTMode.single.rawValue
    @AppStorage(ChatGPTPlanPreferences.workerModelKey) private var planWorkerModel = ""
    @AppStorage(ChatGPTPlanPreferences.workerEffortKey) private var planWorkerEffort = "auto"
    @AppStorage("chatGPTPlanWelcomeShown") private var planWelcomeShown = false
    @State private var enteredAPIKey = ""
    @State private var apiModelID = ChatGPTPreferences.defaultOrchestrator
    @State private var consentGranted = OpenAIConsent.isGranted()
    @State private var message = ""
    @State private var showingPlanWelcome = false

    private var canUseAPI: Bool { apiAccount.hasAPIKey && consentGranted }
    private var hasAvailablePlanModel: Bool {
        guard hasAvailablePlanChoice(modelID: planModel, effort: planEffort) else { return false }
        guard planRoutingMode == AIConfiguration.ChatGPTMode.orchestrated.rawValue else { return true }
        return hasAvailablePlanChoice(modelID: planWorkerModel, effort: planWorkerEffort)
    }
    private var canUsePlan: Bool { planAccount.canUsePlan && consentGranted && hasAvailablePlanModel }

    private func hasAvailablePlanChoice(modelID: String, effort: String) -> Bool {
        guard !modelID.isEmpty, let selected = planAccount.models.first(where: { $0.id == modelID }) else { return false }
        return selected.reasoningEfforts.isEmpty ? effort == "auto" : selected.reasoningEfforts.contains(effort)
    }

    private var selectedProviderTitle: String {
        switch provider {
        case "openai": "OpenAI API key"
        case "chatgpt": "ChatGPT plan"
        default: "Apple Intelligence · on-device"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FocusMenuPicker("AI provider", selection: $provider, selectedTitle: selectedProviderTitle) {
                Text("Apple Intelligence · on-device").tag("apple")
                Text("OpenAI API key").tag("openai").disabled(!canUseAPI)
                Text("ChatGPT plan").tag("chatgpt").disabled(!canUsePlan)
            }

            GroupBox("OpenAI API key") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(apiAccount.status).font(.callout)
                    SecureField("Paste API key", text: $enteredAPIKey)
                        .textFieldStyle(FocusInputFieldStyle())
                        .textContentType(.password)
                        .privacySensitive()
                    HStack {
                        Button("Save key") {
                            apiAccount.saveAPIKey(enteredAPIKey)
                            if apiAccount.error == nil { enteredAPIKey = "" }
                        }.disabled(enteredAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove key") {
                            apiAccount.removeAPIKey()
                            if provider == "openai" { provider = "apple" }
                        }.disabled(!apiAccount.hasAPIKey)
                    }
                    Text("API keys and ChatGPT sign-in tokens have separate Keychain storage. API requests use your key; plan requests use your selected ChatGPT account.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = apiAccount.error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }

            ChatGPTSubscriptionSettingsView()

            GroupBox("Cloud processing consent") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When you explicitly start an analysis with either cloud option, Foliance sends extracted document text and selected passages, optional reference-document text and criteria, your reading goal, and your questions to OpenAI. Selecting a provider does not send document content. The API-key option uses your key and API billing; the ChatGPT option uses eligible plan usage or credits. Review the applicable service terms before continuing.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if consentGranted {
                        HStack {
                            Text("Consent is enabled for cloud processing.").font(.callout)
                            Spacer()
                            Button("Revoke consent") {
                                OpenAIConsent.revoke()
                                consentGranted = false
                                if provider == "openai" || provider == "chatgpt" { provider = "apple" }
                            }
                        }
                    } else {
                        Button("I consent and enable cloud options") {
                            OpenAIConsent.grant()
                            consentGranted = OpenAIConsent.isGranted()
                        }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("OpenAI API model") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Model ID", text: $apiModelID).textFieldStyle(FocusInputFieldStyle())
                    HStack {
                        Button("Save model ID") {
                            let value = apiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard ChatGPTModelChoice.valid(slug: value) else {
                                message = "Enter a model ID containing letters, numbers, periods, underscores, or hyphens."
                                return
                            }
                            savedAPIModel = value
                            savedAPIEffort = "auto"
                            apiModelID = value
                            message = "Model ID saved. OpenAI checks access when you run an analysis."
                        }
                        Button("Use recommended model") {
                            apiModelID = ChatGPTPreferences.defaultOrchestrator
                            savedAPIModel = apiModelID
                            savedAPIEffort = "auto"
                            message = "Recommended API model selected: \(apiModelID)."
                        }
                    }
                    Text("Default API model: gpt-5.4-mini. Availability depends on your API account; Foliance does not guess or import an API catalog.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            apiModelID = savedAPIModel
            presentPlanWelcomeIfNeeded()
        }
        .onChange(of: savedAPIModel) { _, value in apiModelID = value }
        .onChange(of: planAccount.canUsePlan) { _, eligible in
            if eligible { presentPlanWelcomeIfNeeded() }
        }
        .onChange(of: consentGranted) { _, granted in
            if !granted && (provider == "openai" || provider == "chatgpt") { provider = "apple" }
        }
        .sheet(isPresented: $showingPlanWelcome) { planWelcome }
    }

    private func presentPlanWelcomeIfNeeded() {
        guard planAccount.canUsePlan, !planWelcomeShown else { return }
        showingPlanWelcome = true
    }

    private var planWelcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Using your ChatGPT plan").font(.title2.bold())
            Text("Eligible Foliance requests use your connected ChatGPT plan or available credits. Usage depends on your account eligibility and current limits. Manage usage in ChatGPT. Foliance does not sell subscription access or ask you to upgrade.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: "https://chatgpt.com/#settings/Usage") {
                Link("Manage usage and credits in ChatGPT", destination: url)
            }
            HStack {
                Spacer()
                Button("Got it") {
                    planWelcomeShown = true
                    showingPlanWelcome = false
                }.buttonStyle(FocusPrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(SPTheme.background)
        .buttonStyle(FocusSecondaryButtonStyle())
    }
}
