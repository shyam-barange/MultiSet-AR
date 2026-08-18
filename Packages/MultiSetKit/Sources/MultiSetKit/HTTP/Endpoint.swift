import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// A request described independently of how it is sent, so the auth header can
/// be attached late and the whole thing stays testable.
struct Endpoint: Sendable {
    var method: HTTPMethod = .get
    var path: String
    var query: [String: String?] = [:]
    /// Repeated query items, for parameters the API accepts more than once.
    var repeatedQuery: [(String, String)] = []
    var body: Data?
    var contentType: String?
    var accept: String = "application/json"
    var timeout: TimeInterval = 120
    /// Set for `/v1/m2m/token`, which authenticates with Basic rather than Bearer.
    var basicAuthorization: String?
    /// Extra headers. `/v1/m2m/token` also wants `Username` and `Password`.
    var additionalHeaders: [String: String] = [:]
    var requiresAuthentication: Bool = true

    func urlRequest(baseURL: URL, bearerToken: String?) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw MultiSetError.decoding(context: "request URL for \(path)")
        }

        var items = query.compactMap { key, value in
            value.map { URLQueryItem(name: key, value: $0) }
        }
        items.append(contentsOf: repeatedQuery.map { URLQueryItem(name: $0.0, value: $0.1) })
        components.queryItems = items.isEmpty ? nil : items.sorted { $0.name < $1.name }

        guard let url = components.url else {
            throw MultiSetError.decoding(context: "request URL for \(path)")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let basicAuthorization {
            request.setValue("Basic \(basicAuthorization)", forHTTPHeaderField: "Authorization")
        } else if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

extension Endpoint {
    static func json<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        requiresAuthentication: Bool = true
    ) throws -> Endpoint {
        Endpoint(
            method: method,
            path: path,
            body: try JSONCoding.encoder.encode(body),
            contentType: "application/json",
            requiresAuthentication: requiresAuthentication
        )
    }

    static func multipart(_ path: String, form: MultipartFormData) -> Endpoint {
        Endpoint(
            method: .post,
            path: path,
            body: form.finalized(),
            contentType: form.contentType
        )
    }

    /// Standard pagination. Maps use `query`, MapSets use `search`, Content
    /// Spaces use `name` — the caller supplies the right key.
    static func paged(
        _ path: String,
        page: Int,
        limit: Int,
        searchKey: String? = nil,
        searchText: String? = nil,
        extra: [String: String?] = [:]
    ) -> Endpoint {
        var query: [String: String?] = ["page": "\(page)", "limit": "\(limit)"]
        if let searchKey, let searchText, !searchText.isEmpty {
            query[searchKey] = searchText
        }
        query.merge(extra) { _, new in new }
        return Endpoint(path: path, query: query)
    }
}
