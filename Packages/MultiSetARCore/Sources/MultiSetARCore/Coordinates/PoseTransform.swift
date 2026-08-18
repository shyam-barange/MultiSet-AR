import Foundation
import MultiSetKit
import simd

/// Converts between the map's coordinate frame and the ARKit world frame.
///
/// A VPS result is the pose of the *camera* expressed in map space. Anchoring
/// content means inverting that and composing it with the ARKit pose of the same
/// camera at the same instant:
///
///     worldFromMap = worldFromCamera · (mapFromCamera)⁻¹
///
/// Getting "at the same instant" right is the part that matters. A multi-frame
/// query takes several hundred milliseconds, during which the device moves. The
/// server returns `trackingPose` — the ARKit pose it actually matched against —
/// so that is used in preference to wherever the camera is by the time the reply
/// lands. Using the live transform instead bakes in an error equal to however far
/// the user walked mid-query.
public enum PoseTransform {
    public static func matrix(position: Position, rotation: Rotation) -> simd_float4x4 {
        var matrix = simd_float4x4(simd_quatf(
            ix: Float(rotation.x),
            iy: Float(rotation.y),
            iz: Float(rotation.z),
            r: Float(rotation.w)
        ).normalized)
        matrix.columns.3 = SIMD4<Float>(
            Float(position.x),
            Float(position.y),
            Float(position.z),
            1
        )
        return matrix
    }

    public static func matrix(_ pose: Pose) -> simd_float4x4 {
        matrix(position: pose.position, rotation: pose.rotation)
    }

    public static func pose(from transform: simd_float4x4) -> Pose {
        Pose(
            position: Position(transform.translation),
            rotation: Rotation(simd_quatf(transform.rotationOnly).normalized)
        )
    }

    /// The transform that places map-space content into the ARKit world.
    ///
    /// - Parameter liveCameraTransform: where the camera is now, used only when
    ///   the response carried no `trackingPose` (single-frame queries).
    public static func worldFromMap(
        result: LocalizationResult,
        liveCameraTransform: simd_float4x4
    ) -> simd_float4x4 {
        let mapFromCamera = matrix(result.pose)
        let worldFromCamera = result.trackingPose.map(matrix) ?? liveCameraTransform
        return worldFromCamera * mapFromCamera.inverse
    }

    /// Places a single map-space point into the ARKit world.
    public static func worldPosition(
        ofMapPoint point: Position,
        worldFromMap: simd_float4x4
    ) -> SIMD3<Float> {
        (worldFromMap * SIMD4<Float>(point.simd, 1)).xyz
    }

    /// Expresses an ARKit world position back in map space, for authoring a POI
    /// at wherever the user is standing.
    public static func mapPosition(
        ofWorldPoint point: SIMD3<Float>,
        worldFromMap: simd_float4x4
    ) -> Position {
        Position((worldFromMap.inverse * SIMD4<Float>(point, 1)).xyz)
    }

    /// Flips the Z axis to convert between right- and left-handed conventions.
    ///
    /// Not used on the happy path: ARKit is right-handed and the query endpoints
    /// take `isRightHanded`, so the server should already answer in ARKit's
    /// convention. Kept because the SDK documentation only ever shows Unity
    /// sending `isRightHanded=false`, so whether the flag is honoured for native
    /// clients is unverified against a live map. If poses come back mirrored,
    /// this is the correction.
    public static func flippingHandedness(_ transform: simd_float4x4) -> simd_float4x4 {
        let flip = simd_float4x4(diagonal: SIMD4<Float>(1, 1, -1, 1))
        return flip * transform * flip
    }
}

public extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// The rotation basis with translation and any scale removed.
    var rotationOnly: simd_float3x3 {
        simd_float3x3(
            simd_normalize(SIMD3(columns.0.x, columns.0.y, columns.0.z)),
            simd_normalize(SIMD3(columns.1.x, columns.1.y, columns.1.z)),
            simd_normalize(SIMD3(columns.2.x, columns.2.y, columns.2.z))
        )
    }

    /// The direction the camera looks in ARKit's convention, which is -Z.
    var forward: SIMD3<Float> {
        simd_normalize(SIMD3(-columns.2.x, -columns.2.y, -columns.2.z))
    }
}

public extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
