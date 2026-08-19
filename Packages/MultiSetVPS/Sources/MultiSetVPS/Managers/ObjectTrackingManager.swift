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
import simd
import UIKit

/// Internal manager for Object Tracking flow
/// Captures AR frame, sends to /v1/vps/object/query, computes pose, manages mesh download
internal class ObjectTrackingManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isTracking = false
    @Published var isWaitingForAPI = false
    @Published var hasTracked = false
    @Published var statusText = "Ready to track"

    var isShowingOverlay: Bool {
        return isWaitingForAPI
    }

    // MARK: - Configuration

    /// Read at request time so a refresh mid-session is picked up.
    private let tokenBox: VPSTokenBox
    private var objectCodes: [String]
    private var autoTracking: Bool = true
    private var backgroundTracking: Bool = true
    private var bgTrackingDuration: TimeInterval = 15.0
    private var restartTracking: Bool = true
    private var confidenceCheck: Bool = true
    private var confidenceThreshold: Float = 0.3
    private var captureDelay: TimeInterval = 1.0
    private var firstTrackingUntilSuccess: Bool = true
    private var meshVisualization: Bool = true
    private var imageQuality: Int = 90

    // MARK: - Internal State

    private var arSession: ARSession?
    private var objectMeshHandler: ObjectMeshHandler?
    private var outlineMeshRenderer: OutlineMeshRenderer?

    private var isActive = false  // true only after user explicitly starts tracking
    private var isFirstTracking = true
    private var bgTrackingRequest = false

    private var queryCameraTransform: simd_float4x4?
    private var currentTrackedObjectCode: String?
    private var fetchedObjectCodes: Set<String> = []

    private var backgroundTimer: Timer?
    private var trackingTask: Task<Void, Never>?

    // Per-object parent entities in the scene
    private var objectSpaceEntities: [String: Entity] = [:]
    private var rootObjectSpaceEntity: Entity?

    // MARK: - Callbacks

    private var resultCallback: ((Bool, String, ObjectTrackingResponse?) -> Void)?
    private var meshLoadedCallback: ((String) -> Void)?

    // MARK: - Initialization

    init(tokenBox: VPSTokenBox, objectCodes: [String], config: ObjectTrackingConfig) {
        self.tokenBox = tokenBox
        self.objectCodes = Array(objectCodes.prefix(10))
        self.autoTracking = config.autoTracking
        self.backgroundTracking = config.backgroundTracking
        self.bgTrackingDuration = config.bgTrackingDuration
        self.restartTracking = config.restartTracking
        self.confidenceCheck = config.confidenceCheck
        self.confidenceThreshold = config.confidenceThreshold
        self.captureDelay = config.captureDelay
        self.firstTrackingUntilSuccess = config.firstTrackingUntilSuccess
        self.meshVisualization = config.meshVisualization
        self.imageQuality = config.imageQuality
        self.objectMeshHandler = ObjectMeshHandler(tokenBox: tokenBox)
        self.outlineMeshRenderer = OutlineMeshRenderer()
    }

    /// Apply updated tracking configuration at runtime. Takes effect on the next
    /// tracking run; an in-flight run / active background timer is unaffected.
    func updateConfig(_ config: ObjectTrackingConfig, objectCodes: [String]) {
        self.objectCodes = Array(objectCodes.prefix(10))
        self.autoTracking = config.autoTracking
        self.backgroundTracking = config.backgroundTracking
        self.bgTrackingDuration = config.bgTrackingDuration
        self.restartTracking = config.restartTracking
        self.confidenceCheck = config.confidenceCheck
        self.confidenceThreshold = config.confidenceThreshold
        self.captureDelay = config.captureDelay
        self.firstTrackingUntilSuccess = config.firstTrackingUntilSuccess
        self.meshVisualization = config.meshVisualization
        self.imageQuality = config.imageQuality
        print("MultiSetVPS >> Object tracking config updated")
    }

    // MARK: - Setup

    func setARSession(_ session: ARSession?) {
        self.arSession = session
    }

    func setRootEntity(_ entity: Entity?) {
        self.rootObjectSpaceEntity = entity
    }

    func setResultCallback(_ callback: @escaping (Bool, String, ObjectTrackingResponse?) -> Void) {
        self.resultCallback = callback
    }

    func setMeshLoadedCallback(_ callback: @escaping (String) -> Void) {
        self.meshLoadedCallback = callback
    }

    // MARK: - Public Methods

    func startObjectTracking() {
        guard !isTracking else { return }

        isActive = true
        bgTrackingRequest = false
        captureFrameForTracking()
    }

    func stop() {
        isActive = false
        trackingTask?.cancel()
        trackingTask = nil
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        isTracking = false
        isWaitingForAPI = false
    }

    func clearMeshes() {
        outlineMeshRenderer?.removeAllMeshes()
        objectSpaceEntities.values.forEach { $0.removeFromParent() }
        objectSpaceEntities.removeAll()
        fetchedObjectCodes.removeAll()
    }

    // MARK: - Frame Capture

    private func captureFrameForTracking() {
        DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [weak self] in
            self?.requestForObjectTracking()
        }
    }

    private func requestForObjectTracking() {
        isTracking = true

        guard let session = arSession,
              let frame = session.currentFrame,
              frame.camera.trackingState == .normal else {
            isTracking = false
            return
        }

        let interfaceOrientation = UIApplication
            .shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
        let isLandscape = interfaceOrientation.isLandscape

        // Save camera transform at capture time, with portrait orientation correction.
        // ARKit's camera.transform is in landscape-left orientation. When the device
        // is in portrait, we must apply a 90° Z rotation to the camera rotation so the
        // query camera matrix matches the rotated image we send to the API.
        // This matches the localization flow in LocalizationManager.captureCurrentFrame().
        let camTransform = frame.camera.transform
        let position = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
        var rotation = simd_quatf(camTransform)

        if !isLandscape {
            let orientationCorrection = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            rotation = rotation * orientationCorrection
        }

        // Rebuild the camera matrix from corrected position + rotation
        var correctedCamMatrix = simd_float4x4(rotation)
        correctedCamMatrix.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1.0)
        queryCameraTransform = correctedCamMatrix

        // Convert pixel buffer to JPEG
        guard let imageResult = processFrameImage(frame: frame, isLandscape: isLandscape) else {
            isTracking = false
            return
        }

        // Calculate intrinsics
        let intrinsics = calculateIntrinsics(frame: frame, isLandscape: isLandscape)

        // Send API request
        DispatchQueue.main.async { [weak self] in
            self?.isWaitingForAPI = true
            self?.statusText = "Tracking..."
        }

        callObjectTrackingAPI(
            imageData: imageResult.data,
            fx: intrinsics.fx, fy: intrinsics.fy,
            px: intrinsics.px, py: intrinsics.py,
            width: intrinsics.width, height: intrinsics.height
        )
    }

    // MARK: - Image Processing

    private func processFrameImage(frame: ARFrame, isLandscape: Bool) -> (data: Data, width: Int, height: Int)? {
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext()

        let orientedCI: CIImage
        if !isLandscape {
            orientedCI = ciImage.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        } else {
            orientedCI = ciImage
        }

        let targetSize = isLandscape ? CGSize(width: 960, height: 720) : CGSize(width: 720, height: 960)

        let scaleX = targetSize.width / orientedCI.extent.width
        let scaleY = targetSize.height / orientedCI.extent.height
        let resizedCI = orientedCI.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let imageData = context.jpegRepresentation(
            of: resizedCI,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: CGFloat(imageQuality) / 100.0]
        ) else {
            return nil
        }

        return (imageData, Int(targetSize.width), Int(targetSize.height))
    }

    private func calculateIntrinsics(frame: ARFrame, isLandscape: Bool) -> CameraIntrinsics {
        let intr = frame.camera.intrinsics
        let fx = intr[0][0]
        let fy = intr[1][1]
        let cx = intr[2][0]
        let cy = intr[2][1]

        let buffer = frame.capturedImage
        let origW = Float(CVPixelBufferGetWidth(buffer))
        let origH = Float(CVPixelBufferGetHeight(buffer))

        let targetW: Float = isLandscape ? 960 : 720
        let targetH: Float = isLandscape ? 720 : 960

        let scaleX = targetW / (isLandscape ? origW : origH)
        let scaleY = targetH / (isLandscape ? origH : origW)

        let newFx: Float
        let newFy: Float
        let newPx: Float
        let newPy: Float

        if isLandscape {
            newFx = fx * scaleX
            newFy = fy * scaleY
            newPx = cx * scaleX
            newPy = cy * scaleY
        } else {
            newFx = fy * scaleX
            newFy = fx * scaleY
            newPx = (origH - cy) * scaleX
            newPy = cx * scaleY
        }

        return CameraIntrinsics(
            fx: newFx,
            fy: newFy,
            px: newPx,
            py: newPy,
            width: Int(targetW),
            height: Int(targetH)
        )
    }

    // MARK: - API Call

    private func callObjectTrackingAPI(
        imageData: Data,
        fx: Float, fy: Float, px: Float, py: Float,
        width: Int, height: Int
    ) {
        trackingTask = Task {
            do {
                let response = try await sendObjectTrackingRequest(
                    imageData: imageData,
                    fx: fx, fy: fy, px: px, py: py,
                    width: width, height: height
                )
                await handleObjectTrackingResponse(response)
            } catch {
                await MainActor.run {
                    handleTrackingFailure(message: "API error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendObjectTrackingRequest(
        imageData: Data,
        fx: Float, fy: Float, px: Float, py: Float,
        width: Int, height: Int
    ) async throws -> ObjectTrackingResponse {
        guard let url = URL(string: SDKEndpoints.objectQueryURL) else {
            throw NSError(domain: "ObjectTrackingManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let lineBreak = "\r\n"

        // Add each objectCode as a separate form field
        for code in objectCodes {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"objectCode\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(code)\(lineBreak)".data(using: .utf8)!)
        }

        // Camera parameters
        // iOS ARKit uses right-handed coordinate system
        // Must match what the existing localization flow sends
        let params: [String: String] = [
            "isRightHanded": "true",
            "fx": String(fx),
            "fy": String(fy),
            "px": String(px),
            "py": String(py),
            "width": String(width),
            "height": String(height)
        ]

        for (key, value) in params {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }

        // Image binary data
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"queryImage\"; filename=\"image.JPG\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(imageData)
        body.append(lineBreak.data(using: .utf8)!)

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ObjectTrackingManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw NSError(domain: "ObjectTrackingManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(responseBody)"])
        }

        return try JSONDecoder().decode(ObjectTrackingResponse.self, from: data)
    }

    // MARK: - Response Handling

    @MainActor
    private func handleObjectTrackingResponse(_ response: ObjectTrackingResponse) {
        isTracking = false
        isWaitingForAPI = false

        guard response.poseFound else {
            handleTrackingFailure(message: "Object not found")
            return
        }

        if confidenceCheck {
            let confidence = response.confidence ?? 1.0
            if Float(confidence) < confidenceThreshold {
                handleTrackingFailure(message: "Low confidence: \(confidence)")
                return
            }
        }

        // Apply pose
        applyObjectTrackingPose(response)

        if isFirstTracking {
            isFirstTracking = false
        }

        hasTracked = true
        statusText = "Object tracked"

        resultCallback?(true, "Object Tracking Success", response)

        // Schedule background re-tracking
        if backgroundTracking {
            scheduleBackgroundTracking()
        }
    }

    private func applyObjectTrackingPose(_ response: ObjectTrackingResponse) {
        guard let pos = response.position,
              let rot = response.rotation,
              let queryCam = queryCameraTransform else { return }

        // Build response pose matrix
        let responsePosition = pos.toSIMD3()
        let responseRotation = rot.toQuaternion()

        let responseRotMatrix = simd_float4x4(responseRotation)
        var responsePose = responseRotMatrix
        responsePose.columns.3 = SIMD4<Float>(responsePosition.x, responsePosition.y, responsePosition.z, 1.0)

        // CRITICAL: resultPose = queryCameraTransform * responsePose.inverse
        let resultPose = queryCam * responsePose.inverse

        let resultPosition = SIMD3<Float>(
            resultPose.columns.3.x,
            resultPose.columns.3.y,
            resultPose.columns.3.z
        )
        let resultRotation = simd_quatf(resultPose)

        guard let trackedCode = response.objectCodes?.first else { return }
        currentTrackedObjectCode = trackedCode

        // Place or update entity for this object code
        let objectEntity = getOrCreateObjectSpace(for: trackedCode)
        objectEntity.transform.translation = resultPosition
        objectEntity.transform.rotation = resultRotation
        objectEntity.isEnabled = true

        // Download mesh for this object (once per code)
        if !fetchedObjectCodes.contains(trackedCode) {
            fetchedObjectCodes.insert(trackedCode)
            downloadObjectMesh(objectCode: trackedCode, parentEntity: objectEntity)
        } else {
            // Mesh already loaded, just make sure it's visible
            outlineMeshRenderer?.setMeshVisible(for: trackedCode, visible: true)
        }
    }

    // MARK: - Object Space Management

    private func getOrCreateObjectSpace(for objectCode: String) -> Entity {
        if let existing = objectSpaceEntities[objectCode] {
            return existing
        }

        let entity = Entity()
        entity.name = objectCode
        entity.isEnabled = false

        rootObjectSpaceEntity?.addChild(entity)
        objectSpaceEntities[objectCode] = entity

        return entity
    }

    // MARK: - Mesh Download

    private func downloadObjectMesh(objectCode: String, parentEntity: Entity) {
        guard meshVisualization else { return }

        Task {
            do {
                guard let meshResult = try await objectMeshHandler?.downloadObjectMesh(objectCode: objectCode) else {
                    return
                }

                await MainActor.run {
                    outlineMeshRenderer?.renderOutlineMesh(
                        meshResult: meshResult,
                        parentEntity: parentEntity
                    )
                    meshLoadedCallback?(objectCode)
                }
            } catch {
                // Mesh loading failed silently
            }
        }
    }

    // MARK: - Background Re-Tracking

    private func scheduleBackgroundTracking() {
        backgroundTimer?.invalidate()

        backgroundTimer = Timer.scheduledTimer(
            withTimeInterval: bgTrackingDuration,
            repeats: false
        ) { [weak self] _ in
            guard let self = self, self.isActive, !self.isTracking else { return }

            // Don't track when app is in the background
            guard UIApplication.shared.applicationState == .active else {
                self.scheduleBackgroundTracking()
                return
            }
            self.bgTrackingRequest = true
            self.startObjectTracking()
        }
    }

    // MARK: - Failure Handling

    private func handleTrackingFailure(message: String) {
        isTracking = false
        isWaitingForAPI = false

        if firstTrackingUntilSuccess && isFirstTracking && !bgTrackingRequest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startObjectTracking()
            }
            return
        }

        statusText = "Tracking failed"
        resultCallback?(false, message, nil)

        if backgroundTracking {
            scheduleBackgroundTracking()
        }
    }

    // MARK: - AR Tracking State

    func handleTrackingStateChange(_ trackingState: ARCamera.TrackingState) {
        guard isActive, restartTracking else { return }

        switch trackingState {
        case .notAvailable, .limited:
            if !isTracking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.startObjectTracking()
                }
            }
        case .normal:
            break
        }
    }
}

// MARK: - Object Tracking Configuration

internal struct ObjectTrackingConfig {
    var autoTracking: Bool = true
    var backgroundTracking: Bool = true
    var bgTrackingDuration: TimeInterval = 15.0
    var restartTracking: Bool = true
    var confidenceCheck: Bool = true
    var confidenceThreshold: Float = 0.3
    var captureDelay: TimeInterval = 1.0
    var firstTrackingUntilSuccess: Bool = true
    var meshVisualization: Bool = true
    var imageQuality: Int = 90
}
