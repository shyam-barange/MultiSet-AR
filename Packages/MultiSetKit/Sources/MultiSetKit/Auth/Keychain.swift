import Foundation
import Security

/// Minimal Keychain wrapper for the few secrets this app holds. Items are
/// `.whenUnlockedThisDeviceOnly` so they never sync to iCloud or a backup.
public struct Keychain: Sendable {
    private let service: String

    public init(service: String = "ai.multiset.ar.credentials") {
        self.service = service
    }

    public enum Key: String, Sendable, CaseIterable {
        case refreshToken
        case m2mClientId
        case m2mClientSecret
        case userEmail
    }

    public func set(_ value: String, for key: Key) throws {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData as String: data]
            let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard result == errSecSuccess else { throw KeychainError(status: result) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(query as CFDictionary, nil)
            guard result == errSecSuccess else { throw KeychainError(status: result) }
        } else {
            throw KeychainError(status: status)
        }
    }

    public func value(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func remove(_ key: Key) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    /// Clears every secret. Used by sign-out, which must leave nothing behind.
    public func removeAll() {
        for key in Key.allCases { remove(key) }
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
        return "Couldn't reach the device keychain: \(detail)"
    }
}
