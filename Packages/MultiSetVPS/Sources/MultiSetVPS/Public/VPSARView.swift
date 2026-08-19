/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI
import RealityKit
import ARKit
import Combine

/// Public AR view component for MultiSet SDK localization
/// Embed this view in your SwiftUI hierarchy to display AR content with localization
public struct VPSARView: UIViewRepresentable {

    // MARK: - Properties

    private let viewModel: ARViewModel
    private let gizmoManager = GizmoManager()

    /// The parent entity for mesh rendering (accessible for advanced use cases)
    public var parentEntity: Entity? {
        return gizmoManager.gizmoAnchor
    }

    // MARK: - Initialization

    /// Initialize the AR view
    /// - Note: Call VPSEngine.shared.initialize() before using this view
    public init() {
        self.viewModel = ARViewModel()
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let configuration = viewModel.createARConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true

        #if !targetEnvironment(simulator)
        arView.session.run(configuration)
        #endif

        arView.session.delegate = viewModel
        viewModel.session = arView.session
        viewModel.arView = arView

        // Add gizmo at the origin
        let (anchor, gizmoVisual) = addGizmo(to: arView)
        gizmoManager.gizmoAnchor = anchor
        viewModel.gizmoAnchor = anchor
        VPSEngine.shared.gizmoEntity = gizmoVisual

        // Add lighting for mesh visibility
        addLighting(to: arView)

        // Connect to SDK
        connectToSDK(arView: arView)

        return arView
    }

    public func updateUIView(_ uiView: ARView, context: Context) {
        // Updates handled through SDK callbacks
    }

    // MARK: - SDK Integration

    private func connectToSDK(arView: ARView) {
        // Set AR session on the SDK
        VPSEngine.shared.setARSession(arView.session)

        // Set parent entity for mesh rendering (under gizmo, moves with localization)
        if let anchor = gizmoManager.gizmoAnchor {
            VPSEngine.shared.setParentEntity(anchor)
        }

        // Create a separate world-fixed anchor for object tracking meshes
        let objectTrackingAnchor = AnchorEntity(world: [0, 0, 0])
        objectTrackingAnchor.name = "ObjectTrackingAnchor"
        arView.scene.anchors.append(objectTrackingAnchor)
        VPSEngine.shared.setObjectTrackingRootEntity(objectTrackingAnchor)

        // Set gizmo update handler for localization results
        VPSEngine.shared.setGizmoUpdateHandler { [viewModel] position, rotation in
            DispatchQueue.main.async {
                viewModel.localizeGizmo(position: position, rotation: rotation)
                // Reveal the gizmo now that we have a real localized pose.
                VPSEngine.shared.setGizmoVisible(true)
            }
        }

        // Forward tracking state changes to callback
        viewModel.$isTrackingNormal
            .receive(on: DispatchQueue.main)
            .sink { isNormal in
                let state: TrackingState = isNormal ? .tracking : .paused
                VPSEngine.shared.callback?.onTrackingStateChanged(state: state)
            }
            .store(in: &viewModel.cancellables)
    }

    // MARK: - Gizmo Setup

    private func addGizmo(to arView: ARView) -> (AnchorEntity, Entity) {
        // Create a red axis for X
        let xAxis = ModelEntity(
            mesh: .generateBox(size: [0.5, 0.05, 0.05]),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        xAxis.position = [0.25, 0, 0]

        // Create a green axis for Y
        let yAxis = ModelEntity(
            mesh: .generateBox(size: [0.05, 0.5, 0.05]),
            materials: [SimpleMaterial(color: .green, isMetallic: false)]
        )
        yAxis.position = [0, 0.25, 0]

        // Create a blue axis for Z
        let zAxis = ModelEntity(
            mesh: .generateBox(size: [0.05, 0.05, 0.5]),
            materials: [SimpleMaterial(color: .blue, isMetallic: false)]
        )
        zAxis.position = [0, 0, 0.25]

        // Create origin sphere
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 0.05),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        sphere.position = [0, 0, 0]

        // Group axes into gizmo entity
        let gizmoEntity = Entity()
        gizmoEntity.addChild(xAxis)
        gizmoEntity.addChild(yAxis)
        gizmoEntity.addChild(zAxis)
        gizmoEntity.addChild(sphere)

        // Hide the gizmo until the first successful localization
        // Re-enabled by the gizmo update handler on localization success.
        gizmoEntity.isEnabled = false

        // Create anchor at origin
        let anchorEntity = AnchorEntity(world: [0, 0, 0])
        anchorEntity.addChild(gizmoEntity)

        // Add to scene
        arView.scene.anchors.append(anchorEntity)

        return (anchorEntity, gizmoEntity)
    }

    // MARK: - Lighting

    private func addLighting(to arView: ARView) {
        let directionalLight = DirectionalLight()
        directionalLight.light.color = .white
        directionalLight.light.intensity = 1000
        directionalLight.light.isRealWorldProxy = true

        directionalLight.position = [0, 2, 0]
        directionalLight.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])

        let lightAnchor = AnchorEntity(world: [0, 0, 0])
        lightAnchor.addChild(directionalLight)

        arView.scene.anchors.append(lightAnchor)
    }
}

// MARK: - Internal Gizmo Manager

internal class GizmoManager {
    var gizmoAnchor: AnchorEntity?
}
