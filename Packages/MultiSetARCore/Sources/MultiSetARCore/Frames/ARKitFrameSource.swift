import ARKit
import CoreImage
import Foundation
import MultiSetKit
import simd
import UIKit

/// Captures frames from a live `ARSession`.
///
/// Frames are downscaled and JPEG-encoded off the main actor, and intrinsics are
/// scaled with them — sending full-resolution intrinsics alongside a downscaled
/// image is a silent accuracy bug rather than a visible failure.
public final class ARKitFrameSource: NSObject, FrameSource, @unchecked Sendable {
    private weak var session: ARSession?
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let lock = NSLock()

    public init(session: ARSession?) {
        self.session = session
        super.init()
    }

    public func attach(session: ARSession?) {
        lock.withLock { self.session = session }
    }

    private var currentFrame: ARFrame? {
        lock.withLock { session }?.currentFrame
    }

    public var isReadyToCapture: Bool {
        guard let frame = currentFrame else { return false }
        return frame.camera.trackingState.isUsable
    }

    public var trackingStateDescription: String {
        currentFrame?.camera.trackingState.shortDescription ?? "unavailable"
    }

    public var currentCameraTransform: simd_float4x4? {
        currentFrame?.camera.transform
    }

    public func captureFrames(count: Int, interval: Duration, quality: Double) async throws -> [CapturedFrame] {
        guard count > 0 else { return [] }
        var captured: [CapturedFrame] = []

        for index in 0..<count {
            if index > 0 {
                try await Task.sleep(for: interval)
            }
            try Task.checkCancellation()
            guard let frame = currentFrame, frame.camera.trackingState.isUsable else { continue }
            if let encoded = encode(frame: frame, quality: quality) {
                captured.append(encoded)
            }
        }

        guard !captured.isEmpty else {
            throw MultiSetError.notLocalized(
                message: "The camera didn't get a usable frame. Move the device slowly and try again."
            )
        }
        return captured
    }

    private func encode(frame: ARFrame, quality: Double) -> CapturedFrame? {
        let buffer = frame.capturedImage
        let sourceResolution = Resolution(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer)
        )
        let targetResolution = IntrinsicsScaling.uploadResolution(for: sourceResolution)

        var image = CIImage(cvPixelBuffer: buffer)
        if targetResolution != sourceResolution {
            let scale = Double(targetResolution.width) / Double(sourceResolution.width)
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(
                  of: image,
                  colorSpace: colorSpace,
                  options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
              )
        else { return nil }

        let matrix = frame.camera.intrinsics
        let sourceIntrinsics = CameraIntrinsics(
            fx: Double(matrix[0][0]),
            fy: Double(matrix[1][1]),
            px: Double(matrix[2][0]),
            py: Double(matrix[2][1])
        )

        return CapturedFrame(
            jpegData: jpeg,
            intrinsics: IntrinsicsScaling.scaled(
                sourceIntrinsics,
                from: sourceResolution,
                to: targetResolution
            ),
            resolution: targetResolution,
            cameraTransform: frame.camera.transform,
            timestamp: frame.timestamp
        )
    }
}

extension ARCamera.TrackingState {
    var isUsable: Bool {
        switch self {
        case .normal: true
        // Localization needs a stable pose; excessive motion or initialising
        // tracking produces frames whose pose metadata is not trustworthy.
        case .limited(let reason): reason == .insufficientFeatures
        case .notAvailable: false
        }
    }

    var shortDescription: String {
        switch self {
        case .normal: "normal"
        case .notAvailable: "unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "initializing"
            case .excessiveMotion: "excessive motion"
            case .insufficientFeatures: "few features"
            case .relocalizing: "relocalizing"
            @unknown default: "limited"
            }
        }
    }
}
