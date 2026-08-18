import XCTest
@testable import MultiSetKit

final class ExperienceManifestBuilderTests: XCTestCase {
    private let token = AuthToken(token: "t", expiresOn: Date().addingTimeInterval(900))

    private func space(
        mapId: String? = "MAP_A",
        mapSetId: String? = nil,
        metadata: [String: ContentData] = [:]
    ) -> ContentSpace {
        ContentSpace(
            id: "s1",
            name: "Northfield DC",
            spaceCode: "k7m2p9xq",
            description: "A description",
            mapId: mapId,
            mapSetId: mapSetId,
            status: "published",
            isPublic: true,
            metadata: metadata
        )
    }

    private func poi(_ id: String, _ title: String) -> SpaceContent {
        SpaceContent(id: id, title: title, type: .locationPin, position: Position(x: 1, y: 0, z: 2))
    }

    func testMapSetTakesPrecedenceOverMapWhenBothArePresent() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(contentSpace: space(mapId: "MAP_A", mapSetId: "MSET_B"), contents: []),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.target, .mapSet(code: "MSET_B"))
    }

    func testSpaceWithNoMapIsReportedAsNotReady() {
        XCTAssertThrowsError(
            try ExperienceManifestBuilder.build(
                from: ContentSpaceDetail(contentSpace: space(mapId: nil), contents: []),
                token: token,
                spaceCode: "k7m2p9xq"
            )
        ) { error in
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.mapProcessing))
        }
    }

    func testEmptyMapIdStringIsTreatedAsAbsent() {
        XCTAssertThrowsError(
            try ExperienceManifestBuilder.build(
                from: ContentSpaceDetail(contentSpace: space(mapId: ""), contents: []),
                token: token,
                spaceCode: "k7m2p9xq"
            )
        )
    }

    // MARK: - Mode resolution

    func testDeclaredModeAlwaysWins() {
        let mode = ExperienceManifestBuilder.resolveMode(
            declared: "localize",
            hasPOIs: true,
            hasNavGraph: true,
            hasObjects: true
        )
        XCTAssertEqual(mode, .localize)
    }

    func testDeclaredModeIsCaseInsensitive() {
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: "NAVIGATE", hasPOIs: true, hasNavGraph: true, hasObjects: false),
            .navigate
        )
    }

    func testUnrecognisedDeclaredModeFallsBackToInference() {
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: "teleport", hasPOIs: true, hasNavGraph: true, hasObjects: false),
            .navigate
        )
    }

    func testInferenceRequiresBothPOIsAndAGraphToNavigate() {
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: nil, hasPOIs: true, hasNavGraph: false, hasObjects: false),
            .localize,
            "POIs without a graph cannot support navigation"
        )
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: nil, hasPOIs: false, hasNavGraph: true, hasObjects: false),
            .localize
        )
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: nil, hasPOIs: true, hasNavGraph: true, hasObjects: false),
            .navigate
        )
    }

    func testObjectCodesInferTrackMode() {
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: nil, hasPOIs: false, hasNavGraph: false, hasObjects: true),
            .track
        )
    }

    func testBareSpaceDefaultsToLocalize() {
        XCTAssertEqual(
            ExperienceManifestBuilder.resolveMode(declared: nil, hasPOIs: false, hasNavGraph: false, hasObjects: false),
            .localize
        )
    }

    // MARK: - Metadata parsing

    func testOnlyLocationPinsBecomePointsOfInterest() throws {
        let contents = [
            poi("poi_1", "Reception"),
            poi("poi_2", "Dispatch"),
            SpaceContent(id: "t1", title: "A notice", type: .text, position: Position(x: 0, y: 0, z: 0))
        ]
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(contentSpace: space(), contents: contents),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.pointsOfInterest.map(\.id), ["poi_1", "poi_2"])
    }

    func testDestinationResolvesFromMetadata() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(
                contentSpace: space(metadata: [
                    ExperienceManifestBuilder.MetadataKey.destination: ContentData(text: "poi_2")
                ]),
                contents: [poi("poi_1", "Reception"), poi("poi_2", "Dispatch")]
            ),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.destination?.title, "Dispatch")
    }

    func testDestinationFallsBackToTheFirstPOIWhenUnspecified() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(contentSpace: space(), contents: [poi("poi_1", "Reception")]),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.destination?.id, "poi_1")
    }

    func testObjectCodesAreSplitAndTrimmed() {
        XCTAssertEqual(
            ExperienceManifestBuilder.commaSeparated(" OBJ_A , OBJ_B ,, OBJ_C "),
            ["OBJ_A", "OBJ_B", "OBJ_C"]
        )
        XCTAssertEqual(ExperienceManifestBuilder.commaSeparated(nil), [])
        XCTAssertEqual(ExperienceManifestBuilder.commaSeparated(""), [])
    }

    func testValidNavGraphMetadataDecodes() throws {
        let graph = try XCTUnwrap(ExperienceManifestBuilder.decodeNavGraph(Fixtures.navGraphJSON))
        XCTAssertEqual(graph.nodes.count, 4)
        XCTAssertEqual(graph.edges.count, 3)
        XCTAssertEqual(graph.node(id: "n4")?.poiID, "poi_dispatch")
    }

    func testMalformedNavGraphDegradesRatherThanFailingTheInvocation() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(
                contentSpace: space(metadata: [
                    ExperienceManifestBuilder.MetadataKey.navGraph: ContentData(text: "{not json")
                ]),
                contents: [poi("poi_1", "Reception")]
            ),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertNil(manifest.navGraph)
        XCTAssertEqual(manifest.mode, .localize, "a broken graph must not promise navigation")
    }

    func testBrandingFallsBackToSpaceNameAndDescription() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(contentSpace: space(), contents: []),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.branding.title, "Northfield DC")
        XCTAssertEqual(manifest.branding.subtitle, "A description")
    }

    func testMetadataSubtitleOverridesTheDescription() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(
                contentSpace: space(metadata: [
                    ExperienceManifestBuilder.MetadataKey.subtitle: ContentData(text: "Follow the line")
                ]),
                contents: []
            ),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertEqual(manifest.branding.subtitle, "Follow the line")
    }

    func testExpectationNamesTheDestinationWhenNavigating() throws {
        let manifest = try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(
                contentSpace: space(metadata: [
                    ExperienceManifestBuilder.MetadataKey.mode: ContentData(text: "navigate"),
                    ExperienceManifestBuilder.MetadataKey.destination: ContentData(text: "poi_2")
                ]),
                contents: [poi("poi_1", "Reception"), poi("poi_2", "Dispatch office")]
            ),
            token: token,
            spaceCode: "k7m2p9xq"
        )
        XCTAssertTrue(manifest.expectation.contains("Dispatch office"))
        XCTAssertEqual(manifest.mode.primaryActionTitle, "Start navigating")
    }
}

final class MockAPITests: XCTestCase {
    func testUnpublishedSpaceCannotBeResolvedAsAnExperience() async {
        let api = MockMultiSetAPI(behaviour: .instant)
        do {
            _ = try await api.resolveExperience(spaceCode: "pumpskid1")
            XCTFail("a draft space must not resolve")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.deactivated))
        }
    }

    func testUnknownSpaceCodeIsRejected() async {
        let api = MockMultiSetAPI(behaviour: .instant)
        do {
            _ = try await api.resolveExperience(spaceCode: "no-such-code")
            XCTFail("expected unknownCode")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.unknownCode))
        }
    }

    func testPublishedNavigationSpaceResolvesWithGraphAndDestination() async throws {
        let api = MockMultiSetAPI(behaviour: .instant)
        let manifest = try await api.resolveExperience(spaceCode: "k7m2p9xq")
        XCTAssertEqual(manifest.mode, .navigate)
        XCTAssertEqual(manifest.target, .map(code: "MAP_7UVHMW2TJMOA"))
        XCTAssertNotNil(manifest.navGraph)
        XCTAssertEqual(manifest.destination?.title, "Dispatch office")
        XCTAssertEqual(manifest.pointsOfInterest.count, 3)
    }

    func testPublishingThenRevokingFlipsResolvability() async throws {
        let api = MockMultiSetAPI(behaviour: .instant)
        try await api.publishContentSpace(id: "pumpskid1")
        _ = try await api.resolveExperience(spaceCode: "pumpskid1")

        try await api.unpublishContentSpace(id: "pumpskid1")
        do {
            _ = try await api.resolveExperience(spaceCode: "pumpskid1")
            XCTFail("revoking must invalidate the experience")
        } catch {
            XCTAssertEqual(error as? MultiSetError, .experienceUnavailable(.deactivated))
        }
    }

    func testTransientFailuresAreExhaustedThenSucceed() async throws {
        let api = MockMultiSetAPI(behaviour: .init(latency: .zero, transientFailures: 2))
        for attempt in 1...2 {
            do {
                _ = try await api.maps(page: .first, search: nil, status: nil)
                XCTFail("attempt \(attempt) should have failed")
            } catch {
                XCTAssertEqual(error as? MultiSetError, .offline)
            }
        }
        let page = try await api.maps(page: .first, search: nil, status: nil)
        XCTAssertFalse(page.maps.isEmpty)
    }

    func testFixturesIncludeNonReadyMapsSoStatusUIIsExercised() async throws {
        let api = MockMultiSetAPI(behaviour: .instant)
        let statuses = Set(try await api.maps(page: .first, search: nil, status: nil).maps.map(\.status))
        XCTAssertTrue(statuses.contains(.active))
        XCTAssertTrue(statuses.contains(.processing))
        XCTAssertTrue(statuses.contains(.failed))
    }

    func testSearchFiltersOnNameAndCode() async throws {
        let api = MockMultiSetAPI(behaviour: .instant)
        let byName = try await api.maps(page: .first, search: "brewery", status: nil).maps
        let byCode = try await api.maps(page: .first, search: "MAP_7UVH", status: nil).maps
        let noMatch = try await api.maps(page: .first, search: "zzz", status: nil).maps
        XCTAssertEqual(byName.count, 1)
        XCTAssertEqual(byCode.count, 1)
        XCTAssertTrue(noMatch.isEmpty)
    }
}
