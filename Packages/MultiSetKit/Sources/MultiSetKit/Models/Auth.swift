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
}

public struct M2MClient: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var clientId: String
    /// Returned once at creation only. Never present when listing.
    public var clientSecret: String?
    public var name: String?
    public var status: String?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case clientId, clientSecret, name, status, createdAt
    }
}

public struct M2MClientListPage: Codable, Sendable {
    public var clients: [M2MClient]?
    public var totalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case clients, totalCount
    }
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
