import Foundation
import Security

protocol OpenAISecretStore: Sendable {
    func read() throws -> String?
    func contains() throws -> Bool
    func save(_ value: String) throws
    func delete() throws
}

struct OpenAIKeychainStore: OpenAISecretStore {
    static let service = "app.foliance.mac.openai"
    static let account = "api-key"

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account,
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw OpenAICredentialError.keychain(status)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func contains() throws -> Bool {
        var query = identity
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw OpenAICredentialError.keychain(status) }
        return true
    }

    func save(_ value: String) throws {
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8),
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updateStatus = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw OpenAICredentialError.keychain(updateStatus) }

        var item = identity
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw OpenAICredentialError.keychain(addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAICredentialError.keychain(status)
        }
    }
}

enum OpenAICredentialError: LocalizedError, Sendable {
    case keychain(OSStatus)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .keychain: "Foliance could not update the API key in this Mac’s Keychain."
        case .invalidFormat: "Enter a valid API key without spaces or control characters."
        }
    }
}

struct OpenAICredentials: Sendable {
    static let shared = OpenAICredentials(store: OpenAIKeychainStore())
    private let store: any OpenAISecretStore

    init(store: any OpenAISecretStore) { self.store = store }

    static let maximumKeyLength = 4096

    var hasAPIKey: Bool { (try? store.contains()) == true }
    func apiKey() throws -> String? { try store.read() }
    func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWhitespaceOrControl = value.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }
        guard !value.isEmpty, value.utf8.count <= Self.maximumKeyLength, !hasWhitespaceOrControl else {
            throw OpenAICredentialError.invalidFormat
        }
        try store.save(value)
    }
    func remove() throws { try store.delete() }
}
