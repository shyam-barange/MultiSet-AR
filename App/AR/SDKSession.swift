import ARKit
import Combine
import MultiSetKit
import MultiSetVPS
import MultiSetUI
import SwiftUI

/// Drives `MultiSetSDK` for the developer-facing localization and object-tracking
/// screens, and republishes its callbacks as observable state.
///
/// The SDK owns the AR session for these flows. `MultiSetARView` installs the
/// SDK's own `ARSession` delegate, creates the gizmo anchor that map meshes are
/// parented to, and a separate world-fixed anchor for object meshes — so the mesh
/// pipeline only works if the SDK is allowed to set the scene up itself. That is
/// why these screens use `MultiSetARView` rather than the app's own `ARSceneHost`.
///
/// `VPSEngine.shared` is a singleton that refuses a second `initialize`, so a
/// session must be released before another map or object can be configured.
@MainActor
final class SDKSession: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case authenticating
        case ready
        /// Missing or rejected credentials, or a configuration the SDK refused.
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    enum MeshState: Equatable {
        case none
        case loading
        case loaded(code: String)
        case failed(String)
    }

    /// What the session is configured to do. Localization and object tracking are
    /// separate because the SDK validates a different part of the config for each.
    enum Target: Equatable {
        case map(code: String, mode: MultiSetVPS.LocalizationMode)
        case mapSet(code: String, mode: MultiSetVPS.LocalizationMode)
        case objects(codes: [String])

        var localizationMode: MultiSetVPS.LocalizationMode {
            switch self {
            case .map(_, let mode), .mapSet(_, let mode): mode
            case .objects: .singleFrame
            }
        }

        var displayCode: String {
            switch self {
            case .map(let code, _), .mapSet(let code, _): code
            case .objects(let codes): codes.joined(separator: ", ")
            }
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle

    /// True once `initialize` has run and the SDK holds an internal manager.
    ///
    /// `MultiSetARView` hands the SDK its AR session, mesh parent, object anchor and
    /// gizmo handler from `makeUIView` — and every one of those forwards through
    /// `internalManager?`, so they are silently dropped if the SDK is not initialized
    /// yet. The view must therefore not exist until this is true. The SDK documents
    /// the requirement on `MultiSetARView` itself.
    @Published private(set) var isSDKInitialized = false
    @Published private(set) var isTrackingNormal = false
    @Published private(set) var lastResult: MultiSetVPS.LocalizationResult?
    @Published private(set) var mapMesh: MeshState = .none
    @Published private(set) var objectMesh: MeshState = .none
    @Published private(set) var trackedObjectCode: String?
    @Published private(set) var trackedObjectConfidence: Double?
    @Published private(set) var falsePositive: FalsePositiveInfo?
    @Published private(set) var failureMessage: String?
    @Published var toast: MSToast?

    /// Counters for the pose readout. The SDK reports outcomes, not attempts, so
    /// these are maintained here.
    @Published private(set) var queryCount = 0
    @Published private(set) var successCount = 0
    @Published private(set) var falsePositiveCount = 0
    @Published private(set) var lastLatency: Duration?

    /// Mirrors of the SDK's own polled state, which it exposes as plain properties
    /// rather than as a publisher.
    @Published private(set) var isLocalizing = false
    @Published private(set) var isShowingOverlay = false
    @Published private(set) var isCapturingFrames = false
    @Published private(set) var hasLocalized = false
    @Published private(set) var isObjectTrackingActive = false
    @Published private(set) var hasTrackedObject = false

    private var target: Target?
    private var pollTask: Task<Void, Never>?
    private var queryStartedAt: ContinuousClock.Instant?

    // MARK: - Lifecycle

    /// Configures and authenticates the SDK. Releases any previous session first,
    /// because `VPSEngine.shared.initialize` is a no-op while already initialized.
    func start(
        target: Target,
        tokenProvider: any VPSTokenProviding,
        environment: APIEnvironment,
        settings: SDKSettings = .init()
    ) {
        stop()

        self.target = target
        phase = .authenticating

        // No credentials here. The engine asks `tokenProvider` for a bearer token,
        // so it runs as whoever the app is already signed in as.
        var config = VPSConfig(baseURL: Self.sdkBaseURL(for: environment))

        switch target {
        case .map(let code, let mode):
            config.mapCode = code
            config.localizationMode = mode
        case .mapSet(let code, let mode):
            config.mapSetCode = code
            config.localizationMode = mode
        case .objects(let codes):
            config.objectCodes = codes
        }

        // The screen drives capture explicitly and renders its own status, so the
        // SDK's alerts and auto-start are off. Mesh visualisation stays on: it is
        // what downloads the map or object mesh and puts it in the scene.
        config.meshVisualization = true
        config.showAlerts = false
        config.autoLocalize = settings.autoLocalize
        config.autoObjectTracking = settings.autoObjectTracking
        config.backgroundLocalization = settings.backgroundLocalization
        config.relocalization = settings.relocalization
        config.firstLocalizationUntilSuccess = settings.retryUntilFirstSuccess
        config.numberOfFrames = settings.frameCount
        config.frameCaptureIntervalMs = settings.frameIntervalMilliseconds
        config.confidenceCheck = settings.confidenceThreshold != nil
        config.confidenceThreshold = settings.confidenceThreshold ?? 0.3
        config.poseConsistencyCheck = settings.poseConsistencyCheck
        config.poseConsistencyThreshold = settings.poseConsistencyThreshold
        config.passGeoPose = settings.passGeoPose
        config.geoCoordinatesInResponse = settings.passGeoPose
        config.imageQuality = settings.imageQuality

        VPSEngine.shared.initialize(
            config: config.validated(),
            callback: self,
            tokenProvider: tokenProvider
        )
        // initialize() creates the internal manager synchronously, so the AR view is
        // safe to build from here on — authentication completing is a separate,
        // later event.
        isSDKInitialized = VPSEngine.shared.isInitialized
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        VPSEngine.shared.stopLocalization()
        VPSEngine.shared.stopObjectTracking()
        VPSEngine.shared.stopGpsUpdates()
        if VPSEngine.shared.isInitialized {
            VPSEngine.shared.release()
        }
        isSDKInitialized = false
        phase = .idle
        resetObservedState()
    }

    // MARK: - Actions

    func localize() {
        guard phase.isReady else { return }
        queryStartedAt = ContinuousClock.now
        queryCount += 1
        failureMessage = nil
        falsePositive = nil
        if case .none = mapMesh {
            mapMesh = .loading
        }
        VPSEngine.shared.localize()
    }

    func startObjectTracking() {
        guard phase.isReady else { return }
        queryStartedAt = ContinuousClock.now
        queryCount += 1
        failureMessage = nil
        VPSEngine.shared.startObjectTracking()
    }

    /// Discards the current fix and the pose the false-positive check measures
    /// against, so the next response is trusted as the new reference.
    func resetWorldOrigin() {
        VPSEngine.shared.stopLocalization()
        VPSEngine.shared.clearMesh()
        VPSEngine.shared.resetPoseConsistencyReference()
        lastResult = nil
        mapMesh = .none
        falsePositive = nil
        hasLocalized = false
        toast = MSToast(message: "World origin reset", tone: .info)
    }

    func resetObjectTracking() {
        VPSEngine.shared.stopObjectTracking()
        VPSEngine.shared.clearObjectMeshes()
        trackedObjectCode = nil
        trackedObjectConfidence = nil
        objectMesh = .none
        hasTrackedObject = false
        toast = MSToast(message: "Tracking reset", tone: .info)
    }

    func clearFailure() {
        failureMessage = nil
    }

    func clearFalsePositive() {
        falsePositive = nil
    }

    func setGizmoVisible(_ visible: Bool) {
        VPSEngine.shared.setGizmoVisible(visible)
    }

    /// The frame count actually in force, after the SDK's own clamping.
    var frameCount: Int { VPSEngine.shared.config?.numberOfFrames ?? 4 }

    var sdkVersion: String { VPSEngine.version }
    var activeBaseURL: String { VPSEngine.shared.activeBaseURL }
    var targetCode: String { target?.displayCode ?? "—" }

    /// The pose readout's view of the session.
    var readout: PoseReadoutData {
        PoseReadoutData(
            position: lastResult.map { (($0.position.x), ($0.position.y), ($0.position.z)) },
            rotation: lastResult.map {
                ($0.rotation.imag.x, $0.rotation.imag.y, $0.rotation.imag.z, $0.rotation.real)
            },
            confidence: lastResult?.confidence,
            latency: lastLatency,
            framesSubmitted: 0,
            queryCount: queryCount,
            mapCode: lastResult?.mapCode ?? targetCode,
            trackingState: isTrackingNormal ? "normal" : "limited"
        )
    }

    // MARK: - Private

    /// The engine's base URL includes the version path, unlike `APIEnvironment`.
    static func sdkBaseURL(for environment: APIEnvironment) -> String {
        environment.baseURL.appendingPathComponent("v1").absoluteString
    }

    private func startPolling() {
        pollTask?.cancel()
        // The SDK exposes capture and overlay progress as plain properties, so the
        // only way to drive UI from them is to sample them.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.isLocalizing = VPSEngine.shared.isLocalizing
                self.isShowingOverlay = VPSEngine.shared.isShowingOverlay
                self.isCapturingFrames = VPSEngine.shared.isCapturingFrames
                self.hasLocalized = VPSEngine.shared.hasLocalized
                self.isObjectTrackingActive = VPSEngine.shared.isObjectTrackingActive
                self.hasTrackedObject = VPSEngine.shared.hasTrackedObject
            }
        }
    }

    private func resetObservedState() {
        isLocalizing = false
        isShowingOverlay = false
        isCapturingFrames = false
        hasLocalized = false
        isObjectTrackingActive = false
        hasTrackedObject = false
        lastResult = nil
        mapMesh = .none
        objectMesh = .none
        trackedObjectCode = nil
        trackedObjectConfidence = nil
        falsePositive = nil
        failureMessage = nil
        queryCount = 0
        successCount = 0
        falsePositiveCount = 0
        lastLatency = nil
    }

    private func recordLatency() {
        guard let start = queryStartedAt else { return }
        lastLatency = ContinuousClock.now - start
        queryStartedAt = nil
    }
}

/// Behavioural knobs surfaced to the developer. Defaults match the SDK's own,
/// except that alerts and auto-start are handled by the screen.
struct SDKSettings: Equatable {
    var autoLocalize = false
    var autoObjectTracking = false
    var backgroundLocalization = false
    var relocalization = true
    var retryUntilFirstSuccess = false
    var frameCount = 4
    var frameIntervalMilliseconds = 500
    var confidenceThreshold: Float?
    var poseConsistencyCheck = true
    var poseConsistencyThreshold: Float = 5
    var passGeoPose = false
    var imageQuality = 90
}

// MARK: - VPSCallback

extension SDKSession: VPSCallback {
    nonisolated func onSDKReady() {}

    nonisolated func onAuthenticationSuccess() {
        Task { @MainActor in
            phase = .ready
        }
    }

    nonisolated func onAuthenticationFailure(error: String) {
        Task { @MainActor in
            phase = .failed(error)
        }
    }

    nonisolated func onLocalizationSuccess(result: MultiSetVPS.LocalizationResult) {
        Task { @MainActor in
            recordLatency()
            lastResult = result
            successCount += 1
            hasLocalized = true
            failureMessage = nil
            falsePositive = nil
            toast = MSToast(message: "Localized in \(result.mapCode)", tone: .success)
        }
    }

    nonisolated func onLocalizationFailure(error: String) {
        Task { @MainActor in
            recordLatency()
            failureMessage = Self.readableLocalizationError(error)
            if case .loading = mapMesh {
                mapMesh = .none
            }
        }
    }

    /// The server found a pose but the SDK discarded it, because it contradicts the
    /// device's own motion. Nothing in the scene moved, so this is neither a success
    /// nor a failure and has to be surfaced on its own.
    nonisolated func onLocalizationFalsePositive(info: FalsePositiveInfo) {
        Task { @MainActor in
            recordLatency()
            falsePositive = info
            falsePositiveCount += 1
        }
    }

    nonisolated func onTrackingStateChanged(state: MultiSetVPS.TrackingState) {
        Task { @MainActor in
            isTrackingNormal = state == .tracking
        }
    }

    nonisolated func onMeshLoaded(mapCode: String) {
        Task { @MainActor in
            mapMesh = .loaded(code: mapCode)
        }
    }

    nonisolated func onMeshLoadError(error: String) {
        Task { @MainActor in
            mapMesh = .failed(error)
        }
    }

    nonisolated func onObjectTrackingSuccess(objectCode: String, confidence: Double) {
        Task { @MainActor in
            recordLatency()
            trackedObjectCode = objectCode
            trackedObjectConfidence = confidence
            successCount += 1
            hasTrackedObject = true
            failureMessage = nil
            if case .none = objectMesh {
                objectMesh = .loading
            }
            toast = MSToast(message: "Tracking \(objectCode)", tone: .success)
        }
    }

    nonisolated func onObjectTrackingFailure(error: String) {
        Task { @MainActor in
            recordLatency()
            failureMessage = Self.readableTrackingError(error)
        }
    }

    nonisolated func onObjectMeshLoaded(objectCode: String) {
        Task { @MainActor in
            objectMesh = .loaded(code: objectCode)
        }
    }

    /// The SDK reports transport-level detail; these say what to do next instead.
    static func readableLocalizationError(_ error: String) -> String {
        let lower = error.lowercased()
        if lower.contains("pose not found") {
            return "No match in this map. Point at a well-lit, textured area and try again."
        }
        if lower.contains("low confidence") {
            return "The match was too weak to trust. Move to a different angle and try again."
        }
        if lower.contains("no frames captured") {
            return "No camera frames were captured. Check nothing is covering the lens."
        }
        if lower.contains("api error") || lower.contains("http") {
            return "Couldn't reach MultiSet. Check your connection and try again."
        }
        if lower.contains("missing pose data") {
            return "The response was incomplete. Try again."
        }
        return error
    }

    static func readableTrackingError(_ error: String) -> String {
        let lower = error.lowercased()
        if lower.contains("object not found") {
            return "That object wasn't recognised. Fill more of the frame with it and try again."
        }
        if lower.contains("low confidence") {
            return "The match was too weak to trust. Try another angle or move closer."
        }
        if lower.contains("api error") || lower.contains("http") {
            return "Couldn't reach MultiSet. Check your connection and try again."
        }
        return error
    }
}
