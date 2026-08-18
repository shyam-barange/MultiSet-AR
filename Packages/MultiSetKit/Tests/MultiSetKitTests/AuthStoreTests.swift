import XCTest
@testable import MultiSetKit

/// Records every request and replies from a queue, so token lifecycle can be
/// tested without a network.
final actor StubTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [(Int, String)]
    private let delay: Duration

    init(responses: [(Int, String)], delay: Duration = .zero) {
        self.responses = responses
        self.delay = delay
    }

    var requestCount: Int { requests.count }

    func paths() -> [String] {
        requests.compactMap { $0.url?.path }
    }

    func header(_ field: String, at index: Int) -> String? {
        guard requests.indices.contains(index) else { return nil }
        return requests[index].value(forHTTPHeaderField: field)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let (status, body) = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}

final class AuthStoreTests: XCTestCase {
    private func loginBody(access: String, accessExpiry: String, refresh: String = "r1") -> String {
        """
        {"accessToken":{"token":"\(access)","expiresOn":"\(accessExpiry)"},
         "refreshToken":{"token":"\(refresh)","expiresOn":"2027-01-01T00:00:00.000Z"},
         "userId":"usr_1"}
        """
    }

    private func makeStore(
        transport: StubTransport,
        now: Date = Date(timeIntervalSince1970: 1_755_000_000)
    ) -> AuthStore {
        AuthStore(
            environment: .production,
            transport: transport,
            secrets: InMemorySecretStore(),
            clock: { now }
        )
    }

    // MARK: - Sign in

    func testSignInStoresUserPrincipal() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [(200, loginBody(access: "a1", accessExpiry: expiry))])
        let store = makeStore(transport: transport, now: now)

        let session = try await store.signIn(email: "alex@example.com", password: "secret")

        let isAuthenticated = await store.isAuthenticated
        let paths = await transport.paths()
        XCTAssertEqual(session.accessToken.token, "a1")
        XCTAssertTrue(isAuthenticated)
        XCTAssertEqual(paths, ["/v1/auth/login"])
    }

    func testSignInRejectionSurfacesInvalidCredentials() async {
        let transport = StubTransport(responses: [(401, #"{"message":"bad"}"#)])
        let store = makeStore(transport: transport)

        do {
            _ = try await store.signIn(email: "a@b.c", password: "wrong")
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .invalidCredentials)
        }
    }

    // MARK: - Token freshness

    func testFreshTokenIsReusedWithoutARefreshRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [(200, loginBody(access: "a1", accessExpiry: expiry))])
        let store = makeStore(transport: transport, now: now)
        _ = try await store.signIn(email: "a@b.c", password: "p")

        let token = try await store.validToken()

        let requestCount = await transport.requestCount
        let refreshCount = await store.refreshCount
        XCTAssertEqual(token, "a1")
        XCTAssertEqual(requestCount, 1, "no refresh should have been needed")
        XCTAssertEqual(refreshCount, 0)
    }

    func testTokenExpiringInsideTheMarginTriggersRefresh() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let formatter = ISO8601DateFormatter()
        // Four minutes out — inside the five-minute safety margin.
        let nearExpiry = formatter.string(from: now.addingTimeInterval(240))
        let farExpiry = formatter.string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [
            (200, loginBody(access: "a1", accessExpiry: nearExpiry)),
            (200, loginBody(access: "a2", accessExpiry: farExpiry, refresh: "r2"))
        ])
        let store = makeStore(transport: transport, now: now)
        _ = try await store.signIn(email: "a@b.c", password: "p")

        let token = try await store.validToken()

        let paths = await transport.paths()
        XCTAssertEqual(token, "a2")
        XCTAssertEqual(paths, ["/v1/auth/login", "/v1/auth/refresh-token"])
    }

    // MARK: - Single flight

    func testConcurrentCallersShareOneRefreshRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let formatter = ISO8601DateFormatter()
        let stale = formatter.string(from: now.addingTimeInterval(-60))
        let fresh = formatter.string(from: now.addingTimeInterval(1_800))
        // One login, then a single slow refresh. Any second refresh attempt
        // finds the queue empty and throws, failing the test.
        let transport = StubTransport(
            responses: [
                (200, loginBody(access: "a1", accessExpiry: stale)),
                (200, loginBody(access: "a2", accessExpiry: fresh, refresh: "r2"))
            ],
            delay: .milliseconds(120)
        )
        let store = makeStore(transport: transport, now: now)
        _ = try await store.signIn(email: "a@b.c", password: "p")

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 {
                group.addTask { try await store.validToken() }
            }
            var collected: [String] = []
            for try await token in group { collected.append(token) }
            return collected
        }

        let requestCount = await transport.requestCount
        let refreshCount = await store.refreshCount
        XCTAssertEqual(tokens.count, 12)
        XCTAssertTrue(tokens.allSatisfy { $0 == "a2" }, "all callers should see the refreshed token")
        XCTAssertEqual(requestCount, 2, "12 concurrent callers must cause exactly one refresh")
        XCTAssertEqual(refreshCount, 1)
    }

    func testFailedRefreshClearsTheInFlightTaskSoALaterCallRetries() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let formatter = ISO8601DateFormatter()
        let stale = formatter.string(from: now.addingTimeInterval(-60))
        let fresh = formatter.string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [
            (200, loginBody(access: "a1", accessExpiry: stale)),
            (500, #"{"message":"upstream"}"#),
            (200, loginBody(access: "a3", accessExpiry: fresh, refresh: "r3"))
        ])
        let store = makeStore(transport: transport, now: now)
        _ = try await store.signIn(email: "a@b.c", password: "p")

        do {
            _ = try await store.validToken()
            XCTFail("expected the first refresh to fail")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .server(status: 500, message: "upstream"))
        }

        let token = try await store.validToken()
        XCTAssertEqual(token, "a3", "a failed refresh must not poison later attempts")
    }

    // MARK: - M2M

    func testMachineTokenRequestCarriesBasicAndDuplicatedHeaders() async throws {
        let transport = StubTransport(responses: [
            (200, #"{"token":"m2m-token","expiresOn":"2027-01-01T00:00:00.000Z"}"#)
        ])
        let store = makeStore(transport: transport)

        let token = try await store.activateMachineCredentials(
            M2MCredentials(clientId: "cid", clientSecret: "csecret")
        )

        let paths = await transport.paths()
        let authorization = await transport.header("Authorization", at: 0)
        let username = await transport.header("Username", at: 0)
        let password = await transport.header("Password", at: 0)
        let contentType = await transport.header("Content-Type", at: 0)
        let expected = Data("cid:csecret".utf8).base64EncodedString()

        XCTAssertEqual(token.token, "m2m-token")
        XCTAssertEqual(paths, ["/v1/m2m/token"])
        XCTAssertEqual(authorization, "Basic \(expected)")
        XCTAssertEqual(username, "cid")
        XCTAssertEqual(password, "csecret")
        XCTAssertEqual(contentType, "text/plain")
    }

    func testRejectedMachineCredentialsSurfaceAsInvalidCredentials() async {
        let transport = StubTransport(responses: [(401, "{}")])
        let store = makeStore(transport: transport)

        do {
            _ = try await store.activateMachineCredentials(
                M2MCredentials(clientId: "cid", clientSecret: "wrong")
            )
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .invalidCredentials)
        }
    }

    // MARK: - Experience token

    func testExperienceTokenIsFetchedWithoutAnyCredential() async throws {
        let transport = StubTransport(responses: [
            (200, #"{"token":"exp-token","expiresOn":"2027-01-01T00:00:00.000Z"}"#)
        ])
        let store = makeStore(transport: transport)

        let token = try await store.resolveExperience(spaceCode: "k7m2p9xq")

        let paths = await transport.paths()
        let authorization = await transport.header("Authorization", at: 0)
        XCTAssertEqual(token.token, "exp-token")
        XCTAssertEqual(paths, ["/v1/auth/experience/k7m2p9xq"])
        XCTAssertNil(authorization, "the Clip must send no credential")
    }

    func testUnknownSpaceCodeMapsToUnknownCodeReason() async {
        let transport = StubTransport(responses: [(404, "{}")])
        let store = makeStore(transport: transport)

        do {
            _ = try await store.resolveExperience(spaceCode: "nope")
            XCTFail("expected experienceUnavailable")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.unknownCode))
        }
    }

    func testForbiddenSpaceMapsToDeactivatedReason() async {
        let transport = StubTransport(responses: [(403, "{}")])
        let store = makeStore(transport: transport)

        do {
            _ = try await store.resolveExperience(spaceCode: "ended")
            XCTFail("expected experienceUnavailable")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.deactivated))
        }
    }

    func testExpiredExperienceTokenRefreshesSilently() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let formatter = ISO8601DateFormatter()
        let stale = formatter.string(from: now.addingTimeInterval(-10))
        let fresh = formatter.string(from: now.addingTimeInterval(900))
        let transport = StubTransport(responses: [
            (200, #"{"token":"exp1","expiresOn":"\#(stale)"}"#),
            (200, #"{"token":"exp2","expiresOn":"\#(fresh)"}"#)
        ])
        let store = makeStore(transport: transport, now: now)
        _ = try await store.resolveExperience(spaceCode: "k7m2p9xq")

        let token = try await store.validToken()

        let paths = await transport.paths()
        XCTAssertEqual(token, "exp2")
        XCTAssertEqual(paths, ["/v1/auth/experience/k7m2p9xq", "/v1/auth/experience/k7m2p9xq"])
    }

    // MARK: - Sign out

    func testSignOutClearsPrincipalAndStoredSecrets() async throws {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [(200, loginBody(access: "a1", accessExpiry: expiry))])
        let secrets = InMemorySecretStore()
        let store = AuthStore(transport: transport, secrets: secrets, clock: { now })
        _ = try await store.signIn(email: "a@b.c", password: "p")
        let hadSession = await store.hasStoredSession
        XCTAssertTrue(hadSession)

        await store.signOut()

        let isAuthenticated = await store.isAuthenticated
        let hasStoredSession = await store.hasStoredSession
        let machineCredentials = await store.storedMachineCredentials
        XCTAssertFalse(isAuthenticated)
        XCTAssertFalse(hasStoredSession)
        XCTAssertNil(machineCredentials)
        XCTAssertNil(secrets.value(for: .refreshToken))
    }

    func testAnonymousPrincipalCannotProduceAToken() async {
        let transport = StubTransport(responses: [])
        let store = makeStore(transport: transport)

        do {
            _ = try await store.validToken()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .unauthorized)
        }
        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 0, "no request should be attempted")
    }
}

final class SecretStoreTests: XCTestCase {
    func testAWriteFailureIsRecordedRatherThanSwallowed() async throws {
        struct FailingStore: SecretStore {
            struct Denied: Error {}
            func set(_ value: String, for key: Keychain.Key) throws { throw Denied() }
            func value(for key: Keychain.Key) -> String? { nil }
            func remove(_ key: Keychain.Key) {}
            func removeAll() {}
        }

        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [(200, """
        {"accessToken":{"token":"a1","expiresOn":"\(expiry)"},
         "refreshToken":{"token":"r1","expiresOn":"2027-01-01T00:00:00.000Z"},
         "userId":"usr_1"}
        """)])
        let store = AuthStore(transport: transport, secrets: FailingStore(), clock: { now })

        // Sign-in still succeeds: the session is usable in memory this launch.
        let session = try await store.signIn(email: "a@b.c", password: "p")
        XCTAssertEqual(session.accessToken.token, "a1")

        let failure = await store.secretStoreFailure
        XCTAssertNotNil(failure, "a storage failure must be visible, not silent")
    }

    func testInMemoryStoreRoundTripsAndClears() throws {
        let store = InMemorySecretStore()
        try store.set("r1", for: .refreshToken)
        XCTAssertEqual(store.value(for: .refreshToken), "r1")
        store.remove(.refreshToken)
        XCTAssertNil(store.value(for: .refreshToken))

        try store.set("cid", for: .m2mClientId)
        try store.set("csecret", for: .m2mClientSecret)
        store.removeAll()
        XCTAssertNil(store.value(for: .m2mClientId))
        XCTAssertNil(store.value(for: .m2mClientSecret))
    }
}
