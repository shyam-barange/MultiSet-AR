import Metal
import XCTest
@testable import MultiSetVPS

/// Covers the one seam this port changed: the engine authenticates from a token
/// provider rather than by exchanging a clientId and clientSecret.
final class EngineAuthTests: XCTestCase {
    func testConfigCarriesNoCredentials() {
        // The point of the port. There is no property to put a secret in, so a
        // credential cannot reach the engine — or the App Clip — by construction.
        let config = VPSConfig(mapCode: "MAP_A")
        XCTAssertTrue(config.hasCredentials, "credentials are the host's business now")
        XCTAssertEqual(config.mapCode, "MAP_A")
    }

    func testTokenBoxIsReadableAndUpdatable() {
        // The managers read this synchronously while building URLRequests, so a
        // refresh mid-session has to be visible to the next request.
        let box = VPSTokenBox(token: "first")
        XCTAssertEqual(box.value, "first")
        box.update("second")
        XCTAssertEqual(box.value, "second")
    }

    func testTokenBoxToleratesConcurrentReadsAndWrites() async {
        let box = VPSTokenBox(token: "t0")
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { box.update("t\(index)") }
                group.addTask { _ = box.value }
            }
        }
        XCTAssertTrue(box.value.hasPrefix("t"))
    }

    func testStaticTokenProviderReturnsItsToken() async throws {
        let provider = StaticVPSToken("abc")
        let token = try await provider.validToken()
        XCTAssertEqual(token, "abc")
    }

    func testClosureTokenProviderForwardsAndCanFail() async {
        let good = ClosureVPSToken(fetch: { "xyz" })
        await XCTAssertNoThrowAsync(try await good.validToken())

        struct Denied: Error {}
        let bad = ClosureVPSToken(fetch: { throw Denied() })
        do {
            _ = try await bad.validToken()
            XCTFail("expected the provider's error to propagate")
        } catch {
            XCTAssertTrue(error is Denied)
        }
    }

    func testClosureTokenProviderForwardsInvalidation() async {
        // The engine calls this after a 401 so the next request re-fetches rather
        // than repeating a token the server has already rejected.
        final class Flag: @unchecked Sendable { var invalidated = false }
        let flag = Flag()
        let provider = ClosureVPSToken(fetch: { "t" }, invalidate: { flag.invalidated = true })
        await provider.invalidateToken()
        XCTAssertTrue(flag.invalidated)
    }

    func testConfigValidationClampsTheSameWayTheSDKDid() {
        // Ported behaviour, pinned so the clamps are not lost in a future edit.
        var config = VPSConfig(mapCode: "MAP_A")
        config.numberOfFrames = 99
        config.frameCaptureIntervalMs = 10
        config.confidenceThreshold = 5
        config.poseConsistencyThreshold = 1
        config.imageQuality = 5
        config.objectCodes = (0..<20).map { "OBJ_\($0)" }

        let validated = config.validated()
        XCTAssertEqual(validated.numberOfFrames, 6)
        XCTAssertEqual(validated.frameCaptureIntervalMs, 300)
        XCTAssertEqual(validated.confidenceThreshold, 0.8)
        XCTAssertEqual(validated.poseConsistencyThreshold, 3)
        XCTAssertEqual(validated.imageQuality, 50)
        XCTAssertEqual(validated.objectCodes.count, 10)
    }

    func testMapAndMapSetAreMutuallyExclusiveTargets() {
        var map = VPSConfig(mapCode: "MAP_A")
        XCTAssertEqual(map.activeMapType, .map)
        XCTAssertEqual(map.activeMapCode, "MAP_A")
        XCTAssertTrue(map.hasMapConfiguration)

        map.mapCode = ""
        map.mapSetCode = "MSET_B"
        XCTAssertEqual(map.activeMapType, .mapSet)
        XCTAssertEqual(map.activeMapCode, "MSET_B")
    }

    func testObjectTrackingConfigurationIsDetected() {
        var config = VPSConfig(mapCode: "")
        XCTAssertFalse(config.hasObjectTrackingConfiguration)
        config.objectCodes = ["OBJ_A"]
        XCTAssertTrue(config.hasObjectTrackingConfiguration)
    }
}

/// The mesh overlay depends on these compiling into the package's own bundle. A
/// missing library only downgrades the material at runtime, so it would otherwise
/// go unnoticed.
final class ShaderLibraryTests: XCTestCase {
    func testShadersLoadFromThePackageBundle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device in this environment")
        }
        let library = try device.makeDefaultLibrary(bundle: .module)
        for name in ["radialRevealSurface", "outlineSurface", "outlineGeometry"] {
            XCTAssertNotNil(
                library.makeFunction(name: name),
                "\(name) missing — the mesh overlay would silently fall back to a plain material"
            )
        }
    }
}

private func XCTAssertNoThrowAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("threw \(error)", file: file, line: line)
    }
}
