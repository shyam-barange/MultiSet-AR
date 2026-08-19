import SwiftUI
import XCTest
@testable import MultiSetUI

/// Catches a renamed, unmembered, or mis-bundled asset here rather than as a blank
/// rectangle in a demo.
final class StateArtTests: XCTestCase {
    func testEveryStateArtCaseLoadsFromThePackageBundle() {
        for art in StateArt.allCases {
            XCTAssertTrue(
                art.exists,
                "\(art.assetName) did not load from Bundle.module — check StateArt.xcassets membership and Package.swift resources"
            )
        }
    }

    func testStateArtResolvesAgainstThePackageBundleNotTheMainBundle() {
        // A package view looking in the main bundle is the classic silent failure,
        // so the bundle is asserted rather than assumed.
        XCTAssertEqual(StateArt.bundle, .module)
        XCTAssertNil(HomeImage.bundle, "Home imagery belongs to the app target")
        XCTAssertNil(OnboardingImage.bundle, "content imagery belongs to the app target")
        XCTAssertNil(LearnImage.bundle, "content imagery belongs to the app target")
    }

    func testStateArtPreservesVectorDataSoItScalesWithoutBlurring() throws {
        // Without preserves-vector-representation the SVG rasterises at its
        // intrinsic size and blurs when Dynamic Type scales it up.
        for art in StateArt.allCases {
            let image = try XCTUnwrap(art.uiImage, art.assetName)
            XCTAssertTrue(
                image.isSymbolImage || image.imageAsset != nil,
                "\(art.assetName) has no image asset backing"
            )
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testStateArtRendersAsTemplateSoItTakesATint() throws {
        for art in StateArt.allCases {
            let image = try XCTUnwrap(art.uiImage, art.assetName)
            XCTAssertEqual(
                image.renderingMode,
                .alwaysTemplate,
                "\(art.assetName) is not a template image, so .foregroundStyle() will not tint it"
            )
        }
    }

    func testEveryCaseHasAFallbackIllustration() {
        // The fallback is what keeps a missing asset from leaving an empty frame.
        for art in StateArt.allCases {
            XCTAssertNotNil(art.fallbackIllustration)
        }
    }

    func testAssetNamesAreUniqueAcrossEveryCatalogEnum() {
        let names = HomeImage.allCases.map(\.assetName)
            + OnboardingImage.allCases.map(\.assetName)
            + LearnImage.allCases.map(\.assetName)
            + StateArt.allCases.map(\.assetName)
        XCTAssertEqual(Set(names).count, names.count, "duplicate asset name would shadow one of them")
    }

    func testAssetNamesAreKebabCaseMatchingTheCatalogLayout() {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for name in HomeImage.allCases.map(\.assetName)
            + OnboardingImage.allCases.map(\.assetName)
            + LearnImage.allCases.map(\.assetName)
            + StateArt.allCases.map(\.assetName) {
            XCTAssertTrue(
                name.unicodeScalars.allSatisfy(allowed.contains),
                "\(name) does not match the catalog's kebab-case naming"
            )
        }
    }

    func testLearnODRTagMatchesTheCatalogTag() {
        // Drift here means the fetch requests a tag no asset carries and silently
        // returns nothing.
        XCTAssertEqual(LearnImage.onDemandResourceTag, "learn-content")
    }

    func testCoverageMatchesTheProducedAssetSet() {
        XCTAssertEqual(HomeImage.allCases.count, 1)
        XCTAssertEqual(OnboardingImage.allCases.count, 3)
        XCTAssertEqual(LearnImage.allCases.count, 6)
        XCTAssertEqual(StateArt.allCases.count, 4)
    }
}
