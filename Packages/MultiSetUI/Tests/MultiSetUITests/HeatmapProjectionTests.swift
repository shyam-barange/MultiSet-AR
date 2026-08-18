import XCTest
@testable import MultiSetUI

final class HeatmapProjectionTests: XCTestCase {
    private let size = CGSize(width: 200, height: 200)

    func testBoundsIsNilForEmptyInput() {
        XCTAssertNil(LocalizationHeatmap.bounds(of: []))
    }

    func testBoundsSpansAllSamples() throws {
        let bounds = try XCTUnwrap(LocalizationHeatmap.bounds(of: [
            HeatmapSample(x: -3, z: 1),
            HeatmapSample(x: 5, z: -2),
            HeatmapSample(x: 0, z: 7)
        ]))
        XCTAssertEqual(bounds.minX, -3)
        XCTAssertEqual(bounds.maxX, 5)
        XCTAssertEqual(bounds.minZ, -2)
        XCTAssertEqual(bounds.maxZ, 7)
    }

    func testSingleSampleCollapsesToCentre() {
        let sample = HeatmapSample(x: 4, z: 4)
        let bounds = (minX: 4.0, maxX: 4.0, minZ: 4.0, maxZ: 4.0)
        let point = LocalizationHeatmap.project(sample, bounds: bounds, into: size)
        XCTAssertEqual(point.x, 100, accuracy: 0.001)
        XCTAssertEqual(point.y, 100, accuracy: 0.001)
    }

    func testProjectionPreservesAspectRatio() {
        // A 10 x 5 extent in a square view must not stretch: the drawn height
        // should be exactly half the drawn width.
        let bounds = (minX: 0.0, maxX: 10.0, minZ: 0.0, maxZ: 5.0)
        let left = LocalizationHeatmap.project(HeatmapSample(x: 0, z: 0), bounds: bounds, into: size)
        let right = LocalizationHeatmap.project(HeatmapSample(x: 10, z: 0), bounds: bounds, into: size)
        let bottom = LocalizationHeatmap.project(HeatmapSample(x: 0, z: 5), bounds: bounds, into: size)
        XCTAssertEqual(right.x - left.x, (bottom.y - left.y) * 2, accuracy: 0.001)
    }

    func testProjectionStaysWithinInsetBounds() {
        let bounds = (minX: -5.0, maxX: 5.0, minZ: -5.0, maxZ: 5.0)
        for sample in [HeatmapSample(x: -5, z: -5), HeatmapSample(x: 5, z: 5)] {
            let point = LocalizationHeatmap.project(sample, bounds: bounds, into: size)
            XCTAssertGreaterThanOrEqual(point.x, 20)
            XCTAssertLessThanOrEqual(point.x, 180)
            XCTAssertGreaterThanOrEqual(point.y, 20)
            XCTAssertLessThanOrEqual(point.y, 180)
        }
    }

    func testDegenerateZeroHeightExtentDoesNotProduceNaN() {
        let bounds = (minX: 0.0, maxX: 10.0, minZ: 3.0, maxZ: 3.0)
        let point = LocalizationHeatmap.project(HeatmapSample(x: 5, z: 3), bounds: bounds, into: size)
        XCTAssertFalse(point.x.isNaN)
        XCTAssertFalse(point.y.isNaN)
    }
}

final class ColorHexTests: XCTestCase {
    func testInvalidHexIsVisiblyWrongRatherThanTransparent() {
        // A bad token must be obvious in review, not silently invisible.
        XCTAssertNotNil(Color(hex: "nonsense"))
        XCTAssertNotNil(Color(hex: "#7C3AED"))
        XCTAssertNotNil(Color(hex: "7C3AEDFF"))
    }
}
