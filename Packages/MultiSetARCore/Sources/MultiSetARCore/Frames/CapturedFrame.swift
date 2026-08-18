import CoreGraphics
import Foundation
import MultiSetKit
import simd

/// One ARKit frame, reduced to what the query endpoints need. Held as JPEG data
/// rather than a pixel buffer so a batch of frames does not pin camera memory.
public struct CapturedFrame: Sendable {
    public let jpegData: Data
    public let intrinsics: CameraIntrinsics
    public let resolution: Resolution
    /// The device pose in the ARKit world frame at capture time.
    public let cameraTransform: simd_float4x4
    public let timestamp: TimeInterval

    public init(
        jpegData: Data,
        intrinsics: CameraIntrinsics,
        resolution: Resolution,
        cameraTransform: simd_float4x4,
        timestamp: TimeInterval
    ) {
        self.jpegData = jpegData
        self.intrinsics = intrinsics
        self.resolution = resolution
        self.cameraTransform = cameraTransform
        self.timestamp = timestamp
    }

    public var queryFrame: QueryFrame {
        QueryFrame(jpegData: jpegData, pose: PoseTransform.pose(from: cameraTransform))
    }
}

/// Scales camera intrinsics when the captured image is resized before upload.
/// Sending full-resolution intrinsics with a downscaled image is a silent
/// accuracy bug, so the two are always transformed together.
public enum IntrinsicsScaling {
    public static func scaled(
        _ intrinsics: CameraIntrinsics,
        from source: Resolution,
        to target: Resolution
    ) -> CameraIntrinsics {
        guard source.width > 0, source.height > 0 else { return intrinsics }
        let sx = Double(target.width) / Double(source.width)
        let sy = Double(target.height) / Double(source.height)
        return CameraIntrinsics(
            fx: intrinsics.fx * sx,
            fy: intrinsics.fy * sy,
            px: intrinsics.px * sx,
            py: intrinsics.py * sy
        )
    }

    /// The longest edge the query image should have. Larger costs upload time
    /// without measurably improving the match.
    public static let maxUploadEdge = 960

    public static func uploadResolution(for source: Resolution) -> Resolution {
        let longest = max(source.width, source.height)
        guard longest > maxUploadEdge, longest > 0 else { return source }
        let scale = Double(maxUploadEdge) / Double(longest)
        return Resolution(
            width: max(1, Int((Double(source.width) * scale).rounded())),
            height: max(1, Int((Double(source.height) * scale).rounded()))
        )
    }
}
