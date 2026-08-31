import Foundation
import Security

protocol OpenAIAPIKeyStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String?) throws
}

enum OpenAIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status):
            "Le trousseau sécurisé est indisponible (\(status))."
        }
    }
}

struct KeychainOpenAIAPIKeyStore: OpenAIAPIKeyStore {
    private let service: String
    private let account: String

    init(service: String = "com.jeremydelloume.Lore.openai", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw OpenAIKeyStoreError.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw LoreAIError.invalidAPIKey
        }
        return key
    }

    func saveAPIKey(_ key: String?) throws {
        guard let key else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw OpenAIKeyStoreError.keychain(status)
            }
            return
        }
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let data = normalized.data(using: .utf8) else {
            throw LoreAIError.invalidAPIKey
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw OpenAIKeyStoreError.keychain(updateStatus)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw OpenAIKeyStoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
