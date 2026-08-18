import XCTest
@testable import MultiSetKit

final class MultipartFormDataTests: XCTestCase {
    private func body(_ form: MultipartFormData) -> String {
        String(decoding: form.finalized(), as: UTF8.self)
    }

    func testTextFieldIsEncodedWithDisposition() {
        var form = MultipartFormData(boundary: "B")
        form.append("MAP_A", name: "mapCode")
        XCTAssertEqual(
            body(form),
            "--B\r\nContent-Disposition: form-data; name=\"mapCode\"\r\n\r\nMAP_A\r\n--B--\r\n"
        )
    }

    func testBooleanIsEncodedAsLowercaseString() {
        var form = MultipartFormData(boundary: "B")
        form.append(true, name: "isRightHanded")
        XCTAssertTrue(body(form).contains("\r\n\r\ntrue\r\n"))
        var negative = MultipartFormData(boundary: "B")
        negative.append(false, name: "isRightHanded")
        XCTAssertTrue(body(negative).contains("\r\n\r\nfalse\r\n"))
    }

    func testFileFieldCarriesFilenameAndMIMEType() {
        var form = MultipartFormData(boundary: "B")
        form.append(Data([0xFF, 0xD8]), name: "queryImage", filename: "image.JPG")
        let encoded = body(form)
        XCTAssertTrue(encoded.contains("name=\"queryImage\"; filename=\"image.JPG\""))
        XCTAssertTrue(encoded.contains("Content-Type: image/jpeg"))
    }

    func testFinalizedIsIdempotentSoTheTerminatorIsNeverDoubled() {
        var form = MultipartFormData(boundary: "B")
        form.append("v", name: "k")
        XCTAssertEqual(form.finalized(), form.finalized())
        XCTAssertEqual(body(form).components(separatedBy: "--B--").count - 1, 1)
    }

    func testFieldOrderIsPreservedForPairedFrameFields() {
        // The multi-image endpoint pairs queryImage_N with metadata_N, so order matters.
        var form = MultipartFormData(boundary: "B")
        form.append(Data([0x01]), name: "queryImage_0", filename: "image_0.JPG")
        form.append(#"{"x":0}"#, name: "metadata_0")
        form.append(Data([0x02]), name: "queryImage_1", filename: "image_1.JPG")
        form.append(#"{"x":1}"#, name: "metadata_1")

        let encoded = body(form)
        let indices = ["queryImage_0", "metadata_0", "queryImage_1", "metadata_1"]
            .compactMap { encoded.range(of: $0)?.lowerBound }
        XCTAssertEqual(indices.count, 4)
        XCTAssertEqual(indices, indices.sorted())
    }
}

final class QueryFrameMetadataTests: XCTestCase {
    func testMetadataFlattensPoseWithQPrefixedRotationKeys() throws {
        let frame = QueryFrame(
            jpegData: Data(),
            pose: Pose(
                position: Position(x: -0.005, y: 1.128, z: -0.021),
                rotation: Rotation(x: -0.010, y: 0.100, z: 0.002, w: -0.995)
            )
        )
        let json = try XCTUnwrap(frame.metadataJSON)
        // The endpoint expects x/y/z with qx/qy/qz/qw in one flat object.
        for key in ["\"x\":", "\"y\":", "\"z\":", "\"qx\":", "\"qy\":", "\"qz\":", "\"qw\":"] {
            XCTAssertTrue(json.contains(key), "missing \(key) in \(json)")
        }
        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.hasSuffix("}"))
    }

    func testMetadataIsAbsentWhenNoPoseWasCaptured() {
        XCTAssertNil(QueryFrame(jpegData: Data()).metadataJSON)
    }
}

final class EndpointTests: XCTestCase {
    private let baseURL = URL(string: "https://api.multiset.ai")!

    func testQueryItemsAreSortedForStableURLs() throws {
        let endpoint = Endpoint(path: "/v1/vps/map", query: ["page": "1", "limit": "50", "query": "aisle"])
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: nil)
        XCTAssertEqual(request.url?.query, "limit=50&page=1&query=aisle")
    }

    func testNilQueryValuesAreOmitted() throws {
        let endpoint = Endpoint(path: "/v1/vps/map", query: ["page": "1", "status": nil])
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: nil)
        XCTAssertEqual(request.url?.query, "page=1")
    }

    func testRepeatedQueryItemsArePreserved() throws {
        let endpoint = Endpoint(
            path: "/v1/vps/object",
            repeatedQuery: [("objectCode", "OBJ_A"), ("objectCode", "OBJ_B")]
        )
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: nil)
        XCTAssertEqual(request.url?.query, "objectCode=OBJ_A&objectCode=OBJ_B")
    }

    func testBearerTokenIsAttachedWhenPresent() throws {
        let endpoint = Endpoint(path: "/v1/user")
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: "tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testBasicAuthorizationTakesPrecedenceOverBearer() throws {
        let endpoint = Endpoint(path: "/v1/m2m/token", basicAuthorization: "abc")
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: "tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic abc")
    }

    func testSearchKeyIsCallerSuppliedBecauseEntitiesDisagree() throws {
        // Maps use `query`, MapSets use `search`, Content Spaces use `name`.
        let maps = Endpoint.paged("/v1/vps/map", page: 1, limit: 10, searchKey: "query", searchText: "a")
        let sets = Endpoint.paged("/v1/vps/map-set", page: 1, limit: 10, searchKey: "search", searchText: "a")
        let spaces = Endpoint.paged("/v1/content-space", page: 1, limit: 10, searchKey: "name", searchText: "a")
        XCTAssertEqual(maps.query["query"], "a")
        XCTAssertEqual(sets.query["search"], "a")
        XCTAssertEqual(spaces.query["name"], "a")
    }

    func testEmptySearchTextIsNotSentAsAFilter() {
        let endpoint = Endpoint.paged("/v1/vps/map", page: 1, limit: 10, searchKey: "query", searchText: "")
        XCTAssertNil(endpoint.query["query"] ?? nil)
    }
}

final class HTTPStatusMappingTests: XCTestCase {
    private func mapped(_ status: Int, body: String = "{}", headers: [String: String] = [:]) -> MultiSetError {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.multiset.ai/v1/x")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return HTTPClient.mapStatus(response, data: Data(body.utf8), context: "map")
    }

    func testStatusCodesMapToSpecificErrors() {
        XCTAssertEqual(mapped(401), .unauthorized)
        XCTAssertEqual(mapped(403), .forbidden)
        XCTAssertEqual(mapped(404), .notFound(resource: "map"))
        XCTAssertEqual(mapped(429, headers: ["Retry-After": "30"]), .rateLimited(retryAfter: 30))
        XCTAssertEqual(mapped(429), .rateLimited(retryAfter: nil))
    }

    func testServerMessageIsSurfacedToTheUser() {
        XCTAssertEqual(
            mapped(500, body: #"{"error":"E","message":"Upstream timeout"}"#),
            .server(status: 500, message: "Upstream timeout")
        )
    }

    func testErrorKeyIsUsedWhenMessageIsAbsent() {
        XCTAssertEqual(mapped(502, body: #"{"error":"bad_gateway"}"#), .server(status: 502, message: "bad_gateway"))
    }

    func testTransportFailuresDistinguishOfflineFromOtherFaults() {
        XCTAssertEqual(HTTPClient.mapTransportFailure(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(HTTPClient.mapTransportFailure(URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(HTTPClient.mapTransportFailure(URLError(.cancelled)), .cancelled)
        if case .network = HTTPClient.mapTransportFailure(URLError(.timedOut)) {} else {
            XCTFail("timeout should map to .network")
        }
    }

    func testEveryErrorCaseHasAnActionableMessage() {
        let cases: [MultiSetError] = [
            .unauthorized, .forbidden, .offline, .notFound(resource: "map"),
            .rateLimited(retryAfter: 5), .rateLimited(retryAfter: nil),
            .notLocalized(message: nil), .notLocalized(message: "Could not localize"),
            .network(code: .timedOut, description: "timed out"),
            .server(status: 500, message: nil), .decoding(context: "maps"),
            .experienceUnavailable(.unknownCode), .experienceUnavailable(.deactivated),
            .experienceUnavailable(.mapProcessing), .experienceUnavailable(.expired),
            .experienceUnavailable(.deviceUnsupported),
            .cameraAccessDenied, .arUnsupported, .invalidCredentials, .cancelled
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "\(error) has no message")
            XCTAssertFalse(
                message.lowercased().contains("something went wrong"),
                "\(error) uses a non-actionable message"
            )
        }
    }

    func testRetryabilityMatchesWhetherRetryingCouldHelp() {
        XCTAssertTrue(MultiSetError.offline.isRetryable)
        XCTAssertTrue(MultiSetError.server(status: 503, message: nil).isRetryable)
        XCTAssertFalse(MultiSetError.server(status: 400, message: nil).isRetryable)
        XCTAssertFalse(MultiSetError.unauthorized.isRetryable)
        XCTAssertFalse(MultiSetError.experienceUnavailable(.deactivated).isRetryable)
    }
}
