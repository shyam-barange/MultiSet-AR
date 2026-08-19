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

/// Internal manager for localization process
/// Handles frame capture, API calls, background localization, and retry logic
internal class LocalizationManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isLocalizing = false
    @Published var isCapturingFrames = false
    @Published var isWaitingForAPI = false
    @Published var isBackgroundRequest = false
    @Published var hasLocalized = false
    @Published var statusText = "Capturing frames..."

    var isShowingOverlay: Bool {
        return (isCapturingFrames || isWaitingForAPI) && !isBackgroundRequest
    }

    // MARK: - Private Properties

    /// Read at request time so a refresh mid-session is picked up.
    private let tokenBox: VPSTokenBox
    private var config: LocalizationConfig
    private var sdkConfig: VPSConfig

    private var arSession: ARSession?
    private var gpsHandler: GpsCoordinateHandler?
    private var meshHandler: MeshHandler?
    private var meshRenderer: MeshRenderer?

    private var isFirstLocalization = true
    private var capturedFrames: [CapturedFrame] = []
    private var capturedGpsCoordinates: GeoCoordinates?

    private lazy var poseConsistencyGate = PoseConsistencyGate(
        thresholdMeters: config.poseConsistencyThreshold
    )
    private var reestablishRetryCount = 0
    private var consecutiveFalsePositives = 0
    private static let reestablishRetryDelay: TimeInterval = 1.0
    private static let maxReestablishRetries = 3

    private var backgroundLocalizationTimer: Timer?
    private var localizationTask: Task<Void, Never>?

    // Callbacks
    private var gizmoUpdateHandler: ((SIMD3<Float>, simd_quatf) -> Void)?
    private var meshLoadHandler: (([String]) -> Void)?
    private var resultCallback: ((Bool, String, LocalizationResult?) -> Void)?
    private var falsePositiveCallback: ((FalsePositiveInfo) -> Void)?

    // Last result
    private var lastResult: InternalLocalizationResult?

    // MARK: - Initialization

    init(tokenBox: VPSTokenBox, config: LocalizationConfig, sdkConfig: VPSConfig) {
        self.tokenBox = tokenBox
        self.config = config.validated()
        self.sdkConfig = sdkConfig
        self.meshHandler = MeshHandler(tokenBox: tokenBox)
        self.meshRenderer = MeshRenderer()
    }

    // MARK: - Setup Methods

    func setARSession(_ session: ARSession?) {
        // A different session is a different world origin, so an anchor measured in the
        // old one cannot be compared against anything in the new one. This fires when a
        // host tears down and re-creates its AR view (leaving and re-entering an AR
        // screen), and does not depend on ARKit reporting `.limited(.initializing)`.
        if session !== arSession {
            resetPoseConsistency()
        }

        self.arSession = session
    }

    func setGpsHandler(_ handler: GpsCoordinateHandler) {
        self.gpsHandler = handler
    }

    func setGizmoUpdateHandler(_ handler: @escaping (SIMD3<Float>, simd_quatf) -> Void) {
        self.gizmoUpdateHandler = handler
    }

    func setMeshLoadHandler(_ handler: @escaping ([String]) -> Void) {
        self.meshLoadHandler = handler
    }

    func setResultCallback(_ callback: @escaping (Bool, String, LocalizationResult?) -> Void) {
        self.resultCallback = callback
    }

    func setFalsePositiveCallback(_ callback: @escaping (FalsePositiveInfo) -> Void) {
        self.falsePositiveCallback = callback
    }

    func updateLocalizationMode(_ mode: LocalizationMode) {
        config.localizationMode = mode
        sdkConfig.localizationMode = mode
        print("MultiSetVPS >> Localization mode updated to: \(mode.rawValue)")
    }

    /// Apply an updated configuration at runtime. Behavioral changes take effect
    /// on the next localization run; an in-flight run is unaffected.
    func updateConfig(_ config: LocalizationConfig, sdkConfig: VPSConfig) {
        self.config = config.validated()
        self.sdkConfig = sdkConfig
        poseConsistencyGate.updateTuning(thresholdMeters: self.config.poseConsistencyThreshold)
        print("MultiSetVPS >> Localization config updated")
    }

    func handleTrackingStateChange(_ trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            break
        case .limited(.relocalizing), .notAvailable:
            markSessionDiscontinuity()
        case .limited(.initializing):
            resetPoseConsistency()
        case .limited:
            break
        @unknown default:
            markSessionDiscontinuity()
        }
    }

    func handleSessionInterrupted() {
        markSessionDiscontinuity()
    }

    func handleWorldOriginReset() {
        resetPoseConsistency()
    }

    private func markSessionDiscontinuity() {
        if poseConsistencyGate.markSessionDiscontinuity() {
            reestablishRetryCount = 0
            consecutiveFalsePositives = 0
        }
    }

    /// Drop the reference outright, so the next response is trusted and becomes the
    /// new one. Called on a world-origin reset and by hosts that want to re-bootstrap
    /// deliberately after a run of rejections.
    func resetPoseConsistencyReference() {
        resetPoseConsistency()
        print("MultiSetVPS >> Pose consistency reference cleared, next response will bootstrap")
    }

    private func resetPoseConsistency() {
        poseConsistencyGate.reset()
        reestablishRetryCount = 0
        consecutiveFalsePositives = 0
    }

    // MARK: - Public Methods

    func startLocalization() {
        guard !isLocalizing else {
            print("MultiSetVPS >> Localization already in progress")
            return
        }

        isBackgroundRequest = false
        beginLocalization()
    }

    func stop() {
        localizationTask?.cancel()
        localizationTask = nil
        backgroundLocalizationTimer?.invalidate()
        backgroundLocalizationTimer = nil
        isLocalizing = false
        isCapturingFrames = false
        isWaitingForAPI = false
        capturedFrames.removeAll()
    }

    func clearMesh() {
        meshRenderer?.removeMesh()
    }

    func loadMesh(mapId: String, parentEntity: Entity?) async {
        guard config.meshVisualization else { return }
        guard let parent = parentEntity else { return }

        // Capture camera world position for mesh reveal animation
        let cameraWorldPosition: SIMD3<Float>? = arSession?.currentFrame.map { frame in
            let col3 = frame.camera.transform.columns.3
            return SIMD3<Float>(col3.x, col3.y, col3.z)
        }

        do {
            let meshResult: MeshResult?

            switch sdkConfig.activeMapType {
            case .map:
                meshResult = try await meshHandler?.loadMeshForMap(mapId: mapId)
            case .mapSet:
                meshResult = try await meshHandler?.loadMeshForMapSet(
                    mapSetCode: sdkConfig.mapSetCode,
                    localizedMapId: mapId
                )
            }

            if let result = meshResult {
                let session = self.arSession
                await MainActor.run {
                    meshRenderer?.renderMesh(meshResult: result, parentEntity: parent, cameraWorldPosition: cameraWorldPosition, arSession: session)
                }
            }
        } catch {
            // Mesh loading failed silently
        }
    }

    // MARK: - Private Methods

    private func beginLocalization() {
        capturedFrames.removeAll()
        isLocalizing = true
        isCapturingFrames = true

        switch config.localizationMode {
        case .singleFrame:
            statusText = "Capturing frame..."
        case .multiFrame:
            statusText = "Capturing frames..."
        }

        if config.passGeoPose {
            capturedGpsCoordinates = gpsHandler?.getCurrentCoordinates()
            if capturedGpsCoordinates?.isValid() == true {
                print("MultiSetVPS >> GPS captured: \(capturedGpsCoordinates!.toGeoHintString())")
            } else {
                capturedGpsCoordinates = nil
            }
        }

        localizationTask = Task {
            switch config.localizationMode {
            case .singleFrame:
                await captureSingleFrame()
            case .multiFrame:
                await captureFrames()
            }
        }
    }

    private func captureFrames() async {
        for i in 0..<config.numberOfFrames {
            guard !Task.isCancelled else { return }

            await MainActor.run {
                statusText = "Capturing frame \(i + 1)/\(config.numberOfFrames)..."
            }

            if let frame = await captureCurrentFrame() {
                capturedFrames.append(frame)
                print("MultiSetVPS >> Frame \(capturedFrames.count)/\(config.numberOfFrames) captured")
            }

            if i < config.numberOfFrames - 1 {
                try? await Task.sleep(nanoseconds: UInt64(config.frameCaptureIntervalMs) * 1_000_000)
            }
        }

        await MainActor.run {
            isCapturingFrames = false
            isWaitingForAPI = true
            statusText = "Localizing..."
        }

        await sendLocalizationRequest()
    }

    private func captureSingleFrame() async {
        guard !Task.isCancelled else { return }

        await MainActor.run {
            statusText = "Capturing frame..."
        }

        if let frame = await captureCurrentFrame() {
            capturedFrames.append(frame)
            print("MultiSetVPS >> Single frame captured")
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            isCapturingFrames = false
            isWaitingForAPI = true
            statusText = "Localizing..."
        }

        await sendLocalizationRequest()
    }

    @MainActor
    private func captureCurrentFrame() async -> CapturedFrame? {
        guard let session = arSession,
              let frame = session.currentFrame,
              frame.camera.trackingState == .normal else {
            print("MultiSetVPS >> Frame not ready for capture")
            return nil
        }

        let interfaceOrientation = UIApplication
            .shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait

        let isLandscape = interfaceOrientation.isLandscape

        let position = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )

        var rotation = simd_quatf(frame.camera.transform)

        if !isLandscape {
            let orientationCorrection = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            rotation = rotation * orientationCorrection
        }

        guard let imageData = processFrameImage(frame: frame, isLandscape: isLandscape) else {
            return nil
        }

        let intrinsics = calculateIntrinsics(frame: frame, isLandscape: isLandscape)

        return CapturedFrame(
            imageData: imageData.data,
            position: position,
            rotation: rotation,
            intrinsics: intrinsics
        )
    }

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
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: CGFloat(config.imageQuality) / 100.0]
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

    /// Appends `hintMapCodes` multipart fields (one per code) to the request body.
    /// Only sent for MapSet localization
    private func appendHintMapCodes(to body: inout Data, boundary: String, lineBreak: String) {
        guard sdkConfig.activeMapType == .mapSet, !config.hintMapCodes.isEmpty else { return }

        for code in config.hintMapCodes {
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"hintMapCodes\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(trimmed)\(lineBreak)".data(using: .utf8)!)
        }
    }

    private func sendLocalizationRequest() async {
        guard !capturedFrames.isEmpty else {
            handleLocalizationFailure(message: "No frames captured")
            return
        }

        let firstFrame = capturedFrames[0]

        var parameters: [String: String] = [
            "isRightHanded": "true",
            "fx": String(firstFrame.intrinsics.fx),
            "fy": String(firstFrame.intrinsics.fy),
            "px": String(firstFrame.intrinsics.px),
            "py": String(firstFrame.intrinsics.py),
            "width": String(firstFrame.intrinsics.width),
            "height": String(firstFrame.intrinsics.height)
        ]

        switch sdkConfig.activeMapType {
        case .map:
            parameters["mapCode"] = sdkConfig.mapCode
        case .mapSet:
            parameters["mapSetCode"] = sdkConfig.mapSetCode
        }

        if config.passGeoPose {
            if let gps = capturedGpsCoordinates, gps.isValid() {
                parameters["geoHint"] = gps.toGeoHintString()
                print("MultiSetVPS >> Adding geoHint: \(gps.toGeoHintString())")
            }
        }

        if config.geoCoordinatesInResponse {
            parameters["convertToGeoCoordinates"] = "true"
        }

        // Localization hints
        let trimmedHintPosition = config.hintPosition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHintPosition.isEmpty {
            parameters["hintPosition"] = trimmedHintPosition
        }

        let trimmedHintFloorHeight = config.hintFloorHeight.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHintFloorHeight.isEmpty {
            parameters["hintFloorHeight"] = trimmedHintFloorHeight
        }

        // Spatial filters only make sense when a geo hint or a positional hint is
        // present. Sending hintRadius/use2DFiltering without a geo/position reference
        // can make the server return "pose not found", so gate them here.
        let hasGeoOrPositionHint = parameters["geoHint"] != nil || !trimmedHintPosition.isEmpty
        if hasGeoOrPositionHint {
            if config.hintRadius > 0 {
                parameters["hintRadius"] = String(config.hintRadius)
            }

            if config.use2DFiltering {
                parameters["use2DFiltering"] = "true"
            }
        }

        print("MultiSetVPS >> Sending \(config.localizationMode.rawValue) localization request with \(capturedFrames.count) frame(s)")

        do {
            switch config.localizationMode {
            case .singleFrame:
                let (response, rawBody) = try await sendSingleFrameRequest(parameters: parameters)
                await handleSingleFrameResponse(response, rawBody: rawBody)
            case .multiFrame:
                let (response, rawBody) = try await sendMultiFrameRequest(parameters: parameters)
                await handleLocalizationResponse(response, rawBody: rawBody)
            }
        } catch {
            handleLocalizationFailure(message: "API error: \(error.localizedDescription)")
        }
    }

    private func sendMultiFrameRequest(parameters: [String: String]) async throws -> (MultiFrameLocalizationResponse, String) {
        guard let url = URL(string: SDKEndpoints.multiImageQueryURL) else {
            throw NSError(domain: "LocalizationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let lineBreak = "\r\n"

        for (key, value) in parameters {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }

        appendHintMapCodes(to: &body, boundary: boundary, lineBreak: lineBreak)

        for (index, frame) in capturedFrames.enumerated() {
            let imageNum = index + 1

            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\(imageNum)\"; filename=\"image_\(imageNum).JPG\"\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append(frame.imageData)
            body.append(lineBreak.data(using: .utf8)!)

            let metadata = ImageMetadata(
                x: frame.position.x,
                y: frame.position.y,
                z: frame.position.z,
                qx: frame.rotation.imag.x,
                qy: frame.rotation.imag.y,
                qz: frame.rotation.imag.z,
                qw: frame.rotation.real
            )

            if let metadataJSON = metadata.toJSONString() {
                body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"image\(imageNum)_data\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
                body.append("\(metadataJSON)\(lineBreak)".data(using: .utf8)!)
            }
        }

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "LocalizationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw NSError(domain: "LocalizationManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(responseBody)"])
        }

        let decoded = try JSONDecoder().decode(MultiFrameLocalizationResponse.self, from: data)
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        return (decoded, rawBody)
    }

    private func sendSingleFrameRequest(parameters: [String: String]) async throws -> (SingleFrameLocalizationResponse, String) {
        guard let url = URL(string: SDKEndpoints.queryURL) else {
            throw NSError(domain: "LocalizationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        guard let frame = capturedFrames.first else {
            throw NSError(domain: "LocalizationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No frame captured"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let lineBreak = "\r\n"

        for (key, value) in parameters {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }

        appendHintMapCodes(to: &body, boundary: boundary, lineBreak: lineBreak)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"queryImage\"; filename=\"query_image.JPG\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(frame.imageData)
        body.append(lineBreak.data(using: .utf8)!)

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "LocalizationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            throw NSError(domain: "LocalizationManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(responseBody)"])
        }

        let decoded = try JSONDecoder().decode(SingleFrameLocalizationResponse.self, from: data)
        let rawBody = String(data: data, encoding: .utf8) ?? ""
        return (decoded, rawBody)
    }

    @MainActor
    private func handleSingleFrameResponse(_ response: SingleFrameLocalizationResponse, rawBody: String) async {
        isLocalizing = false
        isWaitingForAPI = false

        guard response.poseFound else {
            handleLocalizationFailure(message: response.message ?? "Pose not found")
            return
        }

        guard let position = response.position,
              let rotation = response.rotation else {
            handleLocalizationFailure(message: "Missing pose data in response")
            return
        }

        guard let capturedFrame = capturedFrames.first else {
            handleLocalizationFailure(message: "No captured frame available")
            return
        }

        if config.confidenceCheck {
            let confidence = response.confidence ?? 1.0
            if confidence < config.confidenceThreshold {
                handleLocalizationFailure(message: "Low confidence: \(confidence)")
                return
            }
        }

        let resultPose = calculateSingleFrameResultPose(
            estimatedPosition: position.toSIMD3(),
            estimatedRotation: rotation.toQuaternion(),
            trackingPosition: capturedFrame.position,
            trackingRotation: capturedFrame.rotation
        )

        guard passesPoseConsistency(
            anchor: resultPose.position,
            mapCodes: response.safeMapCodes,
            confidence: response.confidence
        ) else { return }

        lastResult = InternalLocalizationResult(
            response: response,
            resultPosition: resultPose.position,
            resultRotation: resultPose.rotation
        )

        if isFirstLocalization {
            isFirstLocalization = false
        }

        hasLocalized = true

        gizmoUpdateHandler?(resultPose.position, resultPose.rotation)
        meshLoadHandler?(response.safeMapCodes)

        let result = LocalizationResult(
            mapCode: response.safeMapCodes.first ?? "",
            mapCodes: response.safeMapCodes,
            position: resultPose.position,
            rotation: resultPose.rotation,
            confidence: response.confidence,
            geoCoordinates: response.GeoPose?.toGeoCoordinates(),
            geoPose: response.GeoPose?.toGeoPose(),
            estimatedPosition: position.toSIMD3(),
            estimatedRotation: rotation.toQuaternion(),
            queryCameraPosition: capturedFrame.position,
            queryCameraRotation: capturedFrame.rotation,
            mode: .singleFrame
        )
        resultCallback?(true, "Localization Success", result)

        print("MultiSetVPS >> Single-frame localization successful!")
        print("MultiSetVPS >> Localization response:\n\(rawBody)")

        if config.backgroundLocalization {
            scheduleBackgroundLocalization()
        }
    }

    private func calculateSingleFrameResultPose(
        estimatedPosition: SIMD3<Float>,
        estimatedRotation: simd_quatf,
        trackingPosition: SIMD3<Float>,
        trackingRotation: simd_quatf
    ) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let estRotMatrix = simd_float4x4(estimatedRotation)
        var estMatrix = estRotMatrix
        estMatrix.columns.3 = SIMD4<Float>(estimatedPosition.x, estimatedPosition.y, estimatedPosition.z, 1.0)
        let invEstMatrix = estMatrix.inverse

        let trackRotMatrix = simd_float4x4(trackingRotation)
        var trackMatrix = trackRotMatrix
        trackMatrix.columns.3 = SIMD4<Float>(trackingPosition.x, trackingPosition.y, trackingPosition.z, 1.0)

        let resultMatrix = trackMatrix * invEstMatrix

        let resultPosition = SIMD3<Float>(
            resultMatrix.columns.3.x,
            resultMatrix.columns.3.y,
            resultMatrix.columns.3.z
        )

        let resultRotation = simd_quatf(resultMatrix)

        return (resultPosition, resultRotation)
    }

    @MainActor
    private func handleLocalizationResponse(_ response: MultiFrameLocalizationResponse, rawBody: String) async {
        isLocalizing = false
        isWaitingForAPI = false

        guard response.poseFound else {
            handleLocalizationFailure(message: response.message ?? "Pose not found")
            return
        }

        guard let estimatedPose = response.estimatedPose,
              let trackingPose = response.trackingPose else {
            handleLocalizationFailure(message: "Missing pose data in response")
            return
        }

        if config.confidenceCheck {
            let confidence = response.confidence ?? 1.0
            if confidence < config.confidenceThreshold {
                handleLocalizationFailure(message: "Low confidence: \(confidence)")
                return
            }
        }

        let resultPose = calculateResultPose(estimatedPose: estimatedPose, trackingPose: trackingPose)

        guard passesPoseConsistency(
            anchor: resultPose.position,
            mapCodes: response.safeMapCodes,
            confidence: response.confidence
        ) else { return }

        lastResult = InternalLocalizationResult(
            response: response,
            resultPosition: resultPose.position,
            resultRotation: resultPose.rotation
        )

        if isFirstLocalization {
            isFirstLocalization = false
        }

        hasLocalized = true

        gizmoUpdateHandler?(resultPose.position, resultPose.rotation)
        meshLoadHandler?(response.safeMapCodes)

        let result = LocalizationResult(
            mapCode: response.safeMapCodes.first ?? "",
            mapCodes: response.safeMapCodes,
            position: resultPose.position,
            rotation: resultPose.rotation,
            confidence: response.confidence,
            geoCoordinates: response.GeoPose?.toGeoCoordinates(),
            geoPose: response.GeoPose?.toGeoPose(),
            estimatedPosition: estimatedPose.position.toSIMD3(),
            estimatedRotation: estimatedPose.rotation.toQuaternion(),
            queryCameraPosition: trackingPose.position.toSIMD3(),
            queryCameraRotation: trackingPose.rotation.toQuaternion(),
            mode: .multiFrame
        )
        resultCallback?(true, "Localization Success", result)

        print("MultiSetVPS >> Localization successful!")
        print("MultiSetVPS >> Localization response:\n\(rawBody)")

        if config.backgroundLocalization {
            scheduleBackgroundLocalization()
        }
    }

    /// Runs the false-positive gate over a pose the server accepted.
    ///
    /// Returns true when the response may be applied. On false the response has
    /// already been reported (as a false positive or as a plain failure) and the
    /// caller must return immediately without touching the gizmo, the mesh,
    /// `lastResult` or `hasLocalized` — discarding the response is the whole point.
    @MainActor
    private func passesPoseConsistency(
        anchor: SIMD3<Float>,
        mapCodes: [String],
        confidence: Float?
    ) -> Bool {
        guard config.poseConsistencyCheck else { return true }

        let decision = poseConsistencyGate.evaluate(anchor: anchor)
        logPoseConsistency(decision)

        if decision.accepted {
            reestablishRetryCount = 0
            consecutiveFalsePositives = 0
            return true
        }

        if decision.isFalsePositive {
            consecutiveFalsePositives += 1
            handleFalsePositive(decision: decision, mapCodes: mapCodes, confidence: confidence)
        } else {
            handleLocalizationFailure(
                message: "Pose consistency rejected: \(decision.reason)",
                reestablishing: decision.reestablishing
            )
        }

        return false
    }

    /// A server pose that contradicts the device's own AR trajectory: the query image
    /// matched somewhere else in the space. Reported on its own channel rather than as
    /// a localization failure, because the distinction matters to the host app — the
    /// request succeeded, the answer was wrong, and the user should localize again.
    private func handleFalsePositive(
        decision: PoseConsistencyGate.Decision,
        mapCodes: [String],
        confidence: Float?
    ) {
        isLocalizing = false
        isCapturingFrames = false
        isWaitingForAPI = false

        let info = FalsePositiveInfo(
            jumpMeters: decision.jumpMeters,
            thresholdMeters: decision.thresholdMeters,
            consecutiveCount: consecutiveFalsePositives,
            mapCodes: mapCodes,
            confidence: confidence,
            reason: decision.reason
        )

        print("MultiSetVPS >> Discarded \(info.summary)")
        print("MultiSetVPS >> Scene left untouched — gizmo and mesh keep the last accepted pose")

        falsePositiveCallback?(info)

        // No fast retry: the host app is being told to localize again, and an
        // automatic retry from the same spot would either race that prompt or feed a
        // second identical mismatch straight back into the gate. Background
        // localization, when enabled, resumes on its normal interval.
        if config.backgroundLocalization {
            scheduleBackgroundLocalization()
        }
    }

    private func logPoseConsistency(_ decision: PoseConsistencyGate.Decision) {
        let verdict = decision.accepted ? "ACCEPT" : "REJECT"
        var line = String(
            format: "MultiSetVPS >> Pose consistency %@ — jump %.1f m, threshold %.1f m (%@)",
            verdict, decision.jumpMeters, decision.thresholdMeters, decision.reason
        )

        // Printed on every fix, accepted ones included: the jump distance is what a
        // threshold gets tuned against, and the agreement count shows whether repeated
        // rejections are landing in the same wrong place or scattering.
        if decision.agreements > 0 {
            line += " [\(decision.agreements) agreeing rejections so far]"
        }

        print(line)
    }

    private func handleLocalizationFailure(message: String, reestablishing: Bool = false) {
        isLocalizing = false
        isCapturingFrames = false
        isWaitingForAPI = false

        if config.firstLocalizationUntilSuccess && isFirstLocalization && !isBackgroundRequest {
            print("MultiSetVPS >> First localization failed, retrying silently...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startLocalization()
            }
            return
        }

        print("MultiSetVPS >> Localization failed: \(message)")

        // Re-establishing is not a failure. An ARKit discontinuity — backgrounding the
        // app, a relocalization — invalidated the reference, and the gate is asking for a
        // second agreeing fix before it trusts a pose again. Retry quietly and report
        // nothing yet: a routine resume must not raise "Localization Failed" at the user.
        //
        // Deliberately ahead of the `backgroundLocalization` check below — recovering the
        // anchor is correctness, not periodic refresh, so it must also work for hosts that
        // localize on demand only.
        if reestablishing && reestablishRetryCount < Self.maxReestablishRetries {
            reestablishRetryCount += 1
            print("MultiSetVPS >> Re-establishing pose reference, retrying (\(reestablishRetryCount)/\(Self.maxReestablishRetries))")
            scheduleReestablishRetry()
            return
        }

        if reestablishing {
            print("MultiSetVPS >> Re-establish attempts exhausted, reporting failure")
        }

        resultCallback?(false, "Localization Failed!", nil)

        guard config.backgroundLocalization else { return }

        scheduleBackgroundLocalization()
    }

    private func scheduleReestablishRetry() {
        backgroundLocalizationTimer?.invalidate()

        // Whether the run was user-initiated has to survive the retry: forcing it to look
        // like a background request hides the capture overlay from someone standing there
        // waiting for the pose they asked for.
        let wasBackgroundRequest = isBackgroundRequest

        backgroundLocalizationTimer = Timer.scheduledTimer(withTimeInterval: Self.reestablishRetryDelay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isLocalizing else { return }

            // Backgrounded mid-retry: hand back to the periodic loop if there is one,
            // otherwise stop and let the next explicit localize resume the recovery.
            guard UIApplication.shared.applicationState == .active else {
                if self.config.backgroundLocalization {
                    self.scheduleBackgroundLocalization()
                }
                return
            }

            self.isBackgroundRequest = wasBackgroundRequest
            self.beginLocalization()
        }
    }

    private func calculateResultPose(
        estimatedPose: MultiFrameLocalizationResponse.EstimatedPose,
        trackingPose: MultiFrameLocalizationResponse.TrackingPose
    ) -> (position: SIMD3<Float>, rotation: simd_quatf) {
        let estPosition = estimatedPose.position.toSIMD3()
        let estRotation = estimatedPose.rotation.toQuaternion()

        let trackPosition = trackingPose.position.toSIMD3()
        let trackRotation = trackingPose.rotation.toQuaternion()

        let estRotMatrix = simd_float4x4(estRotation)
        var estMatrix = estRotMatrix
        estMatrix.columns.3 = SIMD4<Float>(estPosition.x, estPosition.y, estPosition.z, 1.0)
        let invEstMatrix = estMatrix.inverse

        let trackRotMatrix = simd_float4x4(trackRotation)
        var trackMatrix = trackRotMatrix
        trackMatrix.columns.3 = SIMD4<Float>(trackPosition.x, trackPosition.y, trackPosition.z, 1.0)

        let resultMatrix = trackMatrix * invEstMatrix

        let resultPosition = SIMD3<Float>(
            resultMatrix.columns.3.x,
            resultMatrix.columns.3.y,
            resultMatrix.columns.3.z
        )

        let resultRotation = simd_quatf(resultMatrix)

        return (resultPosition, resultRotation)
    }

    private func scheduleBackgroundLocalization() {
        backgroundLocalizationTimer?.invalidate()

        backgroundLocalizationTimer = Timer.scheduledTimer(withTimeInterval: config.bgLocalizationDuration, repeats: false) { [weak self] _ in
            guard let self = self, !self.isLocalizing else { return }

            // Don't localize when app is in the background
            guard UIApplication.shared.applicationState == .active else {
                print("MultiSetVPS >> Skipping background localization - app not active")
                self.scheduleBackgroundLocalization()
                return
            }

            print("MultiSetVPS >> Starting background localization")
            self.isBackgroundRequest = true
            self.beginLocalization()
        }
    }
}

// MARK: - simd_float4x4 Extension

extension simd_float4x4 {
    init(_ quaternion: simd_quatf) {
        let q = quaternion.vector
        let x = q.x, y = q.y, z = q.z, w = q.w

        let xx = x * x
        let yy = y * y
        let zz = z * z
        let xy = x * y
        let xz = x * z
        let yz = y * z
        let wx = w * x
        let wy = w * y
        let wz = w * z

        self.init(columns: (
            SIMD4<Float>(1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy), 0),
            SIMD4<Float>(2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx), 0),
            SIMD4<Float>(2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }
}
