/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import Combine
import ARKit
import RealityKit

/// Internal AR session and tracking manager
internal class ARViewModel: NSObject, ARSessionDelegate, ObservableObject {

    @Published var appState = AppState()
    @Published var isTrackingNormal = false

    var session: ARSession?
    var arView: ARView?
    var gizmoAnchor: AnchorEntity?

    var cancellables = Set<AnyCancellable>()

    // MARK: - Gizmo Methods

    func localizeGizmo(position: SIMD3<Float>, rotation: simd_quatf) {
        guard let gizmoAnchor = gizmoAnchor else {
            print("MultiSetVPS >> Gizmo anchor is not initialized")
            return
        }
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            print("MultiSetVPS >> Invalid position: \(position)")
            return
        }
        guard rotation.vector.x.isFinite, rotation.vector.y.isFinite, rotation.vector.z.isFinite, rotation.vector.w.isFinite else {
            print("MultiSetVPS >> Invalid rotation: \(rotation)")
            return
        }

        gizmoAnchor.transform.translation = position
        gizmoAnchor.transform.rotation = rotation

        print("MultiSetVPS >> Gizmo updated to Position: \(position), Rotation: \(rotation)")
    }

    func resetWorldOrigin() {
        session?.pause()
        let config = createARConfiguration()
        session?.run(config, options: [.resetTracking])

        VPSEngine.shared.handleARWorldOriginReset()

        gizmoAnchor?.transform.translation = SIMD3<Float>(0, 0, 0)
        gizmoAnchor?.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - AR Configuration

    func createARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true

        if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = .sceneDepth
        }
        return configuration
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Available for frame processing
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async {
            self.appState.trackingState = self.trackingStateToString(camera.trackingState)
            self.isTrackingNormal = (camera.trackingState == .normal)

            // Forward to object tracking manager for re-tracking on state loss
            VPSEngine.shared.handleARTrackingStateChange(camera.trackingState)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("MultiSetVPS >> AR session interrupted")
        DispatchQueue.main.async {
            VPSEngine.shared.handleARSessionInterrupted()
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("MultiSetVPS >> AR session interruption ended")
        DispatchQueue.main.async {
            VPSEngine.shared.handleARSessionInterrupted()
        }
    }

    func trackingStateToString(_ trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .notAvailable:
            return "Not Available"
        case .normal:
            return "Tracking Normal"
        case .limited(.excessiveMotion):
            return "Excessive Motion"
        case .limited(.initializing):
            return "Tracking Initializing"
        case .limited(.insufficientFeatures):
            return "Insufficient Features"
        case .limited(.relocalizing):
            return "Relocalizing"
        @unknown default:
            return "Unknown"
        }
    }

    func toPublicTrackingState(_ arTrackingState: ARCamera.TrackingState) -> TrackingState {
        switch arTrackingState {
        case .normal:
            return .tracking
        case .limited:
            return .paused
        case .notAvailable:
            return .stopped
        }
    }
}
