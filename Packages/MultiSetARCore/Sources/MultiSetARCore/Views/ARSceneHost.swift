import ARKit
import AVFoundation
import Combine
import MultiSetKit
import RealityKit
import SwiftUI
import simd

/// Owns the `ARView`, the `ARSession`, and the entity hierarchy that map content
/// is anchored into.
///
/// A class rather than view state because the ARKit session must outlive SwiftUI
/// re-renders — recreating it on every body evaluation would restart tracking and
/// throw away the world origin the localization result is expressed against.
@MainActor
public final class ARSceneHost: ObservableObject {
    public let arView: ARView
    /// Everything positioned in map space hangs off here, so a new fix only has
    /// to move one transform.
    public let mapAnchor: AnchorEntity
    public let frameSource: ARKitFrameSource

    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var cameraAccessDenied = false

    private var contentRoot = Entity()

    public init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        mapAnchor = AnchorEntity(world: .zero)
        frameSource = ARKitFrameSource(session: arView.session)

        mapAnchor.addChild(contentRoot)
        arView.scene.addAnchor(mapAnchor)
        arView.environment.sceneUnderstanding.options = []
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField]
    }

    public var session: ARSession { arView.session }

    public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    public func start() {
        guard Self.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        frameSource.attach(session: session)
        isSessionRunning = true
    }

    public func pause() {
        session.pause()
        isSessionRunning = false
    }

    public func requestCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAccessDenied = false
        case .notDetermined:
            cameraAccessDenied = !(await AVCaptureDevice.requestAccess(for: .video))
        case .denied, .restricted:
            cameraAccessDenied = true
        @unknown default:
            cameraAccessDenied = true
        }
    }

    /// Re-anchors map content. Replacing the transform on one parent is cheaper
    /// than repositioning every child, and keeps content from visibly jumping
    /// piece by piece as a new fix lands.
    public func apply(worldFromMap: simd_float4x4) {
        mapAnchor.transform = Transform(matrix: worldFromMap)
    }

    public func replaceContent(with entities: [Entity]) {
        contentRoot.removeFromParent()
        contentRoot = Entity()
        for entity in entities {
            contentRoot.addChild(entity)
        }
        mapAnchor.addChild(contentRoot)
    }

    public func clearContent() {
        replaceContent(with: [])
    }

    public func snapshot() async -> UIImage? {
        await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { continuation.resume(returning: $0) }
        }
    }
}

public struct ARSceneView: UIViewRepresentable {
    public let host: ARSceneHost

    public init(host: ARSceneHost) {
        self.host = host
    }

    public func makeUIView(context: Context) -> ARView { host.arView }

    public func updateUIView(_ uiView: ARView, context: Context) {}
}
