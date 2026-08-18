import Foundation

/// Sample data shaped exactly like real API responses, so previews and tests
/// exercise the same decoding paths and edge cases the live app will hit —
/// including a processing map, a failed map, and a map with no georeference.
public enum Fixtures {
    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date(timeIntervalSince1970: 1_700_000_000)
    }

    public static let profile = UserProfile(
        id: "usr_8f21c4",
        fullName: "Alex Rivera",
        email: "alex@example.com",
        companyName: "Northfield Logistics",
        region: "us-west",
        accountId: "acc_3d91f0"
    )

    public static let plan = PlanDetails(apiCalls: 10_000, storage: 5_120, mapsCount: 50, watermark: false)

    public static let maps: [VPSMap] = [
        VPSMap(
            id: "64a1f0c2e91b4a0012ab34cd",
            mapCode: "MAP_7UVHMW2TJMOA",
            mapName: "Northfield DC — Aisle 1–12",
            accountId: "acc_3d91f0",
            status: .active,
            storage: 185.5,
            location: GeoJSONPoint(type: "Point", coordinates: [-122.4194, 37.7749]),
            coordinates: GeoCoordinates(latitude: 37.7749, longitude: -122.4194, altitude: 12),
            mapMesh: MapMesh(
                id: "mesh_1",
                rawMesh: MeshReference(type: "glb", meshLink: "maps/raw/northfield.glb"),
                texturedMesh: MeshReference(type: "glb", meshLink: "maps/textured/northfield.glb")
            ),
            cameraIntrinsics: MapCameraIntrinsics(
                cameraIntrinsics: CameraIntrinsics(fx: 667.795, fy: 667.795, px: 361.050, py: 481.819),
                resolution: Resolution(width: 720, height: 960)
            ),
            resolution: Resolution(width: 720, height: 960),
            thumbnail: "thumbnails/northfield.jpg",
            heading: 45,
            offlineBundle: "bundles/MAP_7UVHMW2TJMOA.bytes",
            offlineBundleStatus: "active",
            source: SourceInfo(provider: "multiset", fileType: "e57", coordinateSystem: "right-handed"),
            createdAt: date("2026-01-15T10:00:00Z"),
            updatedAt: date("2026-08-02T15:30:00Z")
        ),
        VPSMap(
            id: "64a1f0c2e91b4a0012ab34ce",
            mapCode: "MAP_QK83LZ0P4RTN",
            mapName: "Toit Brewery — Production Floor",
            accountId: "acc_3d91f0",
            status: .active,
            storage: 96.2,
            coordinates: GeoCoordinates(latitude: 12.9784, longitude: 77.6408, altitude: 0),
            mapMesh: MapMesh(
                id: "mesh_2",
                rawMesh: MeshReference(type: "glb", meshLink: "maps/raw/toit.glb"),
                texturedMesh: nil
            ),
            thumbnail: "thumbnails/toit.jpg",
            source: SourceInfo(provider: "multiset", fileType: "glb", coordinateSystem: "right-handed"),
            createdAt: date("2026-03-04T09:12:00Z"),
            updatedAt: date("2026-07-19T11:02:00Z")
        ),
        VPSMap(
            id: "64a1f0c2e91b4a0012ab34cf",
            mapCode: "MAP_3HNPX7WQ9CDE",
            mapName: "Terminal B — Concourse",
            status: .processing,
            storage: 402.8,
            source: SourceInfo(provider: "multiset", fileType: "las", coordinateSystem: "right-handed"),
            createdAt: date("2026-08-17T08:45:00Z"),
            updatedAt: date("2026-08-17T08:45:00Z")
        ),
        VPSMap(
            id: "64a1f0c2e91b4a0012ab34d0",
            mapCode: "MAP_ZR21KM6VB8YJ",
            mapName: "Plant Room 4 — Boiler Deck",
            status: .failed,
            storage: 12.1,
            source: SourceInfo(provider: "multiset", fileType: "ply", coordinateSystem: "right-handed"),
            createdAt: date("2026-08-11T14:20:00Z"),
            updatedAt: date("2026-08-11T14:52:00Z")
        )
    ]

    public static let mapSets: [MapSet] = [
        MapSet(
            id: "64b2a1d3f02c5b0013cd45ef",
            name: "Northfield DC — All Floors",
            mapSetCode: "MSET_4TQ9WX2LMNPV",
            accountId: "acc_3d91f0",
            status: .active,
            totalMaps: 3,
            mapSetData: [
                MapSetEntry(
                    id: "data_1",
                    order: 0,
                    relativePose: RelativePose(
                        position: Position(x: 0, y: 0, z: 0),
                        rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
                    ),
                    map: maps[0]
                ),
                MapSetEntry(
                    id: "data_2",
                    order: 1,
                    relativePose: RelativePose(
                        position: Position(x: 0, y: 4.2, z: 0),
                        rotation: Rotation(x: 0, y: 0, z: 0, w: 1)
                    ),
                    map: maps[1]
                )
            ],
            createdAt: date("2026-02-10T08:00:00Z"),
            updatedAt: date("2026-08-01T12:00:00Z")
        )
    ]

    public static let objects: [TrackedObject] = [
        TrackedObject(
            id: "64c3b2e4a13d6c0014de56f0",
            objectName: "Grundfos CR 15 Pump Skid",
            objectCode: "OBJ_8KMQ2WT7XPRA",
            accountId: "acc_3d91f0",
            status: .active,
            trackingType: "3d",
            storage: 1_024,
            source: SourceInfo(provider: "multiset", fileType: "glb", coordinateSystem: "right-handed"),
            objectMesh: ObjectMesh(meshLink: "objects/mesh/OBJ_8KMQ2WT7XPRA.glb"),
            thumbnail: "thumbnails/pump.jpg",
            createdAt: date("2026-02-01T10:00:00Z"),
            updatedAt: date("2026-06-15T14:00:00Z")
        ),
        TrackedObject(
            id: "64c3b2e4a13d6c0014de56f1",
            objectName: "ABB Control Cabinet",
            objectCode: "OBJ_5NZD9YV3QLHB",
            status: .active,
            trackingType: "3d",
            storage: 780,
            objectMesh: ObjectMesh(meshLink: "objects/mesh/OBJ_5NZD9YV3QLHB.glb"),
            createdAt: date("2026-04-22T10:00:00Z"),
            updatedAt: date("2026-06-30T09:00:00Z")
        ),
        TrackedObject(
            id: "64c3b2e4a13d6c0014de56f2",
            objectName: "Demo Target Sheet",
            objectCode: "OBJ_DEMO0TARGET1",
            status: .active,
            trackingType: "2d",
            storage: 24,
            createdAt: date("2026-08-01T10:00:00Z"),
            updatedAt: date("2026-08-01T10:00:00Z")
        )
    ]

    public static let contentSpaces: [ContentSpace] = [
        ContentSpace(
            id: "space_1",
            name: "Northfield DC — Wayfinding",
            spaceCode: "k7m2p9xq",
            description: "Guides visitors from reception to the dispatch office.",
            accountId: "acc_3d91f0",
            mapId: "MAP_7UVHMW2TJMOA",
            status: "published",
            isPublic: true,
            metadata: [
                ExperienceManifestBuilder.MetadataKey.mode: ContentData(text: "navigate"),
                ExperienceManifestBuilder.MetadataKey.destination: ContentData(text: "poi_dispatch"),
                ExperienceManifestBuilder.MetadataKey.subtitle: ContentData(text: "Follow the line to Dispatch"),
                ExperienceManifestBuilder.MetadataKey.navGraph: ContentData(text: navGraphJSON)
            ],
            createdAt: date("2026-06-01T10:00:00Z"),
            updatedAt: date("2026-08-14T10:00:00Z")
        ),
        ContentSpace(
            id: "space_2",
            name: "Toit Brewery — Tank Tour",
            spaceCode: "toit-brewery",
            description: "A self-guided tour of the fermentation hall.",
            accountId: "acc_3d91f0",
            mapId: "MAP_QK83LZ0P4RTN",
            status: "published",
            isPublic: true,
            metadata: [
                ExperienceManifestBuilder.MetadataKey.mode: ContentData(text: "localize")
            ],
            createdAt: date("2026-07-08T10:00:00Z"),
            updatedAt: date("2026-08-10T10:00:00Z")
        ),
        ContentSpace(
            id: "space_3",
            name: "Pump Skid Inspection",
            spaceCode: "pumpskid1",
            description: "Traces the pump skid for a commissioning check.",
            accountId: "acc_3d91f0",
            mapId: "MAP_QK83LZ0P4RTN",
            status: "draft",
            isPublic: false,
            metadata: [
                ExperienceManifestBuilder.MetadataKey.mode: ContentData(text: "track"),
                ExperienceManifestBuilder.MetadataKey.objectCodes: ContentData(text: "OBJ_8KMQ2WT7XPRA")
            ],
            createdAt: date("2026-08-12T10:00:00Z"),
            updatedAt: date("2026-08-12T10:00:00Z")
        )
    ]

    static let navGraphJSON = """
    {"nodes":[\
    {"id":"n1","position":{"x":0,"y":0,"z":0}},\
    {"id":"n2","position":{"x":4.5,"y":0,"z":0}},\
    {"id":"n3","position":{"x":4.5,"y":0,"z":-7.2}},\
    {"id":"n4","position":{"x":11.8,"y":0,"z":-7.2},"poiID":"poi_dispatch"}\
    ],"edges":[\
    {"from":"n1","to":"n2"},{"from":"n2","to":"n3"},{"from":"n3","to":"n4"}\
    ]}
    """

    public static let contentsBySpaceCode: [String: [SpaceContent]] = [
        "k7m2p9xq": [
            SpaceContent(
                id: "poi_reception",
                contentSpaceId: "space_1",
                title: "Reception",
                type: .locationPin,
                position: Position(x: 0, y: 0, z: 0)
            ),
            SpaceContent(
                id: "poi_dispatch",
                contentSpaceId: "space_1",
                title: "Dispatch office",
                type: .locationPin,
                position: Position(x: 11.8, y: 0, z: -7.2)
            ),
            SpaceContent(
                id: "poi_safety",
                contentSpaceId: "space_1",
                title: "Safety station",
                type: .locationPin,
                position: Position(x: 4.5, y: 0, z: -3.1)
            ),
            SpaceContent(
                id: "text_welcome",
                contentSpaceId: "space_1",
                title: "Hard hats required beyond this point",
                type: .text,
                position: Position(x: 1.2, y: 1.6, z: -0.4)
            )
        ],
        "toit-brewery": [
            SpaceContent(
                id: "poi_tank_1",
                contentSpaceId: "space_2",
                title: "Fermenter 1",
                type: .locationPin,
                position: Position(x: 2.1, y: 0, z: -3.4)
            )
        ],
        "pumpskid1": []
    ]

    public static func localizationResult(mode: LocalizationMode, mapCode: String) -> LocalizationResult {
        LocalizationResult(
            pose: Pose(
                position: Position(x: 1.234, y: 0.456, z: -2.671),
                rotation: Rotation(x: 0.011, y: 0.994, z: 0.021, w: -0.052)
            ),
            trackingPose: mode == .multiFrame
                ? Pose(
                    position: Position(x: 0.10, y: 1.13, z: -0.02),
                    rotation: Rotation(x: -0.01, y: 0.10, z: 0, w: -0.99)
                )
                : nil,
            confidence: 0.87,
            mapCodes: [mapCode],
            mapIds: ["64a1f0c2e91b4a0012ab34cd"],
            mode: mode,
            latency: .milliseconds(mode == .multiFrame ? 640 : 310)
        )
    }

    public static let analytics = AnalyticsSummary(
        totalQueries: 4_812,
        successfulQueries: 4_401,
        failedQueries: 411,
        mapsCount: 4,
        objectsCount: 3,
        storageUsed: 696.6
    )

    public static let queryRecords: [QueryRecord] = (0..<40).map(Self.queryRecord(index:))

    private static func queryRecord(index: Int) -> QueryRecord {
        let succeeded: Bool = index % 9 != 0
        let angle: Double = Double(index) * 0.4
        let radius: Double = 3 + Double(index % 6)
        let confidence: Double = succeeded ? 0.6 + Double(index % 4) * 0.09 : 0.12
        let timestamp: Double = 1_755_000_000 + Double(index) * 3_600
        return QueryRecord(
            id: "q_\(index)",
            mapId: "64a1f0c2e91b4a0012ab34cd",
            mapCode: "MAP_7UVHMW2TJMOA",
            poseFound: succeeded,
            confidence: confidence,
            position: Position(x: cos(angle) * radius, y: 0, z: sin(angle) * radius),
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    public static let heatmapCells: [HeatmapCell] = (0..<180).map(Self.heatmapCell(index:))

    private static func heatmapCell(index: Int) -> HeatmapCell {
        let angle: Double = Double(index) * 0.32
        let radius: Double = 2 + Double(index % 19) * 0.6
        let total: Int = 1 + index % 12
        let failures: Int = index % 11 == 0 ? total : 0
        return HeatmapCell(
            x: cos(angle) * radius,
            z: sin(angle) * radius * 0.62,
            count: total,
            successCount: total - failures,
            failureCount: failures
        )
    }

    public static let simulationDatasets: [SimulationDataset] = [
        SimulationDataset(
            id: "sim_1",
            name: "Northfield DC — Aisle 3 walkthrough",
            simulationCode: "SIM_9QZ2LT4KMBRW",
            fileSize: 5_242_880,
            originalFilename: "SimulationData.zip",
            status: .active,
            s3Key: "simulation-data/SIM_9QZ2LT4KMBRW.zip",
            createdAt: date("2026-03-17T15:57:36Z")
        )
    ]
}
