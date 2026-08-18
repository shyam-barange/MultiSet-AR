import XCTest
@testable import MultiSetKit

/// Decoding is verified against payloads copied from the live API documentation
/// and Postman collection, not against shapes invented for the test.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - Dates

    func testAcceptsFractionalSecondTimestamps() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"active",
         "createdAt":"2026-03-25T12:00:00.000Z"}
        """)
        XCTAssertNotNil(map.createdAt)
    }

    func testAcceptsWholeSecondTimestamps() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"active",
         "createdAt":"2026-03-25T12:00:00Z"}
        """)
        XCTAssertNotNil(map.createdAt)
    }

    func testRejectsUnparseableTimestamp() {
        XCTAssertThrowsError(try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"active","createdAt":"yesterday"}
        """))
    }

    // MARK: - Quaternion key spellings

    func testRotationDecodesXYZWSpelling() throws {
        let rotation = try decode(Rotation.self, #"{"x":0.1,"y":0.2,"z":0.3,"w":0.9}"#)
        XCTAssertEqual(rotation.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rotation.w, 0.9, accuracy: 1e-9)
    }

    func testRotationDecodesQXQYQZQWSpelling() throws {
        // MapSet relativePose uses this spelling; localization responses do not.
        let rotation = try decode(Rotation.self, #"{"qx":0.1,"qy":0.2,"qz":0.3,"qw":0.9}"#)
        XCTAssertEqual(rotation.x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(rotation.w, 0.9, accuracy: 1e-9)
    }

    func testRotationDefaultsToIdentityWhenKeysAreAbsent() throws {
        let rotation = try decode(Rotation.self, "{}")
        XCTAssertEqual(rotation.w, 1, accuracy: 1e-9)
        XCTAssertEqual(rotation.x, 0, accuracy: 1e-9)
    }

    func testMapSetRelativePoseUsesQPrefixedRotation() throws {
        let mapSet = try decode(MapSet.self, """
        {"_id":"64b","name":"Floor 1","mapSetCode":"MSET_X","status":"active",
         "mapSetData":[{"_id":"data_1","order":0,
           "relativePose":{"position":{"x":0,"y":4.2,"z":0},
                           "rotation":{"qx":0,"qy":0.7071,"qz":0,"qw":0.7071}}}]}
        """)
        let rotation = try XCTUnwrap(mapSet.mapSetData?.first?.relativePose?.rotation)
        XCTAssertEqual(rotation.y, 0.7071, accuracy: 1e-6)
        XCTAssertEqual(rotation.w, 0.7071, accuracy: 1e-6)
    }

    // MARK: - The two localization response shapes

    func testSingleFrameResponseWithInlinePositionNormalizes() throws {
        let response = try decode(SingleFrameLocalizeResponse.self, """
        {"poseFound":true,
         "localizationSuccess":{"poseFound":true,
           "position":{"x":1.23,"y":0.45,"z":-2.67},
           "rotation":{"x":0.01,"y":0.99,"z":0.02,"w":-0.05},
           "confidence":0.87,"mapIds":["64a"],"mapCodes":["MAP_7UVHMW2TJMOA"]},
         "localizationFailure":null}
        """)
        let result = try response.normalized(latency: .milliseconds(310))
        XCTAssertEqual(result.pose.position.x, 1.23, accuracy: 1e-9)
        XCTAssertEqual(result.confidence, 0.87)
        XCTAssertEqual(result.primaryMapCode, "MAP_7UVHMW2TJMOA")
        XCTAssertEqual(result.mode, .singleFrame)
    }

    func testSingleFrameResponseWithNestedEstimatedPoseNormalizes() throws {
        // The dashboard-era shape nests the pose under estimatedPose instead.
        let response = try decode(SingleFrameLocalizeResponse.self, """
        {"poseFound":true,
         "localizationSuccess":{"poseFound":true,
           "estimatedPose":{"position":{"x":5,"y":6,"z":7},
                            "rotation":{"x":0,"y":0,"z":0,"w":1}},
           "confidence":0.5}}
        """)
        let result = try response.normalized(latency: .zero)
        XCTAssertEqual(result.pose.position.z, 7, accuracy: 1e-9)
    }

    func testSingleFrameFailureThrowsNotLocalizedWithServerMessage() throws {
        let response = try decode(SingleFrameLocalizeResponse.self, """
        {"poseFound":false,"localizationSuccess":null,
         "localizationFailure":{"poseFound":false,"message":"Could not localize the image"}}
        """)
        XCTAssertThrowsError(try response.normalized(latency: .zero)) { error in
            XCTAssertEqual(
                error as? MultiSetError,
                .notLocalized(message: "Could not localize the image")
            )
        }
    }

    func testMultiFrameResponseUsesTopLevelPose() throws {
        let response = try decode(MultiFrameLocalizeResponse.self, """
        {"poseFound":true,
         "estimatedPose":{"position":{"x":1.23,"y":0.45,"z":-2.67},
                          "rotation":{"x":0.01,"y":0.99,"z":0.02,"w":-0.05}},
         "trackingPose":{"position":{"x":0.10,"y":1.13,"z":-0.02},
                         "rotation":{"x":-0.01,"y":0.10,"z":0.00,"w":-0.99}},
         "confidence":0.92,"mapIds":["64a"],"mapCodes":["MAP_7UVHMW2TJMOA"]}
        """)
        let result = try response.normalized(latency: .milliseconds(640))
        XCTAssertEqual(result.pose.position.x, 1.23, accuracy: 1e-9)
        XCTAssertNotNil(result.trackingPose)
        XCTAssertEqual(result.mode, .multiFrame)
    }

    func testMultiFrameResponseWithoutPoseThrows() throws {
        let response = try decode(MultiFrameLocalizeResponse.self, #"{"poseFound":false}"#)
        XCTAssertThrowsError(try response.normalized(latency: .zero))
    }

    func testObjectTrackingResponseNormalizes() throws {
        let response = try decode(ObjectTrackingResponse.self, """
        {"poseFound":true,"position":{"x":0.5,"y":0.3,"z":-1.2},
         "rotation":{"x":0,"y":0.7,"z":0,"w":0.7},
         "confidence":0.95,"objectCodes":["OBJ_XXXXX"]}
        """)
        let result = try response.normalized(latency: .zero)
        XCTAssertEqual(result.primaryObjectCode, "OBJ_XXXXX")
        XCTAssertEqual(result.confidence, 0.95)
    }

    // MARK: - Map detail

    func testMapDetailDecodesDoublyNestedIntrinsics() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"64a","accountId":"acc","mapName":"Office Map",
         "location":{"type":"Point","coordinates":[-122.4194,37.7749]},
         "status":"active","storage":185.5,"mapCode":"MAP_7UVHMW2TJMOA",
         "source":{"provider":"multiset","fileType":"e57","coordinateSystem":"left-handed"},
         "cameraIntrinsics":{"camera_intrinsics":{"fx":667.79,"fy":667.79,"px":361.05,"py":481.82},
                             "resolution":{"width":720,"height":960}},
         "mapMesh":{"_id":"m","rawMesh":{"type":"glb","meshLink":"maps/raw/abc.glb"}},
         "thumbnail":"t.jpg","heading":45.0,
         "offlineBundleStatus":"active","offlineBundle":"bundles/x.bytes"}
        """)
        XCTAssertEqual(map.cameraIntrinsics?.cameraIntrinsics?.fx ?? 0, 667.79, accuracy: 1e-6)
        XCTAssertEqual(map.cameraIntrinsics?.resolution?.height, 960)
        XCTAssertTrue(map.hasOfflineBundle)
        XCTAssertEqual(map.source?.captureKind, "E57 point cloud")
    }

    func testGeoJSONCoordinatesAreLongitudeFirst() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"active",
         "location":{"type":"Point","coordinates":[-122.4194,37.7749]}}
        """)
        let geo = try XCTUnwrap(map.geoPosition)
        XCTAssertEqual(geo.latitude, 37.7749, accuracy: 1e-6)
        XCTAssertEqual(geo.longitude, -122.4194, accuracy: 1e-6)
        XCTAssertTrue(map.isGeoreferenced)
    }

    func testMapWithoutGeoreferenceIsNotMarkedGeoreferenced() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"active",
         "coordinates":{"latitude":0,"longitude":0,"altitude":0}}
        """)
        XCTAssertFalse(map.isGeoreferenced)
    }

    func testUnrecognisedStatusFallsBackRatherThanThrowing() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"quantum-superposition"}
        """)
        XCTAssertEqual(map.status, .unknown)
        XCTAssertFalse(map.status.isReady)
    }

    func testStatusDecodingIsCaseInsensitive() throws {
        let map = try decode(VPSMap.self, """
        {"_id":"1","mapCode":"MAP_A","mapName":"A","status":"ACTIVE"}
        """)
        XCTAssertEqual(map.status, .active)
    }

    // MARK: - Auth and content

    func testLoginResponseDecodes() throws {
        let response = try decode(LoginResponse.self, """
        {"accessToken":{"token":"a","expiresOn":"2026-08-19T12:00:00.000Z"},
         "refreshToken":{"token":"r","expiresOn":"2026-09-19T12:00:00.000Z"},
         "userId":"usr_1"}
        """)
        XCTAssertEqual(response.accessToken.token, "a")
        XCTAssertEqual(response.userId, "usr_1")
    }

    func testM2MTokenResponseDecodes() throws {
        let token = try decode(AuthToken.self, """
        {"token":"eyJhbGciOiJIUzI1NiIs","expiresOn":"2026-03-25T12:00:00.000Z"}
        """)
        XCTAssertEqual(token.token, "eyJhbGciOiJIUzI1NiIs")
    }

    func testLocationPinContentDecodesAsPointOfInterest() throws {
        let content = try decode(SpaceContent.self, """
        {"_id":"c1","contentSpaceId":"s1","title":"Dispatch","type":"location_pin",
         "position":{"x":11.8,"y":0,"z":-7.2},
         "rotation":{"x":0,"y":0,"z":0,"w":1},"scale":{"x":1,"y":1,"z":1}}
        """)
        XCTAssertEqual(content.type, .locationPin)
        XCTAssertTrue(content.isPointOfInterest)
        XCTAssertNotNil(PointOfInterest(content: content))
    }

    func testTextContentIsNotAPointOfInterest() throws {
        let content = try decode(SpaceContent.self, """
        {"_id":"c2","title":"Notice","type":"text","position":{"x":0,"y":0,"z":0}}
        """)
        XCTAssertNil(PointOfInterest(content: content))
    }

    func testContentSpaceShareURLMatchesPlatformFormat() {
        let space = ContentSpace(id: "s", name: "N", spaceCode: "k7m2p9xq")
        XCTAssertEqual(space.shareURL?.absoluteString, "https://app.multiset.ai/space/k7m2p9xq")
    }

    func testHeatmapResponseAcceptsAnyOfItsThreeArrayKeys() throws {
        for key in ["heatmap", "data", "cells"] {
            let response = try decode(HeatmapResponse.self, """
            {"\(key)":[{"x":1,"z":2,"count":3,"successCount":3,"failureCount":0}]}
            """)
            XCTAssertEqual(response.allCells.count, 1, "failed for key \(key)")
        }
    }

    func testQueryRecordPageAcceptsEitherArrayKey() throws {
        for key in ["queries", "data"] {
            let page = try decode(QueryRecordPage.self, #"{"\#(key)":[{"_id":"q1"}]}"#)
            XCTAssertEqual(page.records.count, 1, "failed for key \(key)")
        }
    }
}
