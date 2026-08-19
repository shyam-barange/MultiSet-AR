import ARKit
import Foundation
import MultiSetARCore
import MultiSetKit
import MultiSetSDK
import RealityKit

/// Localizes through `MultiSetSDK`, the framework MultiSet's customers ship.
///
/// This file lives in the App target rather than in `MultiSetARCore` on purpose.
/// `MultiSetConfig` requires a `clientId` and `clientSecret` and exposes no way
/// to inject a pre-minted token, so a Clip that linked it would have to carry a
/// credential. Keeping the conformance here means the framework never enters the
/// Clip's dependency graph — a structural guarantee rather than a convention.
///
/// Everything above `PoseProvider` is shared, so the App and the Clip behave
/// identically despite sourcing poses differently.
final class SDKPoseProvider: NSObject, PoseProvider, @unchecked Sendable {
    let providerName = "SDK"
    let requiresCredentials = true

    private let credentials: M2MCredentials
    private let localizationMode: MultiSetSDK.LocalizationMode
    private let session: ARSession?
    private let anchorEntity: Entity?

    private let lock = NSLock()
    private var pendingContinuation: CheckedContinuation<MultiSetKit.LocalizationResult, any Error>?
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var queryStartedAt: ContinuousClock.Instant?

    init(
        credentials: M2MCredentials,
        localizationMode: MultiSetSDK.LocalizationMode = .multiFrame,
        session: ARSession?,
        anchorEntity: Entity?
    ) {
        self.credentials = credentials
        self.localizationMode = localizationMode
        self.session = session
        self.anchorEntity = anchorEntity
        super.init()
    }

    func prepare(target: MapTarget) async throws {
        var config = MultiSetConfig(
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret
        )
        switch target {
        case .map(let code): config.mapCode = code
        case .mapSet(let code): config.mapSetCode = code
        }
        config.localizationMode = localizationMode
        // The engine owns retry cadence, coaching, and the HUD, so the SDK's own
        // automation and alerts are turned off to avoid two things driving one
        // session and disagreeing.
        config.autoLocalize = false
        config.backgroundLocalization = false
        config.relocalization = false
        config.firstLocalizationUntilSuccess = false
        config.showAlerts = false
        config.meshVisualization = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.withLock { readyContinuation = continuation }
            MultiSet.shared.setARSession(session)
            MultiSet.shared.setParentEntity(anchorEntity)
            MultiSet.shared.initialize(config: config.validated(), callback: self)
        }
    }

    /// The SDK captures its own frames from the ARSession, so the frames the
    /// engine gathered are used only for their timestamps and count.
    func locate(
        frames: [CapturedFrame],
        geoHint: MultiSetKit.GeoCoordinates?
    ) async throws -> MultiSetKit.LocalizationResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pendingContinuation = continuation
                queryStartedAt = ContinuousClock.now
            }
            MultiSet.shared.localize()
        }
    }

    func teardown() async {
        MultiSet.shared.stopLocalization()
        MultiSet.shared.clearMesh()
        MultiSet.shared.release()
        failPending(with: MultiSetError.cancelled)
    }

    private func resumeReady(with result: Result<Void, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { readyContinuation = nil }
            return readyContinuation
        }
        continuation?.resume(with: result)
    }

    private func failPending(with error: any Error) {
        let continuation = lock.withLock { () -> CheckedContinuation<MultiSetKit.LocalizationResult, any Error>? in
            defer { pendingContinuation = nil }
            return pendingContinuation
        }
        continuation?.resume(throwing: error)
    }
}

extension SDKPoseProvider: MultiSetCallback {
    func onSDKReady() {}

    func onAuthenticationSuccess() {
        resumeReady(with: .success(()))
    }

    func onAuthenticationFailure(error: String) {
        resumeReady(with: .failure(MultiSetError.invalidCredentials))
    }

    func onLocalizationSuccess(result: MultiSetSDK.LocalizationResult) {
        let (continuation, startedAt) = lock.withLock {
            () -> (CheckedContinuation<MultiSetKit.LocalizationResult, any Error>?, ContinuousClock.Instant?) in
            defer {
                pendingContinuation = nil
                queryStartedAt = nil
            }
            return (pendingContinuation, queryStartedAt)
        }
        guard let continuation else { return }

        continuation.resume(returning: MultiSetKit.LocalizationResult(
            pose: Pose(
                position: Position(result.position),
                rotation: Rotation(result.rotation)
            ),
            confidence: result.confidence.map(Double.init),
            mapCodes: result.mapCodes.isEmpty ? [result.mapCode] : result.mapCodes,
            geoCoordinates: result.geoCoordinates.map {
                MultiSetKit.GeoCoordinates(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude)
            },
            mode: result.mode == .singleFrame ? .singleFrame : .multiFrame,
            latency: startedAt.map { ContinuousClock.now - $0 } ?? .zero
        ))
    }

    func onLocalizationFailure(error: String) {
        failPending(with: MultiSetError.notLocalized(message: error))
    }

    func onTrackingStateChanged(state: MultiSetSDK.TrackingState) {}
}

/// Object tracking through the SDK, kept separate because it queries object
/// codes rather than a map.
final class SDKObjectTrackingProvider: NSObject, ObjectTrackingProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingContinuation: CheckedContinuation<MultiSetKit.ObjectTrackingResult, any Error>?
    private var queryStartedAt: ContinuousClock.Instant?

    func prepare(objectCodes: [String]) async throws {
        guard var config = MultiSet.shared.config else {
            throw MultiSetError.notLocalized(message: "The SDK wasn't initialised for this session.")
        }
        config.objectCodes = objectCodes
        config.autoObjectTracking = false
        config.backgroundObjectTracking = false
        config.restartObjectTracking = false
        MultiSet.shared.updateConfig(config)
    }

    func track(frame: CapturedFrame) async throws -> MultiSetKit.ObjectTrackingResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                pendingContinuation = continuation
                queryStartedAt = ContinuousClock.now
            }
            MultiSet.shared.startObjectTracking()
        }
    }

    func teardown() async {
        MultiSet.shared.stopObjectTracking()
        MultiSet.shared.clearObjectMeshes()
    }
}
