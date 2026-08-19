/*
Portions copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. For license details, visit www.multiset.ai.

This file is not part of the original SDK. It replaces the SDK's AuthManager,
which obtained a token by exchanging an M2M clientId and clientSecret at
POST /v1/m2m/token.
*/

import Foundation

/// Supplies the bearer token every VPS request carries.
///
/// The SDK's `AuthManager` minted its own token from a clientId and clientSecret.
/// Nothing downstream of it needed those credentials — the token appears only as
/// `Bearer <token>` on eight requests — so this protocol takes their place. That
/// lets the engine run on:
///
/// - the signed-in user's access token, refreshed from their refresh token
/// - the App Clip's anonymous experience token, which carries no credential at all
///
/// Implementations are expected to refresh as needed and to be safe to call from
/// several requests at once.
public protocol VPSTokenProviding: Sendable {
    /// A token good for the next request. Implementations refresh if the current
    /// one is close to expiry.
    func validToken() async throws -> String

    /// Called when a request came back 401 despite a token that looked valid, so
    /// the next `validToken()` re-fetches rather than returning the same one.
    func invalidateToken() async
}

/// Holds the token the managers read synchronously.
///
/// The ported managers build `URLRequest`s in non-async completion-handler code and
/// take the token as a plain string, so the orchestrator refreshes this box before
/// each run rather than threading `async` through all of them. A session that runs
/// for an hour with background re-localization therefore never outlives a 30-minute
/// token.
public final class VPSTokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String

    public init(token: String = "") {
        self.current = token
    }

    public var value: String {
        lock.withLock { current }
    }

    public func update(_ token: String) {
        lock.withLock { current = token }
    }
}

/// A fixed token, for tests and for callers that manage refresh themselves.
public struct StaticVPSToken: VPSTokenProviding {
    private let token: String

    public init(_ token: String) {
        self.token = token
    }

    public func validToken() async throws -> String { token }
    public func invalidateToken() async {}
}

/// Adapts any async token closure, for hosts that already have one.
public struct ClosureVPSToken: VPSTokenProviding {
    private let fetch: @Sendable () async throws -> String
    private let invalidate: @Sendable () async -> Void

    public init(
        fetch: @escaping @Sendable () async throws -> String,
        invalidate: @escaping @Sendable () async -> Void = {}
    ) {
        self.fetch = fetch
        self.invalidate = invalidate
    }

    public func validToken() async throws -> String { try await fetch() }
    public func invalidateToken() async { await invalidate() }
}
