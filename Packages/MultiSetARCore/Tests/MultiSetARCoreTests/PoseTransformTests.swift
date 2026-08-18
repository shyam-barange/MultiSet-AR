import XCTest
import MultiSetKit
import simd
@testable import MultiSetARCore

final class PoseTransformTests: XCTestCase {
    private func assertClose(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ message: String = "",
        accuracy: Float = 1e-4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, message, file: file, line: line)
    }

    private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(x, y, z, 1)
        return m
    }

    private func yaw(_ degrees: Float) -> simd_quatf {
        simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - Round trips

    func testMatrixAndPoseRoundTrip() {
        let pose = Pose(
            position: Position(x: 1.5, y: -0.25, z: 3.75),
            rotation: Rotation(yaw(37))
        )
        let recovered = PoseTransform.pose(from: PoseTransform.matrix(pose))
        XCTAssertEqual(recovered.position.x, 1.5, accuracy: 1e-4)
        XCTAssertEqual(recovered.position.y, -0.25, accuracy: 1e-4)
        XCTAssertEqual(recovered.position.z, 3.75, accuracy: 1e-4)
        // Quaternions are double-cover, so compare the rotation they produce.
        let original = PoseTransform.matrix(pose).rotationOnly
        let round = PoseTransform.matrix(recovered).rotationOnly
        let probe = SIMD3<Float>(1, 2, 3)
        assertClose(original * probe, round * probe)
    }

    func testMapAndWorldPositionRoundTrip() {
        let worldFromMap = PoseTransform.matrix(
            position: Position(x: 4, y: 0, z: -2),
            rotation: Rotation(yaw(65))
        )
        let mapPoint = Position(x: 1.25, y: 0.5, z: -3)
        let world = PoseTransform.worldPosition(ofMapPoint: mapPoint, worldFromMap: worldFromMap)
        let back = PoseTransform.mapPosition(ofWorldPoint: world, worldFromMap: worldFromMap)
        XCTAssertEqual(back.x, mapPoint.x, accuracy: 1e-4)
        XCTAssertEqual(back.y, mapPoint.y, accuracy: 1e-4)
        XCTAssertEqual(back.z, mapPoint.z, accuracy: 1e-4)
    }

    // MARK: - The core relation

    func testCameraAtMapOriginPutsMapOriginAtTheCamera() {
        // The camera sits at world (7, 0, 5) and reports being at the map origin,
        // so the map origin must land exactly at the camera.
        let result = LocalizationResult(
            pose: Pose(
                position: Position(x: 0, y: 0, z: 0),
                rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
            ),
            mode: .singleFrame
        )
        let worldFromMap = PoseTransform.worldFromMap(
            result: result,
            liveCameraTransform: translation(7, 0, 5)
        )
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 0, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(7, 0, 5)
        )
    }

    func testMapPointOffsetFromTheCameraLandsAtTheSameOffsetInTheWorld() {
        // Camera is 3 m along map +X from the origin, with no rotation. A map
        // point at the origin must therefore appear 3 m behind the camera in X.
        let result = LocalizationResult(
            pose: Pose(
                position: Position(x: 3, y: 0, z: 0),
                rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
            ),
            mode: .singleFrame
        )
        let worldFromMap = PoseTransform.worldFromMap(
            result: result,
            liveCameraTransform: translation(10, 0, 0)
        )
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 0, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(7, 0, 0)
        )
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 3, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(10, 0, 0),
            "the camera's own map position must map back to the camera"
        )
    }

    func testRotationIsCarriedThroughTheTransform() {
        // Camera reports facing 90° yawed in map space while ARKit has it
        // unrotated, so map content must come back rotated by -90°.
        let result = LocalizationResult(
            pose: Pose(position: Position(x: 0, y: 0, z: 0), rotation: Rotation(yaw(90))),
            mode: .singleFrame
        )
        let worldFromMap = PoseTransform.worldFromMap(
            result: result,
            liveCameraTransform: matrix_identity_float4x4
        )
        // A point 1 m along map +X, viewed through a -90° yaw, lands on +Z.
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 1, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(0, 0, 1)
        )
    }

    /// The single most consequential detail in the transform: a multi-frame query
    /// takes hundreds of milliseconds, so the camera has moved by the time the
    /// reply lands. Anchoring against the live transform bakes in that motion.
    func testTrackingPoseIsPreferredOverTheLiveCameraTransform() {
        let result = LocalizationResult(
            pose: Pose(
                position: Position(x: 0, y: 0, z: 0),
                rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
            ),
            trackingPose: Pose(
                position: Position(x: 2, y: 0, z: 0),
                rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
            ),
            mode: .multiFrame
        )
        // The user walked 5 m during the query. The fix belongs at x = 2, where
        // the frames were taken, not at x = 7 where they now stand.
        let worldFromMap = PoseTransform.worldFromMap(
            result: result,
            liveCameraTransform: translation(7, 0, 0)
        )
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 0, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(2, 0, 0),
            "trackingPose must win, or the anchor drifts by however far the user moved"
        )
    }

    func testLiveTransformIsUsedWhenNoTrackingPoseWasReturned() {
        let result = LocalizationResult(
            pose: Pose(
                position: Position(x: 0, y: 0, z: 0),
                rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
            ),
            mode: .singleFrame
        )
        let worldFromMap = PoseTransform.worldFromMap(
            result: result,
            liveCameraTransform: translation(4, 1, -2)
        )
        assertClose(
            PoseTransform.worldPosition(ofMapPoint: Position(x: 0, y: 0, z: 0), worldFromMap: worldFromMap),
            SIMD3<Float>(4, 1, -2)
        )
    }

    // MARK: - Matrix helpers

    func testForwardFollowsARKitsNegativeZConvention() {
        assertClose(matrix_identity_float4x4.forward, SIMD3<Float>(0, 0, -1))
        var yawed = simd_float4x4(yaw(90))
        yawed.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        assertClose(yawed.forward, SIMD3<Float>(-1, 0, 0))
    }

    func testRotationOnlyStripsTranslationAndScale() {
        var scaled = simd_float4x4(diagonal: SIMD4<Float>(3, 3, 3, 1))
        scaled.columns.3 = SIMD4<Float>(9, 9, 9, 1)
        let basis = scaled.rotationOnly
        XCTAssertEqual(simd_length(basis.columns.0), 1, accuracy: 1e-5)
        XCTAssertEqual(simd_length(basis.columns.1), 1, accuracy: 1e-5)
        XCTAssertEqual(simd_length(basis.columns.2), 1, accuracy: 1e-5)
    }

    func testHandednessFlipIsItsOwnInverse() {
        let original = PoseTransform.matrix(
            position: Position(x: 1, y: 2, z: 3),
            rotation: Rotation(yaw(45))
        )
        let doubled = PoseTransform.flippingHandedness(PoseTransform.flippingHandedness(original))
        let probe = SIMD3<Float>(1, 1, 1)
        assertClose(
            (original * SIMD4<Float>(probe, 1)).xyz,
            (doubled * SIMD4<Float>(probe, 1)).xyz
        )
    }

    func testHandednessFlipNegatesZ() {
        let flipped = PoseTransform.flippingHandedness(translation(1, 2, 3))
        assertClose(flipped.translation, SIMD3<Float>(1, 2, -3))
    }
}

final class IntrinsicsScalingTests: XCTestCase {
    /// Sending unscaled intrinsics with a downscaled image is a silent accuracy
    /// bug — the server would place the pose using the wrong focal length.
    func testIntrinsicsScaleWithTheImage() {
        let source = Resolution(width: 1440, height: 1920)
        let target = Resolution(width: 720, height: 960)
        let scaled = IntrinsicsScaling.scaled(
            CameraIntrinsics(fx: 1335.59, fy: 1335.59, px: 722.1, py: 963.64),
            from: source,
            to: target
        )
        XCTAssertEqual(scaled.fx, 667.795, accuracy: 1e-3)
        XCTAssertEqual(scaled.fy, 667.795, accuracy: 1e-3)
        XCTAssertEqual(scaled.px, 361.05, accuracy: 1e-3)
        XCTAssertEqual(scaled.py, 481.82, accuracy: 1e-3)
    }

    func testScalingIsIdentityWhenResolutionIsUnchanged() {
        let intrinsics = CameraIntrinsics(fx: 100, fy: 200, px: 300, py: 400)
        let same = IntrinsicsScaling.scaled(
            intrinsics,
            from: Resolution(width: 640, height: 480),
            to: Resolution(width: 640, height: 480)
        )
        XCTAssertEqual(same.fx, 100, accuracy: 1e-9)
        XCTAssertEqual(same.py, 400, accuracy: 1e-9)
    }

    func testZeroSourceResolutionDoesNotProduceNaN() {
        let scaled = IntrinsicsScaling.scaled(
            CameraIntrinsics(fx: 1, fy: 1, px: 1, py: 1),
            from: Resolution(width: 0, height: 0),
            to: Resolution(width: 720, height: 960)
        )
        XCTAssertFalse(scaled.fx.isNaN)
        XCTAssertEqual(scaled.fx, 1, accuracy: 1e-9)
    }

    func testUploadResolutionCapsTheLongestEdgeAndKeepsAspect() {
        let capped = IntrinsicsScaling.uploadResolution(for: Resolution(width: 1440, height: 1920))
        XCTAssertEqual(max(capped.width, capped.height), IntrinsicsScaling.maxUploadEdge)
        XCTAssertEqual(
            Double(capped.width) / Double(capped.height),
            1440.0 / 1920.0,
            accuracy: 0.01
        )
    }

    func testUploadResolutionLeavesSmallImagesAlone() {
        let small = Resolution(width: 640, height: 480)
        XCTAssertEqual(IntrinsicsScaling.uploadResolution(for: small), small)
    }

    func testLandscapeAndPortraitAreBothCapped() {
        let landscape = IntrinsicsScaling.uploadResolution(for: Resolution(width: 1920, height: 1440))
        XCTAssertEqual(landscape.width, IntrinsicsScaling.maxUploadEdge)
        let portrait = IntrinsicsScaling.uploadResolution(for: Resolution(width: 1440, height: 1920))
        XCTAssertEqual(portrait.height, IntrinsicsScaling.maxUploadEdge)
    }
}
