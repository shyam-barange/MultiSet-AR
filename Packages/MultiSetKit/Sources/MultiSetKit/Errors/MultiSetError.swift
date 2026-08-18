import Foundation

/// Why a hosted experience cannot run. Maps the App Clip's failure cases to a
/// closed set so the UI is a `switch`, not ad-hoc string matching.
public enum ExperienceUnavailableReason: Sendable, Equatable {
    case unknownCode
    case deactivated
    case mapProcessing
    case expired
    case deviceUnsupported
}

public enum MultiSetError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case offline
    case notFound(resource: String)
    case rateLimited(retryAfter: TimeInterval?)
    case notLocalized(message: String?)
    case network(code: URLError.Code, description: String)
    case server(status: Int, message: String?)
    case decoding(context: String)
    case experienceUnavailable(ExperienceUnavailableReason)
    case cameraAccessDenied
    case arUnsupported
    case invalidCredentials
    case cancelled
}

extension MultiSetError: LocalizedError {
    /// Every case states what happened and what to do next. No "Something went wrong."
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your session expired. Sign in again to continue."
        case .forbidden:
            "This account doesn't have access to that. Check your plan in the developer portal."
        case .offline:
            "You're offline. VPS localization needs a connection — reconnect and try again."
        case .notFound(let resource):
            "That \(resource) no longer exists. It may have been deleted."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Too many requests. Try again in \(Int(retryAfter.rounded())) seconds."
            } else {
                "Too many requests. Wait a moment and try again."
            }
        case .notLocalized(let message):
            message ?? "Couldn't find your position. Point the camera at walls and fixed features, not the floor."
        case .network(_, let description):
            "The connection failed: \(description). Try again."
        case .server(let status, let message):
            message ?? "The MultiSet service returned an error (\(status)). Try again shortly."
        case .decoding(let context):
            "The MultiSet service sent something unexpected while loading \(context). Update the app if this continues."
        case .experienceUnavailable(let reason):
            switch reason {
            case .unknownCode: "This code isn't valid anymore."
            case .deactivated: "This experience has ended."
            case .mapProcessing: "This location isn't ready yet. Check back shortly."
            case .expired: "This session expired. Reopen the code to start again."
            case .deviceUnsupported: "This experience needs a device with ARKit support."
            }
        case .cameraAccessDenied:
            "MultiSet AR needs the camera to recognize your surroundings. Turn it on in Settings."
        case .arUnsupported:
            "This device doesn't support ARKit, which AR positioning requires."
        case .invalidCredentials:
            "Those credentials weren't accepted. Check them in the developer portal."
        case .cancelled:
            "Cancelled."
        }
    }

    /// True when retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .offline, .network, .rateLimited, .notLocalized: true
        case .server(let status, _): status >= 500
        default: false
        }
    }
}
