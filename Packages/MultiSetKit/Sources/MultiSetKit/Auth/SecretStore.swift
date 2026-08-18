import Foundation

/// Where secrets live. Abstracted so tests never touch the real device keychain,
/// which is unavailable to unit-test bundles without a host app.
public protocol SecretStore: Sendable {
    func set(_ value: String, for key: Keychain.Key) throws
    func value(for key: Keychain.Key) -> String?
    func remove(_ key: Keychain.Key)
    func removeAll()
}

extension Keychain: SecretStore {}

/// In-memory store for tests and previews. Nothing persists across launches.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Keychain.Key: String] = [:]

    public init() {}

    public func set(_ value: String, for key: Keychain.Key) throws {
        lock.withLock { storage[key] = value }
    }

    public func value(for key: Keychain.Key) -> String? {
        lock.withLock { storage[key] }
    }

    public func remove(_ key: Keychain.Key) {
        lock.withLock { storage[key] = nil }
    }

    public func removeAll() {
        lock.withLock { storage.removeAll() }
    }
}
