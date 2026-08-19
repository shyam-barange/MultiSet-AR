/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import ARKit
import RealityKit

/// Internal manager that orchestrates all SDK operations
/// This class is not exposed to SDK users
internal final class InternalSDKManager {

    // MARK: - Properties

    private var config: VPSConfig
    private weak var callback: VPSCallback?

    private let tokenProvider: any VPSTokenProviding
    private let tokenBox = VPSTokenBox()
    private var localizationManager: LocalizationManager?
    private var objectTrackingManager: ObjectTrackingManager?
    private var gpsHandler: GpsCoordinateHandler?

    private var arSession: ARSession?
    private var parentEntity: Entity?
    private var objectTrackingRootEntity: Entity?
    private var gizmoUpdateHandler: ((SIMD3<Float>, simd_quatf) -> Void)?

    // MARK: - Initialization

    init(config: VPSConfig, callback: VPSCallback, tokenProvider: any VPSTokenProviding) {
        self.config = config
        self.callback = callback
        self.tokenProvider = tokenProvider
    }

    // MARK: - Authentication

    /// Obtains the first token and builds the managers.
    ///
    /// The SDK exchanged a clientId and clientSecret here. This asks the host's token
    /// provider instead, so the engine runs on whatever the host is already
    /// authenticated as — a signed-in user's access token, or the App Clip's
    /// anonymous experience token.
    func authenticate() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await self.tokenProvider.validToken()
                self.tokenBox.update(token)
                await MainActor.run {
                    VPSEngine.shared.setAuthenticated(true)
                    // Managers first, so a host that attaches its AR session
                    // synchronously from this callback reaches a live manager.
                    self.setupLocalizationManager()
                    self.callback?.onAuthenticationSuccess()
                }
            } catch {
                await MainActor.run {
                    VPSEngine.shared.setAuthenticated(false)
                    self.callback?.onAuthenticationFailure(error: error.localizedDescription)
                }
            }
        }
    }

    /// Refreshes the token the managers read, before a run that may outlive it.
    ///
    /// A user access token lasts 30 minutes while a session with background
    /// re-localization can run far longer, so this is called at the start of every
    /// localization and tracking run rather than once at setup.
    func refreshToken() async {
        do {
            tokenBox.update(try await tokenProvider.validToken())
        } catch {
            print("MultiSetVPS >> Could not refresh the token: \(error.localizedDescription)")
        }
    }

    // MARK: - Localization Manager Setup

    private func setupLocalizationManager() {
        // Convert VPSConfig to internal LocalizationConfig
        let internalConfig = convertToInternalConfig(config)

        localizationManager = LocalizationManager(
            tokenBox: tokenBox,
            config: internalConfig,
            sdkConfig: config
        )

        // Setup callbacks
        localizationManager?.setResultCallback { [weak self] success, message, result in
            guard let self = self else { return }

            if success, let result = result {
                self.callback?.onLocalizationSuccess(result: result)
                print("InternalSDKManager >> Localization callback: success")
            } else {
                self.callback?.onLocalizationFailure(error: message)
            }
        }

        localizationManager?.setFalsePositiveCallback { [weak self] info in
            guard let self = self else { return }
            self.callback?.onLocalizationFalsePositive(info: info)
            print("InternalSDKManager >> Localization callback: \(info.summary)")
        }

        localizationManager?.setMeshLoadHandler { [weak self] mapCodes in
            guard let self = self, let mapCode = mapCodes.first else { return }

            Task {
                await self.localizationManager?.loadMesh(mapId: mapCode, parentEntity: self.parentEntity)
                await MainActor.run {
                    self.callback?.onMeshLoaded(mapCode: mapCode)
                }
            }
        }

        // Setup GPS handler if needed
        if config.passGeoPose {
            gpsHandler = GpsCoordinateHandler()
            gpsHandler?.requestPermission()
            localizationManager?.setGpsHandler(gpsHandler!)
        }

        // The host attaches its AR session and gizmo handler when its AR view is
        // built, which can land before authentication returns and this manager
        // exists. Replay that state instead of dropping it on a nil manager.
        localizationManager?.setARSession(arSession)
        if let gizmoUpdateHandler = gizmoUpdateHandler {
            localizationManager?.setGizmoUpdateHandler(gizmoUpdateHandler)
        }

        // Setup object tracking manager if object codes are configured
        if config.hasObjectTrackingConfiguration {
            setupObjectTrackingManager()
        }
    }

    private func makeTrackingConfig(_ config: VPSConfig) -> ObjectTrackingConfig {
        ObjectTrackingConfig(
            autoTracking: config.autoObjectTracking,
            backgroundTracking: config.backgroundObjectTracking,
            bgTrackingDuration: TimeInterval(config.bgObjectTrackingDurationSeconds),
            restartTracking: config.restartObjectTracking,
            confidenceCheck: config.confidenceCheck,
            confidenceThreshold: config.confidenceThreshold,
            captureDelay: TimeInterval(config.objectTrackingCaptureDelay),
            firstTrackingUntilSuccess: config.firstObjectTrackingUntilSuccess,
            meshVisualization: config.meshVisualization,
            imageQuality: config.imageQuality
        )
    }

    private func setupObjectTrackingManager() {
        let trackingConfig = makeTrackingConfig(config)

        objectTrackingManager = ObjectTrackingManager(
            tokenBox: tokenBox,
            objectCodes: config.objectCodes,
            config: trackingConfig
        )

        objectTrackingManager?.setResultCallback { [weak self] success, message, response in
            guard let self = self else { return }

            if success, let response = response {
                let objectCode = response.objectCodes?.first ?? ""
                let confidence = response.confidence ?? 0
                self.callback?.onObjectTrackingSuccess(objectCode: objectCode, confidence: confidence)
            } else {
                self.callback?.onObjectTrackingFailure(error: message)
            }
        }

        objectTrackingManager?.setMeshLoadedCallback { [weak self] objectCode in
            self?.callback?.onObjectMeshLoaded(objectCode: objectCode)
        }

        objectTrackingManager?.setARSession(arSession)
        objectTrackingManager?.setRootEntity(objectTrackingRootEntity)
    }

    private func convertToInternalConfig(_ config: VPSConfig) -> LocalizationConfig {
        var internalConfig = LocalizationConfig()
        internalConfig.localizationMode = config.localizationMode
        internalConfig.autoLocalize = config.autoLocalize
        internalConfig.backgroundLocalization = config.backgroundLocalization
        internalConfig.bgLocalizationDurationSeconds = config.bgLocalizationDurationSeconds
        internalConfig.relocalization = config.relocalization
        internalConfig.numberOfFrames = config.numberOfFrames
        internalConfig.frameCaptureIntervalMs = config.frameCaptureIntervalMs
        internalConfig.confidenceCheck = config.confidenceCheck
        internalConfig.confidenceThreshold = config.confidenceThreshold
        internalConfig.poseConsistencyCheck = config.poseConsistencyCheck
        internalConfig.poseConsistencyThreshold = config.poseConsistencyThreshold
        internalConfig.firstLocalizationUntilSuccess = config.firstLocalizationUntilSuccess
        internalConfig.showAlerts = config.showAlerts
        internalConfig.meshVisualization = config.meshVisualization
        internalConfig.passGeoPose = config.passGeoPose
        internalConfig.geoCoordinatesInResponse = config.geoCoordinatesInResponse
        internalConfig.hintRadius = config.hintRadius
        internalConfig.use2DFiltering = config.use2DFiltering
        internalConfig.hintMapCodes = config.hintMapCodes
        internalConfig.hintPosition = config.hintPosition
        internalConfig.hintFloorHeight = config.hintFloorHeight
        internalConfig.imageQuality = config.imageQuality
        return internalConfig
    }

    // MARK: - AR Session

    func setARSession(_ session: ARSession?) {
        self.arSession = session
        localizationManager?.setARSession(session)
        objectTrackingManager?.setARSession(session)
    }

    func setParentEntity(_ entity: Entity?) {
        self.parentEntity = entity
    }

    func setObjectTrackingRootEntity(_ entity: Entity?) {
        self.objectTrackingRootEntity = entity
        objectTrackingManager?.setRootEntity(entity)
    }

    func setGizmoUpdateHandler(_ handler: @escaping (SIMD3<Float>, simd_quatf) -> Void) {
        self.gizmoUpdateHandler = handler
        localizationManager?.setGizmoUpdateHandler(handler)
    }

    // MARK: - AR Tracking State

    func handleARTrackingStateChange(_ trackingState: ARCamera.TrackingState) {
        objectTrackingManager?.handleTrackingStateChange(trackingState)
        localizationManager?.handleTrackingStateChange(trackingState)
    }

    func handleARSessionInterrupted() {
        localizationManager?.handleSessionInterrupted()
    }

    func handleARWorldOriginReset() {
        localizationManager?.handleWorldOriginReset()
    }

    func resetPoseConsistencyReference() {
        localizationManager?.resetPoseConsistencyReference()
    }

    // MARK: - Localization Control

    func updateLocalizationMode(_ mode: LocalizationMode) {
        config.localizationMode = mode
        localizationManager?.updateLocalizationMode(mode)
    }

    /// Apply an updated configuration at runtime (after init/auth), propagating
    /// behavioral settings to the active managers. Effective on the next run.
    /// Credentials and map codes are not re-applied (re-initialize for those).
    func updateConfig(_ newConfig: VPSConfig) {
        self.config = newConfig

        // If the localization manager hasn't been created yet (authentication
        // still in flight), setupLocalizationManager() will read the updated
        // `config` when it runs — nothing further to propagate here.
        guard let localizationManager = localizationManager else { return }

        localizationManager.updateConfig(convertToInternalConfig(newConfig), sdkConfig: newConfig)

        // GPS handler follows passGeoPose: create it on first enable, tear it
        // down when disabled.
        if newConfig.passGeoPose {
            if gpsHandler == nil {
                let handler = GpsCoordinateHandler()
                handler.requestPermission()
                gpsHandler = handler
                localizationManager.setGpsHandler(handler)
            }
        } else {
            gpsHandler?.stopUpdates()
            gpsHandler = nil
        }

        // Propagate to the object tracking manager, creating it if object codes
        // were configured but it wasn't set up at auth time.
        if newConfig.hasObjectTrackingConfiguration {
            if let manager = objectTrackingManager {
                manager.updateConfig(makeTrackingConfig(newConfig), objectCodes: newConfig.objectCodes)
            } else {
                setupObjectTrackingManager()
            }
        }
    }

    func startLocalization() {
        localizationManager?.startLocalization()
    }

    func stopLocalization() {
        localizationManager?.stop()
    }

    // MARK: - GPS

    func startGpsUpdates() {
        gpsHandler?.startUpdates()
    }

    func stopGpsUpdates() {
        gpsHandler?.stopUpdates()
    }

    // MARK: - Mesh

    func clearMesh() {
        localizationManager?.clearMesh()
    }

    // MARK: - Object Tracking Control

    func startObjectTracking() {
        objectTrackingManager?.startObjectTracking()
    }

    func stopObjectTracking() {
        objectTrackingManager?.stop()
    }

    func clearObjectMeshes() {
        objectTrackingManager?.clearMeshes()
    }

    var hasTrackedObject: Bool {
        return objectTrackingManager?.hasTracked ?? false
    }

    var isObjectTrackingActive: Bool {
        return objectTrackingManager?.isTracking ?? false
    }

    // MARK: - State

    var isLocalizing: Bool {
        return localizationManager?.isLocalizing ?? false
    }

    var hasLocalized: Bool {
        return localizationManager?.hasLocalized ?? false
    }

    var isShowingOverlay: Bool {
        return localizationManager?.isShowingOverlay ?? false
    }

    var isCapturingFrames: Bool {
        return localizationManager?.isCapturingFrames ?? false
    }

    var authToken: String? {
        let token = tokenBox.value
        return token.isEmpty ? nil : token
    }

    // MARK: - Cleanup

    func release() {
        localizationManager?.stop()
        localizationManager?.clearMesh()
        objectTrackingManager?.stop()
        objectTrackingManager?.clearMeshes()
        gpsHandler?.stopUpdates()
        localizationManager = nil
        objectTrackingManager = nil
        gpsHandler = nil
    }
}
