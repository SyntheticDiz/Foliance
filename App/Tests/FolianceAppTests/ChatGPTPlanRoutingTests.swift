import XCTest
@testable import FolianceApp

final class ChatGPTPlanRoutingTests: XCTestCase {
    func testCapturedPlanBillingSurvivesProviderPreferenceChangesAndWorkerRouting() throws {
        let suite = "Foliance-PlanRouting-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("chatgpt", forKey: "localAIProvider")
        defaults.set("account-visible-model", forKey: ChatGPTPlanPreferences.modelKey)
        defaults.set("auto", forKey: ChatGPTPlanPreferences.effortKey)
        let captured = AIConfiguration.selectedModel(defaults: defaults)
        defaults.set("openai", forKey: "localAIProvider")
        XCTAssertTrue(AIConfiguration.usesChatGPTPlan(captured))
        XCTAssertFalse(AIConfiguration.usesChatGPTPlan(AIConfiguration.selectedModel(defaults: defaults)))
        XCTAssertTrue(AIConfiguration.usesChatGPTPlan(AIConfiguration.workerModel(captured)))
        XCTAssertTrue(AIConfiguration.usesChatGPTPlan(AIConfiguration.orchestratorModel(captured)))
        let job = AIConfiguration.chatGPTJob(orchestrator: "main-model", effort: "high", worker: "worker-model", workerEffort: "auto") + ":plan"
        XCTAssertEqual(AIConfiguration.workerModel(job), AIConfiguration.chatGPTPlanModel("worker-model", effort: "auto"))
        XCTAssertEqual(AIConfiguration.orchestratorModel(job), AIConfiguration.chatGPTPlanModel("main-model", effort: "high"))
        XCTAssertNotEqual(LocalCache.key([captured]), LocalCache.key([AIConfiguration.chatGPTModel("account-visible-model", effort: "auto")]))
    }

    func testPlanWorkflowUsesSeparateMainAndWorkerChoicesWithoutChangingAPISettings() throws {
        let suite = "Foliance-PlanWorkflow-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("chatgpt", forKey: "localAIProvider")
        defaults.set("api-model", forKey: ChatGPTPreferences.modelKey)
        XCTAssertEqual(AIConfiguration.selectedModel(defaults: defaults), AIConfiguration.chatGPTPlanModel("gpt-6.1-sol", effort: "high"))
        defaults.set("orchestrated", forKey: ChatGPTPlanPreferences.modeKey)
        defaults.set("gpt-6-luna", forKey: ChatGPTPlanPreferences.workerModelKey)
        defaults.set("medium", forKey: ChatGPTPlanPreferences.workerEffortKey)
        let job = AIConfiguration.selectedModel(defaults: defaults)
        XCTAssertEqual(AIConfiguration.orchestratorModel(job), AIConfiguration.chatGPTPlanModel("gpt-6.1-sol", effort: "high"))
        XCTAssertEqual(AIConfiguration.workerModel(job), AIConfiguration.chatGPTPlanModel("gpt-6-luna", effort: "medium"))
        defaults.set("single", forKey: ChatGPTPlanPreferences.modeKey)
        XCTAssertEqual(AIConfiguration.selectedModel(defaults: defaults), AIConfiguration.chatGPTPlanModel("gpt-6.1-sol", effort: "high"))
        XCTAssertEqual(defaults.string(forKey: ChatGPTPlanPreferences.workerEffortKey), "medium")
        XCTAssertEqual(defaults.string(forKey: ChatGPTPreferences.modelKey), "api-model")
    }

    func testPlanDoesNotFallBackToAPIKeyWhenPlanPermissionIsMissing() async {
        let plan = AIConfiguration.chatGPTPlanModel("account-visible-model", effort: "auto")
        do {
            _ = try await AIRouting.resolve(plan, appleUnavailable: { nil }, openAIReady: { true }, chatGPTPlanReady: { false })
            XCTFail("An API key must not fund a plan request when plan authorization is absent.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("ChatGPT plan"))
        }
        do {
            let resolved = try await AIRouting.resolve(plan, appleUnavailable: { "Unavailable" }, openAIReady: { false }, chatGPTPlanReady: { true })
            XCTAssertEqual(resolved, plan)
        } catch { XCTFail("A ready plan should route without an API key: \(error)") }
    }

    func testAPIRequestsDoNotUsePlanPermissionAsAReplacementForAKey() async {
        do {
            _ = try await AIRouting.resolve(AIConfiguration.chatGPTModel("api-model", effort: "auto"),
                                           appleUnavailable: { nil }, openAIReady: { false }, chatGPTPlanReady: { true })
            XCTFail("Plan permission must not authorize API-key billing.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("API key")) }
    }
}
