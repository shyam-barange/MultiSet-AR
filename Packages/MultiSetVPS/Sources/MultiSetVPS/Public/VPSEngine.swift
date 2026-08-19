/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import ARKit
import RealityKit

/// Main entry point for the MultiSet Localization SDK
/// Use the shared instance to initialize and control the SDK
public final class VPSEngine {

    // MARK: - Singleton

    /// Shared instance of the SDK
    public static let shared = VPSEngine()

    // MARK: - Version

    /// SDK version string
    public static let version = "1.15.0"

    // MARK: - State

    /// Whether the SDK has been initialized
    public private(set) var isInitialized: Bool = false

    /// Whether the SDK is authenticated with MultiSet servers
    public private(set) var isAuthenticated: Bool = false

    /// Current configuration (nil if not initialized)
    public private(set) var config: VPSConfig?

    /// The API base URL requests are actually going to.
    ///
    /// Equals `config?.baseURL` once initialized, normalized (no trailing slash), or
    /// the production API if an override was refused as malformed. Useful for showing
    /// which environment a build is pointed at.
    public var activeBaseURL: String {
        return SDKEndpoints.baseURL
    }

    // MARK: - Internal

    /// Callback delegate for SDK events
    internal weak var callback: VPSCallback?

    /// Internal SDK manager that orchestrates all operations
    internal var internalManager: InternalSDKManager?

    // MARK: - Private

    private init() {}

    // MARK: - Public Methods

    /// Initialize the engine.
    /// - Parameters:
    ///   - config: Map, object and behaviour settings. Carries no credentials.
    ///   - callback: Delegate to receive engine events
    ///   - tokenProvider: Supplies the bearer token every request carries. This is
    ///     what replaces the SDK's own clientId/clientSecret exchange, so the engine
    ///     runs as whatever the host is already authenticated as.
    public func initialize(
        config: VPSConfig,
        callback: VPSCallback,
        tokenProvider: any VPSTokenProviding
    ) {
        guard !isInitialized else {
            print("MultiSetVPS >> Already initialized")
            return
        }

        guard config.hasMapConfiguration || config.hasObjectTrackingConfiguration else {
            print("MultiSetVPS >> Error: Missing map or object tracking configuration")
            callback.onAuthenticationFailure(error: "Missing mapCode, mapSetCode, or objectCodes")
            return
        }

        self.config = config.validated()
        self.callback = callback

        // Before anything reaches the network: the auth token below is only valid
        // against the host that issues it, so the environment has to be settled first.
        SDKEndpoints.setBaseURL(config.baseURL)

        // Create internal manager
        self.internalManager = InternalSDKManager(
            config: self.config!,
            callback: callback,
            tokenProvider: tokenProvider
        )

        isInitialized = true
        print("MultiSetVPS >> Initialized with version \(VPSEngine.version)")

        // Notify SDK ready
        callback.onSDKReady()

        // Start authentication
        internalManager?.authenticate()
    }

    /// Update the localization mode
    /// - Parameter mode: The new localization mode to use
    public func setLocalizationMode(_ mode: LocalizationMode) {
        guard var updatedConfig = config else { return }
        updatedConfig.localizationMode = mode
        self.config = updatedConfig
        internalManager?.updateLocalizationMode(mode)
    }

    /// Update the SDK configuration at runtime without re-authenticating.
    ///
    /// Use this to apply changed behavioral settings (auto-localize, confidence,
    /// background intervals, hints, object-tracking behavior, etc.) while the SDK
    /// is already initialized. Changes take effect on the next localization /
    /// tracking run; an in-flight run is unaffected.
    ///
    /// Credentials and `baseURL` are not re-applied — call `release()` then
    /// `initialize(...)` to change either. No-op if the SDK is not yet initialized.
    /// - Parameter config: The updated configuration to apply.
    public func updateConfig(_ config: VPSConfig) {
        guard isInitialized else {
            print("MultiSetVPS >> updateConfig ignored: SDK not initialized")
            return
        }

        // Switching host here would leave the SDK holding a token the new host never
        // issued, so the request would fail in a way that looks nothing like its cause.
        if !SDKEndpoints.isActiveBaseURL(config.baseURL) {
            print("MultiSetVPS >> updateConfig kept baseURL \(activeBaseURL) — call release() then initialize(...) to change the API environment")
        }

        self.config = config.validated()
        internalManager?.updateConfig(self.config!)
        print("MultiSetVPS >> Configuration updated")
    }

    /// Trigger manual localization
    /// Call this when you want to start a localization request
    public func localize() {
        guard isInitialized else {
            print("MultiSetVPS >> Error: SDK not initialized")
            return
        }

        guard isAuthenticated else {
            print("MultiSetVPS >> Error: Not authenticated")
            callback?.onLocalizationFailure(error: "Not authenticated")
            return
        }

        Task { [internalManager] in
            await internalManager?.refreshToken()
            await MainActor.run { internalManager?.startLocalization() }
        }
    }

    /// Stop any ongoing localization process
    public func stopLocalization() {
        internalManager?.stopLocalization()
    }

    /// Release SDK resources
    /// Call this when you're done using the SDK
    public func release() {
        internalManager?.release()
        internalManager = nil
        config = nil
        callback = nil
        isInitialized = false
        isAuthenticated = false
        print("MultiSetVPS >> Released")
    }

    // MARK: - Internal Methods

    /// Called by internal manager when authentication succeeds
    internal func setAuthenticated(_ authenticated: Bool) {
        self.isAuthenticated = authenticated
    }

    // MARK: - AR Session Management

    /// Set the AR session for localization
    /// - Parameter session: The ARSession to use for capturing frames
    public func setARSession(_ session: ARSession?) {
        internalManager?.setARSession(session)
    }

    /// Set the parent entity for mesh rendering
    /// - Parameter entity: The RealityKit entity to parent meshes to
    public func setParentEntity(_ entity: Entity?) {
        internalManager?.setParentEntity(entity)
    }

    /// Set the root entity for object tracking meshes (world-fixed, independent of gizmo)
    /// - Parameter entity: The RealityKit entity to parent object tracking meshes to
    public func setObjectTrackingRootEntity(_ entity: Entity?) {
        internalManager?.setObjectTrackingRootEntity(entity)
    }

    /// Set handler for gizmo position updates after localization
    /// - Parameter handler: Callback with position and rotation
    public func setGizmoUpdateHandler(_ handler: @escaping (SIMD3<Float>, simd_quatf) -> Void) {
        internalManager?.setGizmoUpdateHandler(handler)
    }

    /// Show or hide the gizmo (RGB axes + origin sphere)
    public func setGizmoVisible(_ visible: Bool) {
        gizmoEntity?.isEnabled = visible
    }

    /// Internal reference to gizmo entity, set by VPSARView
    internal var gizmoEntity: Entity?

    /// Forward AR tracking state changes to object tracking manager for re-tracking
    internal func handleARTrackingStateChange(_ trackingState: ARCamera.TrackingState) {
        internalManager?.handleARTrackingStateChange(trackingState)
    }

    /// Forward AR session interruptions so pose consistency stops trusting a
    /// session frame that may have moved while the app was suspended
    internal func handleARSessionInterrupted() {
        internalManager?.handleARSessionInterrupted()
    }

    /// Forward a deliberate world-origin reset, which invalidates the session frame outright
    internal func handleARWorldOriginReset() {
        internalManager?.handleARWorldOriginReset()
    }

    /// Forget the pose the false-positive check measures new responses against, so the
    /// next successful response is trusted and becomes the new reference.
    ///
    /// The check normally maintains this by itself. Call it when the user asks to start
    /// over — a "reset" control, or a run of `onLocalizationFalsePositive` calls the user
    /// believes are wrong — since the very first fix after this is accepted unchecked.
    public func resetPoseConsistencyReference() {
        internalManager?.resetPoseConsistencyReference()
    }

    // MARK: - GPS Control

    /// Start GPS updates for geo-pose localization
    public func startGpsUpdates() {
        internalManager?.startGpsUpdates()
    }

    /// Stop GPS updates
    public func stopGpsUpdates() {
        internalManager?.stopGpsUpdates()
    }

    // MARK: - Object Tracking

    /// Start object tracking with configured object codes
    public func startObjectTracking() {
        guard isInitialized else {
            print("MultiSetVPS >> Error: SDK not initialized")
            return
        }
        guard isAuthenticated else {
            print("MultiSetVPS >> Error: Not authenticated")
            callback?.onObjectTrackingFailure(error: "Not authenticated")
            return
        }
        Task { [internalManager] in
            await internalManager?.refreshToken()
            await MainActor.run { internalManager?.startObjectTracking() }
        }
    }

    /// Stop object tracking
    public func stopObjectTracking() {
        internalManager?.stopObjectTracking()
    }

    /// Clear all tracked object meshes
    public func clearObjectMeshes() {
        internalManager?.clearObjectMeshes()
    }

    /// Whether object tracking has succeeded at least once
    public var hasTrackedObject: Bool {
        return internalManager?.hasTrackedObject ?? false
    }

    /// Whether object tracking API is in progress
    public var isObjectTrackingActive: Bool {
        return internalManager?.isObjectTrackingActive ?? false
    }

    // MARK: - Mesh Control

    /// Clear loaded mesh from the scene
    public func clearMesh() {
        internalManager?.clearMesh()
    }

    // MARK: - State Accessors

    /// Whether localization is currently in progress
    public var isLocalizing: Bool {
        return internalManager?.isLocalizing ?? false
    }

    /// Whether localization has succeeded at least once
    public var hasLocalized: Bool {
        return internalManager?.hasLocalized ?? false
    }

    /// Whether the localization overlay is showing (capturing frames or waiting for API)
    public var isShowingOverlay: Bool {
        return internalManager?.isShowingOverlay ?? false
    }

    /// Whether frames are currently being captured
    public var isCapturingFrames: Bool {
        return internalManager?.isCapturingFrames ?? false
    }

    /// Current authentication token (for advanced use cases)
    public var authToken: String? {
        return internalManager?.authToken
    }
}
