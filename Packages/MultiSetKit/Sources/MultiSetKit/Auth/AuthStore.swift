import Foundation

/// Owns the active identity and its token lifecycle.
///
/// An actor because refresh is the one place concurrent callers can do real
/// damage: without a single-flight guard, ten simultaneous 401s become ten
/// token requests, and the server may invalidate the earlier ones.
public actor AuthStore {
    private var principal: AuthPrincipal = .anonymous
    private var machineCredentials: M2MCredentials?
    private var refreshTask: Task<AuthPrincipal, any Error>?
    private let client: HTTPClient
    private let secrets: any SecretStore
    private let clock: @Sendable () -> Date

    /// Counts completed token requests. Tests assert single-flighting against it.
    public private(set) var refreshCount = 0

    /// The last failure writing to the secret store. Sign-in still succeeds when
    /// this is set — the session works in memory — but it will not survive a
    /// relaunch, so Settings surfaces it rather than letting it pass silently.
    public private(set) var secretStoreFailure: (any Error)?

    public init(
        environment: APIEnvironment = .production,
        transport: any HTTPTransport = URLSession.shared,
        secrets: any SecretStore = Keychain(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = HTTPClient(baseURL: environment.baseURL, transport: transport)
        self.secrets = secrets
        self.clock = clock
    }

    /// Records rather than swallows a write failure, so a storage problem is
    /// visible instead of silently discarding the session.
    private func store(_ value: String, for key: Keychain.Key) {
        do {
            try secrets.set(value, for: key)
        } catch {
            secretStoreFailure = error
        }
    }

    public var currentPrincipal: AuthPrincipal { principal }
    public var isAuthenticated: Bool { principal.isAuthenticated }

    public var hasStoredSession: Bool {
        secrets.value(for: .refreshToken) != nil
    }

    public var storedEmail: String? {
        secrets.value(for: .userEmail)
    }

    public var storedMachineCredentials: M2MCredentials? {
        guard let id = secrets.value(for: .m2mClientId),
              let secret = secrets.value(for: .m2mClientSecret)
        else { return nil }
        return M2MCredentials(clientId: id, clientSecret: secret)
    }

    // MARK: - Establishing an identity

    public func signIn(email: String, password: String) async throws -> UserSession {
        struct Payload: Encodable {
            let email: String
            let password: String
        }
        let endpoint = try Endpoint.json(
            .post, "/v1/auth/login",
            body: Payload(email: email, password: password),
            requiresAuthentication: false
        )
        let response: LoginResponse
        do {
            response = try await client.send(endpoint, as: LoginResponse.self, context: "sign-in")
        } catch MultiSetError.unauthorized, MultiSetError.forbidden {
            throw MultiSetError.invalidCredentials
        }

        let session = UserSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId
        )
        principal = .user(session)
        store(response.refreshToken.token, for: .refreshToken)
        store(email, for: .userEmail)
        return session
    }

    /// Restores a session from the Keychain at launch. Returns nil when there is
    /// nothing stored, and throws only when a stored token is actively rejected.
    public func restoreSession() async throws -> UserSession? {
        guard let stored = secrets.value(for: .refreshToken) else { return nil }
        do {
            let session = try await exchangeRefreshToken(stored)
            principal = .user(session)
            if let credentials = storedMachineCredentials {
                machineCredentials = credentials
            }
            return session
        } catch MultiSetError.unauthorized, MultiSetError.invalidCredentials {
            signOut()
            return nil
        }
    }

    /// Activates M2M credentials for the SDK. Persists them so the SDK can be
    /// re-initialised on a later launch without another mint.
    public func activateMachineCredentials(_ credentials: M2MCredentials) async throws -> AuthToken {
        let token = try await mintMachineToken(credentials)
        machineCredentials = credentials
        store(credentials.clientId, for: .m2mClientId)
        store(credentials.clientSecret, for: .m2mClientSecret)
        return token
    }

    /// Resolves an anonymous experience token. This is the App Clip's entire
    /// auth story — no credentials are involved at any point.
    public func resolveExperience(spaceCode: String) async throws -> AuthToken {
        let token = try await fetchExperienceToken(spaceCode: spaceCode)
        principal = .experience(spaceCode: spaceCode, token: token)
        return token
    }

    public func signOut() {
        principal = .anonymous
        machineCredentials = nil
        refreshTask = nil
        secrets.removeAll()
    }

    // MARK: - Token access

    /// Returns a token good for at least the next five minutes, refreshing if
    /// needed. Concurrent callers share one in-flight refresh.
    public func validToken() async throws -> String {
        if let token = freshToken() { return token }

        if let inFlight = refreshTask {
            let refreshed = try await inFlight.value
            guard let token = refreshed.bearerToken else { throw MultiSetError.unauthorized }
            return token
        }

        let snapshot = principal
        let credentials = machineCredentials
        let task = Task<AuthPrincipal, any Error> { [weak self] in
            guard let self else { throw MultiSetError.cancelled }
            return try await self.refreshedPrincipal(from: snapshot, machineCredentials: credentials)
        }
        refreshTask = task

        do {
            let refreshed = try await task.value
            refreshTask = nil
            refreshCount += 1
            principal = refreshed
            if case .user(let session) = refreshed {
                store(session.refreshToken.token, for: .refreshToken)
            }
            guard let token = refreshed.bearerToken else { throw MultiSetError.unauthorized }
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    /// Forces the next `validToken()` to refresh. Called when a request comes
    /// back 401 despite a token that looked fresh.
    public func invalidateToken() {
        switch principal {
        case .user(var session):
            session.accessToken = AuthToken(token: session.accessToken.token, expiresOn: .distantPast)
            principal = .user(session)
        case .machine:
            principal = machineCredentials == nil ? .anonymous : principal
            if machineCredentials != nil {
                principal = .machine(AuthToken(token: "", expiresOn: .distantPast))
            }
        case .experience(let spaceCode, _):
            principal = .experience(
                spaceCode: spaceCode,
                token: AuthToken(token: "", expiresOn: .distantPast)
            )
        case .anonymous:
            break
        }
    }

    private func freshToken() -> String? {
        let now = clock()
        switch principal {
        case .anonymous:
            return nil
        case .user(let session):
            return session.accessToken.isFresh(now: now) ? session.accessToken.token : nil
        case .machine(let token):
            return token.isFresh(now: now) ? token.token : nil
        case .experience(_, let token):
            return token.isFresh(now: now) ? token.token : nil
        }
    }

    // MARK: - Refresh mechanics

    private func refreshedPrincipal(
        from snapshot: AuthPrincipal,
        machineCredentials: M2MCredentials?
    ) async throws -> AuthPrincipal {
        switch snapshot {
        case .anonymous:
            throw MultiSetError.unauthorized
        case .user(let session):
            return .user(try await exchangeRefreshToken(session.refreshToken.token))
        case .machine:
            guard let machineCredentials else { throw MultiSetError.unauthorized }
            return .machine(try await mintMachineToken(machineCredentials))
        case .experience(let spaceCode, _):
            return .experience(
                spaceCode: spaceCode,
                token: try await fetchExperienceToken(spaceCode: spaceCode)
            )
        }
    }

    private func exchangeRefreshToken(_ refreshToken: String) async throws -> UserSession {
        struct Payload: Encodable {
            let refreshToken: String
        }
        let endpoint = try Endpoint.json(
            .post, "/v1/auth/refresh-token",
            body: Payload(refreshToken: refreshToken),
            requiresAuthentication: false
        )
        let response = try await client.send(endpoint, as: LoginResponse.self, context: "session refresh")
        return UserSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId
        )
    }

    /// `POST /v1/m2m/token` is unusual: Basic auth *and* the credentials
    /// repeated in `Username`/`Password` headers, with a `text/plain` body.
    private func mintMachineToken(_ credentials: M2MCredentials) async throws -> AuthToken {
        let pair = "\(credentials.clientId):\(credentials.clientSecret)"
        let endpoint = Endpoint(
            method: .post,
            path: "/v1/m2m/token",
            contentType: "text/plain",
            basicAuthorization: Data(pair.utf8).base64EncodedString(),
            additionalHeaders: [
                "Username": credentials.clientId,
                "Password": credentials.clientSecret
            ],
            requiresAuthentication: false
        )
        do {
            return try await client.send(endpoint, as: AuthToken.self, context: "SDK credentials")
        } catch MultiSetError.unauthorized, MultiSetError.forbidden {
            throw MultiSetError.invalidCredentials
        }
    }

    private func fetchExperienceToken(spaceCode: String) async throws -> AuthToken {
        let endpoint = Endpoint(
            path: "/v1/auth/experience/\(spaceCode)",
            requiresAuthentication: false
        )
        do {
            return try await client.send(endpoint, as: AuthToken.self, context: "experience")
        } catch MultiSetError.notFound {
            throw MultiSetError.experienceUnavailable(.unknownCode)
        } catch MultiSetError.forbidden {
            throw MultiSetError.experienceUnavailable(.deactivated)
        }
    }
}
