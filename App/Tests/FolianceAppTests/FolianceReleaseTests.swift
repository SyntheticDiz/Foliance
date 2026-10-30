import XCTest
@testable import FolianceApp

final class FolianceReleaseTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func plist(at relativePath: String) throws -> [String: Any] {
        let url = projectRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testUnknownProviderCannotSilentlySelectCloudBilling() throws {
        let suite = "Foliance-ReleaseRouting-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unrecognized", forKey: "localAIProvider")
        defaults.set("chatgpt:gpt-6-astra:xhigh:gpt-6-luna:high", forKey: "model")
        defaults.set("gpt-6-astra", forKey: "chatGPTModel")
        defaults.set("account@example.invalid", forKey: "chatGPTAccountEmail")

        XCTAssertEqual(AIConfiguration.selectedModel(defaults: defaults), AppleAIService.modelID)
        XCTAssertEqual(defaults.string(forKey: "localAIProvider"), "unrecognized", "Selection should not rewrite user defaults as a side effect.")
        XCTAssertEqual(defaults.string(forKey: "chatGPTModel"), "gpt-6-astra")
    }

    func testAppIdentityVersionAndPatchNotesAgree() throws {
        let info = try plist(at: "Config/Info.plist")
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "app.foliance.mac")
        XCTAssertEqual(info["CFBundleName"] as? String, "Foliance")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Foliance")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(info["CFBundleVersion"] as? String, "3")
        XCTAssertEqual(Set(info["CFBundleLocalizations"] as? [String] ?? []), Set(["en"]))
        XCTAssertEqual(PatchNotesView.version, info["CFBundleShortVersionString"] as? String)

        let notes = try String(contentsOf: projectRoot.appendingPathComponent("Sources/FolianceApp/PatchNotesView.swift"), encoding: .utf8)
        XCTAssertTrue(notes.contains("Foliance 1.0.0"))
        XCTAssertTrue(notes.contains("English interface update · build 3"))
        XCTAssertFalse(notes.contains("5.32."), "The first release must not carry forward predecessor history.")
    }

    func testPrivacyDisclosesOptionalUserContentAndOAuthCallbackWithoutTracking() throws {
        let entitlements = try plist(at: "Config/Foliance.entitlements")
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.server"] as? Bool, true)
        XCTAssertNil(entitlements["keychain-access-groups"])
        XCTAssertNil(entitlements["com.apple.security.application-groups"])

        let privacy = try plist(at: "Config/PrivacyInfo.xcprivacy")
        XCTAssertEqual(privacy["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(privacy["NSPrivacyTrackingDomains"] as? [String], [])
        let types = try XCTUnwrap(privacy["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let userContent = try XCTUnwrap(types.first { $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeOtherUserContent" })
        XCTAssertEqual(userContent["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        XCTAssertEqual(userContent["NSPrivacyCollectedDataTypePurposes"] as? [String], ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
    }
}
