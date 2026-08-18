import Foundation
import MultiSetKit

/// Where a VPS pose comes from.
///
/// Two conformances exist. `RESTPoseProvider` talks to the query endpoints
/// directly and works with any `AuthPrincipal`, including the App Clip's
/// anonymous experience token. `SDKPoseProvider` lives in the App target and
/// wraps `MultiSetSDK`, which requires a clientId and clientSecret and so can
/// never be used by the Clip.
///
/// Everything above this protocol — state machine, HUD, path rendering — is
/// shared, so the two targets cannot drift apart in behaviour.
public protocol PoseProvider: AnyObject, Sendable {
    /// Human-readable name for the diagnostics HUD, e.g. "REST" or "SDK".
    var providerName: String { get }

    /// Whether this provider needs developer credentials to run.
    var requiresCredentials: Bool { get }

    func prepare(target: MapTarget) async throws

    /// Submits captured frames and returns a pose, or throws `.notLocalized`
    /// when the server could not place them.
    func locate(frames: [CapturedFrame], geoHint: GeoCoordinates?) async throws -> LocalizationResult

    func teardown() async
}

/// Object tracking is separate because it queries object codes, not a map.
public protocol ObjectTrackingProvider: AnyObject, Sendable {
    func prepare(objectCodes: [String]) async throws
    func track(frame: CapturedFrame) async throws -> ObjectTrackingResult
    func teardown() async
}
