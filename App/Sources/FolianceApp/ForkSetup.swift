import Foundation

/// A fresh product never imports another app's preferences, files or credentials.
enum ForkSetup {
    static func migrate() {
        UserDefaults.standard.register(defaults: ["uiLanguage": "en", "localAIProvider": "apple"])
    }
    static func migrate(defaults: UserDefaults, sourceDefaults: [String: Any], support: URL) {
        // Intentionally ignore external settings and storage, including account information.
        defaults.register(defaults: ["uiLanguage": "en", "localAIProvider": "apple"])
    }
}
