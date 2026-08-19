import Foundation

public struct AuthToken: Codable, Sendable, Hashable {
    public var token: String
    public var expiresOn: Date

    public init(token: String, expiresOn: Date) {
        self.token = token
        self.expiresOn = expiresOn
    }

    /// Treats a token as stale five minutes early so a long request cannot
    /// start on a token that expires mid-flight.
    public func isFresh(now: Date = Date(), margin: TimeInterval = 300) -> Bool {
        expiresOn.timeIntervalSince(now) > margin
    }
}

public struct LoginResponse: Codable, Sendable {
    public var accessToken: AuthToken
    public var refreshToken: AuthToken
    public var userId: String?
}

public struct UserSession: Sendable, Equatable {
    public var accessToken: AuthToken
    public var refreshToken: AuthToken
    public var userId: String?

    public init(accessToken: AuthToken, refreshToken: AuthToken, userId: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
    }
}

public struct M2MCredentials: Codable, Sendable, Equatable {
    public var clientId: String
    public var clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    /// Reads a credential pair out of a scanned QR payload.
    ///
    /// The portal's encoding is not specified, so the three plausible shapes are all
    /// accepted: a JSON object, a query string, or two values separated by a colon,
    /// comma or newline. Anything else returns nil rather than guessing, since a
    /// wrong pair fails later and further away.
    public static func parse(scannedPayload payload: String) -> M2MCredentials? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let id = string(object["clientId"] ?? object["client_id"]),
                  let secret = string(object["clientSecret"] ?? object["client_secret"])
            else { return nil }
            return M2MCredentials(clientId: id, clientSecret: secret)
        }

        if trimmed.contains("clientId=") || trimmed.contains("client_id=") {
            let query = trimmed.split(separator: "?").last.map(String.init) ?? trimmed
            var found: [String: String] = [:]
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                found[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
            }
            guard let id = string(found["clientId"] ?? found["client_id"]),
                  let secret = string(found["clientSecret"] ?? found["client_secret"])
            else { return nil }
            return M2MCredentials(clientId: id, clientSecret: secret)
        }

        // A URL would split on the scheme's colon into two plausible-looking halves.
        // The same scanner reads experience QR codes, so scanning one here must be
        // rejected rather than stored as a credential pair.
        guard !trimmed.contains("://") else { return nil }

        let parts = trimmed
            .split(whereSeparator: { $0 == ":" || $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count == 2 else { return nil }
        return M2MCredentials(clientId: parts[0], clientSecret: parts[1])
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Scopes an M2M client can hold. `query` is what localization and object tracking
/// need; `write` is required to create or modify maps.
public enum M2MScope: String, Codable, Sendable, CaseIterable {
    case query
    case write
}

public struct M2MClient: Codable, Sendable, Identifiable, Hashable {
    /// `clientId` is the identity here. The creation response carries no `_id`, so
    /// requiring one made every successful mint fail to decode.
    public var id: String { clientId }

    public var clientId: String
    /// Returned once at creation only, never when listing. There is no way to
    /// recover it later, so it has to be stored when it arrives.
    public var clientSecret: String?
    public var clientName: String?
    public var accountId: String?
    public var scopes: [String]?
    public var isActive: Bool?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case clientId, clientSecret, clientName, accountId, scopes, isActive, createdAt
    }
}

public struct M2MClientListPage: Codable, Sendable {
    public var clients: [M2MClient]?
    public var m2mClients: [M2MClient]?
    public var data: [M2MClient]?
    public var totalCount: Int?

    /// The list endpoint's array key is undocumented, so all three spellings seen
    /// in the wild are accepted rather than guessing one.
    public var all: [M2MClient] { clients ?? m2mClients ?? data ?? [] }
}

public struct UserProfile: Codable, Sendable, Equatable {
    public var id: String?
    public var fullName: String?
    public var email: String?
    public var companyName: String?
    public var region: String?
    public var accountId: String?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case fullName, email, companyName, region, accountId
    }

    public init(
        id: String? = nil,
        fullName: String? = nil,
        email: String? = nil,
        companyName: String? = nil,
        region: String? = nil,
        accountId: String? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.companyName = companyName
        self.region = region
        self.accountId = accountId
    }

    public var displayName: String {
        fullName?.isEmpty == false ? fullName! : (email ?? "Signed in")
    }
}

public struct PlanDetails: Codable, Sendable, Equatable {
    public var apiCalls: Int?
    public var storage: Double?
    public var mapsCount: Int?
    public var watermark: Bool?

    public init(apiCalls: Int? = nil, storage: Double? = nil, mapsCount: Int? = nil, watermark: Bool? = nil) {
        self.apiCalls = apiCalls
        self.storage = storage
        self.mapsCount = mapsCount
        self.watermark = watermark
    }
}

/// The identity a request is made under. The Clip only ever holds `.experience`,
/// which carries no credentials at all.
public enum AuthPrincipal: Sendable, Equatable {
    case anonymous
    case user(UserSession)
    case machine(AuthToken)
    case experience(spaceCode: String, token: AuthToken)

    public var bearerToken: String? {
        switch self {
        case .anonymous: nil
        case .user(let session): session.accessToken.token
        case .machine(let token): token.token
        case .experience(_, let token): token.token
        }
    }

    public var isAuthenticated: Bool { bearerToken != nil }
}
