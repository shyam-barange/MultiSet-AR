import Foundation

/// Seam for tests — a `URLSession` in production, a stub in unit tests.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

struct ServerErrorBody: Decodable {
    var error: String?
    var message: String?
}

/// Sends `Endpoint`s, maps failures onto `MultiSetError`, and never retries on
/// its own — retry policy belongs to the caller that knows the user's intent.
struct HTTPClient: Sendable {
    let baseURL: URL
    let transport: any HTTPTransport

    init(baseURL: URL, transport: any HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.transport = transport
    }

    func send<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type,
        bearerToken: String? = nil,
        context: String
    ) async throws -> Response {
        let data = try await sendForData(endpoint, bearerToken: bearerToken, context: context)
        do {
            return try JSONCoding.decoder.decode(Response.self, from: data)
        } catch {
            throw MultiSetError.decoding(context: context)
        }
    }

    @discardableResult
    func sendForData(
        _ endpoint: Endpoint,
        bearerToken: String? = nil,
        context: String
    ) async throws -> Data {
        let request = try endpoint.urlRequest(baseURL: baseURL, bearerToken: bearerToken)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            throw Self.mapTransportFailure(error)
        } catch is CancellationError {
            throw MultiSetError.cancelled
        }

        guard let http = response as? HTTPURLResponse else {
            throw MultiSetError.decoding(context: context)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapStatus(http, data: data, context: context)
        }
        return data
    }

    static func mapTransportFailure(_ error: URLError) -> MultiSetError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
            .offline
        case .cancelled:
            .cancelled
        default:
            .network(code: error.code, description: error.localizedDescription)
        }
    }

    static func mapStatus(_ response: HTTPURLResponse, data: Data, context: String) -> MultiSetError {
        let body = try? JSONCoding.decoder.decode(ServerErrorBody.self, from: data)
        let message = body?.message ?? body?.error

        switch response.statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound(resource: context)
        case 429:
            let retryAfter = (response.value(forHTTPHeaderField: "Retry-After"))
                .flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(status: response.statusCode, message: message)
        }
    }
}
