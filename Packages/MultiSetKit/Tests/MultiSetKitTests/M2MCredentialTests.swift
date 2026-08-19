import XCTest
@testable import MultiSetKit

/// The mint request and its response are pinned against the shapes in the API's own
/// Postman collection. Both were wrong before: the request sent `name` with no
/// `scope`, which the server rejects, and the response decoder required an `_id`
/// the server never sends — so a successful mint still failed, and the app fell
/// back to telling the user SDK credentials were needed.
final class M2MCredentialTests: XCTestCase {
    private func loginBody(expiry: String) -> String {
        """
        {"accessToken":{"token":"a1","expiresOn":"\(expiry)"},
         "refreshToken":{"token":"r1","expiresOn":"2027-01-01T00:00:00.000Z"},
         "userId":"u1"}
        """
    }

    private func signedInAPI(
        responses: [(Int, String)]
    ) async throws -> (LiveMultiSetAPI, StubTransport) {
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(1_800))
        let transport = StubTransport(responses: [(200, loginBody(expiry: expiry))] + responses)
        let auth = AuthStore(transport: transport, secrets: InMemorySecretStore(), clock: { now })
        _ = try await auth.signIn(email: "a@b.c", password: "p")
        return (LiveMultiSetAPI(auth: auth, transport: transport), transport)
    }

    // MARK: - Request shape

    func testMintSendsClientNameAndScope() async throws {
        let (api, transport) = try await signedInAPI(responses: [(201, """
        {"clientId":"550e8400","clientSecret":"abc123","clientName":"MultiSet AR",
         "accountId":"60d5","scopes":["query"]}
        """)])

        _ = try await api.mintM2MCredentials(name: "MultiSet AR")

        let raw = await transport.body(at: 1)
        let body = try XCTUnwrap(raw)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["clientName"] as? String, "MultiSet AR")
        XCTAssertEqual(json["scope"] as? [String], ["query"], "scope is required, not optional")
        XCTAssertNil(json["name"], "the field is clientName; sending name is rejected")
    }

    func testMintDefaultsToQueryScopeOnly() async throws {
        // Localization and object tracking need query. Requesting write as well would
        // hand the SDK credentials more authority than the flows use.
        let (api, transport) = try await signedInAPI(responses: [(201, """
        {"clientId":"c","clientSecret":"s","scopes":["query"]}
        """)])
        _ = try await api.mintM2MCredentials(name: "x")
        let raw = await transport.body(at: 1)
        let body = try XCTUnwrap(raw)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["scope"] as? [String], ["query"])
    }

    func testMintCanRequestWriteWhenAsked() async throws {
        let (api, transport) = try await signedInAPI(responses: [(201, """
        {"clientId":"c","clientSecret":"s","scopes":["query","write"]}
        """)])
        _ = try await api.mintM2MCredentials(name: "x", scopes: [.query, .write])
        let raw = await transport.body(at: 1)
        let body = try XCTUnwrap(raw)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["scope"] as? [String], ["query", "write"])
    }

    // MARK: - Response shape

    func testMintDecodesAResponseWithNoUnderscoreId() async throws {
        // The documented 201 body carries clientId but no _id. Requiring one made
        // every successful mint fail to decode.
        let (api, _) = try await signedInAPI(responses: [(201, """
        {"clientId":"550e8400-e29b-41d4-a716-446655440000",
         "clientSecret":"abc123def456","clientName":"Test Client",
         "accountId":"60d5ec49f1b2c8b1f8e4e1a1","scopes":["query","write"]}
        """)])

        let credentials = try await api.mintM2MCredentials(name: "Test Client")

        XCTAssertEqual(credentials.clientId, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(credentials.clientSecret, "abc123def456")
    }

    func testM2MClientUsesClientIdAsItsIdentity() throws {
        let client = try JSONCoding.decoder.decode(M2MClient.self, from: Data("""
        {"clientId":"abc","clientName":"n","scopes":["query"]}
        """.utf8))
        XCTAssertEqual(client.id, "abc")
    }

    func testMintRejectsAResponseWithNoSecret() async throws {
        // The secret is only ever returned at creation, so a response without one
        // leaves nothing usable — storing a blank would fail later and further away.
        let (api, _) = try await signedInAPI(responses: [(201, """
        {"clientId":"c","clientName":"n","scopes":["query"]}
        """)])
        do {
            _ = try await api.mintM2MCredentials(name: "n")
            XCTFail("expected a decoding failure")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .decoding(context: "SDK credentials"))
        }
    }

    func testMintRejectsABlankSecret() async throws {
        let (api, _) = try await signedInAPI(responses: [(201, """
        {"clientId":"c","clientSecret":"","scopes":["query"]}
        """)])
        do {
            _ = try await api.mintM2MCredentials(name: "n")
            XCTFail("expected a decoding failure")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .decoding(context: "SDK credentials"))
        }
    }

    func testMint201IsTreatedAsSuccess() async throws {
        // The endpoint answers 201, not 200.
        let (api, _) = try await signedInAPI(responses: [(201, """
        {"clientId":"c","clientSecret":"s"}
        """)])
        let credentials = try await api.mintM2MCredentials(name: "n")
        XCTAssertEqual(credentials.clientId, "c")
    }

    // MARK: - Listing

    func testListAcceptsAnyOfTheArrayKeysSeenInTheWild() throws {
        for key in ["clients", "m2mClients", "data"] {
            let page = try JSONCoding.decoder.decode(M2MClientListPage.self, from: Data("""
            {"\(key)":[{"clientId":"c1"},{"clientId":"c2"}]}
            """.utf8))
            XCTAssertEqual(page.all.count, 2, "failed for key \(key)")
        }
    }

    func testListedClientsCarryNoSecret() throws {
        // Confirms the reason a listed client cannot be reused for the SDK.
        let page = try JSONCoding.decoder.decode(M2MClientListPage.self, from: Data("""
        {"clients":[{"clientId":"c1","clientName":"n","scopes":["query"]}]}
        """.utf8))
        XCTAssertNil(page.all.first?.clientSecret)
    }
}
