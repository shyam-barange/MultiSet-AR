import Foundation

/// Builds a `multipart/form-data` body. The localization endpoints are all
/// multipart, and field ordering matters to the server for the `queryImage_N` /
/// `metadata_N` pairs, so fields are appended in call order.
struct MultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "multiset.\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func append(_ value: String, name: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    mutating func append(_ value: Bool, name: String) {
        append(value ? "true" : "false", name: name)
    }

    mutating func append(
        _ data: Data,
        name: String,
        filename: String,
        mimeType: String = "image/jpeg"
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    /// Closes the body. Calling this twice would emit two terminators, so the
    /// result is returned rather than mutating in place.
    func finalized() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n")
        return result
    }

    var byteCount: Int { body.count + boundary.count + 6 }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
