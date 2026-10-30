import Foundation

enum OpenAIConsent {
    static let version = 2
    static let defaultsKey = "openAIDataSharingConsentVersion"

    static func isGranted(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: defaultsKey) == version
    }

    static func grant(defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: defaultsKey)
    }

    static func revoke(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
