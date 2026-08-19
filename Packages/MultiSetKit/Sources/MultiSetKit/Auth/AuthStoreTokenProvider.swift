import Foundation

/// Bridges `AuthStore` to whatever needs a bearer token, without that thing having
/// to know how the token was obtained.
///
/// The VPS engine needs a token per request and nothing more. Handing it this means
/// the same engine runs on a signed-in user's access token, on M2M credentials, or
/// on the App Clip's anonymous experience token — whichever principal the store
/// currently holds — with refresh and single-flighting already handled.
public struct AuthStoreTokenProvider: Sendable {
    private let store: AuthStore

    public init(store: AuthStore) {
        self.store = store
    }

    public func validToken() async throws -> String {
        try await store.validToken()
    }

    public func invalidateToken() async {
        await store.invalidateToken()
    }
}
