/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Details of a localization response that the SDK returned to the server as
/// successful but discarded locally as a false positive.
///
/// Every fix in one AR session measures the same map-to-session transform, so two
/// fixes taken minutes and metres apart should still agree on where the map sits.
/// When a response disagrees by more than `poseConsistencyThreshold`, the device's
/// own motion tracking contradicts it and the pose is thrown away instead of being
/// applied to the scene.
public struct FalsePositiveInfo: Sendable {

    /// How far the discarded response placed the map from where the last accepted
    /// fix placed it, in meters
    public let jumpMeters: Float

    /// The tolerance that was in force (`VPSConfig.poseConsistencyThreshold`)
    public let thresholdMeters: Float

    /// Consecutive false positives since the last accepted fix. 1 on the first one
    public let consecutiveCount: Int

    /// Map codes the server reported for the discarded response
    public let mapCodes: [String]

    /// Server confidence of the discarded response, when reported
    public let confidence: Float?

    /// Short machine-readable explanation, for logs
    public let reason: String

    public init(
        jumpMeters: Float,
        thresholdMeters: Float,
        consecutiveCount: Int,
        mapCodes: [String],
        confidence: Float?,
        reason: String
    ) {
        self.jumpMeters = jumpMeters
        self.thresholdMeters = thresholdMeters
        self.consecutiveCount = consecutiveCount
        self.mapCodes = mapCodes
        self.confidence = confidence
        self.reason = reason
    }

    /// One-line summary suitable for logging
    public var summary: String {
        return String(
            format: "false positive #%d — pose %.1f m from the tracked anchor, threshold %.1f m (%@)",
            consecutiveCount, jumpMeters, thresholdMeters, reason
        )
    }
}

/// Delegate protocol for receiving SDK events
/// Implement this protocol to handle authentication, localization, and tracking events
public protocol VPSCallback: AnyObject {

    /// Called when the SDK is initialized and ready for use
    func onSDKReady()

    /// Called when authentication with MultiSet servers succeeds
    func onAuthenticationSuccess()

    /// Called when authentication fails
    /// - Parameter error: Description of the authentication error
    func onAuthenticationFailure(error: String)

    /// Called when localization succeeds
    /// - Parameter result: The localization result containing pose and metadata
    func onLocalizationSuccess(result: LocalizationResult)

    /// Called when localization fails
    /// - Parameter error: Description of the localization error
    func onLocalizationFailure(error: String)

    /// Called when the server returned a pose but the SDK discarded it as a false
    /// positive, because it contradicts the device's own AR trajectory.
    ///
    /// Nothing in the scene was changed: the gizmo, the mesh and the last accepted
    /// result are all left exactly as they were. `onLocalizationSuccess` and
    /// `onLocalizationFailure` are *not* called for this response — handle it here.
    /// Prompt the user to move somewhere more distinctive and localize again.
    ///
    /// Only ever called when `VPSConfig.poseConsistencyCheck` is enabled.
    /// - Parameter info: Why the response was discarded, including the jump distance
    func onLocalizationFalsePositive(info: FalsePositiveInfo)

    /// Called when AR tracking state changes
    /// - Parameter state: The new tracking state
    func onTrackingStateChanged(state: TrackingState)

    /// Called when a mesh is successfully loaded
    /// - Parameter mapCode: The code of the map whose mesh was loaded
    func onMeshLoaded(mapCode: String)

    /// Called when mesh loading fails
    /// - Parameter error: Description of the mesh loading error
    func onMeshLoadError(error: String)

    /// Called when object tracking succeeds
    /// - Parameters:
    ///   - objectCode: The tracked object's code
    ///   - confidence: Confidence score of the tracking
    func onObjectTrackingSuccess(objectCode: String, confidence: Double)

    /// Called when object tracking fails
    /// - Parameter error: Description of the tracking error
    func onObjectTrackingFailure(error: String)

    /// Called when an object mesh is loaded and rendered with outline shader
    /// - Parameter objectCode: The object code whose mesh was loaded
    func onObjectMeshLoaded(objectCode: String)
}

// MARK: - Default Implementations

/// Default implementations for optional callback methods
public extension VPSCallback {
    func onLocalizationFalsePositive(info: FalsePositiveInfo) {
        // Optional - default no-op
    }

    func onMeshLoaded(mapCode: String) {
        // Optional - default no-op
    }

    func onMeshLoadError(error: String) {
        // Optional - default no-op
    }

    func onObjectTrackingSuccess(objectCode: String, confidence: Double) {
        // Optional - default no-op
    }

    func onObjectTrackingFailure(error: String) {
        // Optional - default no-op
    }

    func onObjectMeshLoaded(objectCode: String) {
        // Optional - default no-op
    }
}
