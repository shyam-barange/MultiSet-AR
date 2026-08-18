import Foundation

public enum ResourceStatus: String, Codable, Sendable, CaseIterable {
    case active
    case processing
    case failed
    case archived
    case pending
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ResourceStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var isReady: Bool { self == .active }

    public var displayName: String {
        switch self {
        case .active: "Ready"
        case .processing: "Processing"
        case .failed: "Failed"
        case .archived: "Archived"
        case .pending: "Pending"
        case .unknown: "Unknown"
        }
    }
}

public struct MeshReference: Codable, Sendable, Hashable {
    public var type: String?
    public var meshLink: String?
}

public struct MapMesh: Codable, Sendable, Hashable {
    public var id: String?
    public var rawMesh: MeshReference?
    public var texturedMesh: MeshReference?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rawMesh, texturedMesh
    }
}

public struct SourceInfo: Codable, Sendable, Hashable {
    public var provider: String?
    public var fileType: String?
    public var coordinateSystem: String?

    /// How the map was captured, inferred from `fileType`, for the Overview section.
    public var captureKind: String {
        switch (fileType ?? "").lowercased() {
        case "e57": "E57 point cloud"
        case "ply", "splat", "ksplat": "Gaussian splat"
        case "glb", "gltf": "Textured mesh"
        case "mp4", "insv", "360": "360° capture"
        case "las", "laz": "LiDAR point cloud"
        default: fileType?.uppercased() ?? "Scan"
        }
    }
}

/// Wrapper for the doubly-nested `cameraIntrinsics.camera_intrinsics` shape the
/// map detail endpoint returns.
public struct MapCameraIntrinsics: Codable, Sendable, Hashable {
    public var cameraIntrinsics: CameraIntrinsics?
    public var resolution: Resolution?

    private enum CodingKeys: String, CodingKey {
        case cameraIntrinsics = "camera_intrinsics"
        case resolution
    }
}

public struct VPSMap: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var mapCode: String
    public var mapName: String
    public var accountId: String?
    public var status: ResourceStatus
    public var storage: Double?
    public var location: GeoJSONPoint?
    public var coordinates: GeoCoordinates?
    public var mapMesh: MapMesh?
    public var cameraIntrinsics: MapCameraIntrinsics?
    public var resolution: Resolution?
    public var thumbnail: String?
    public var globalFeature: String?
    public var heading: Double?
    public var offlineBundle: String?
    public var offlineBundleStatus: String?
    public var source: SourceInfo?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case mapCode, mapName, accountId, status, storage, location, coordinates
        case mapMesh, cameraIntrinsics, resolution, thumbnail, globalFeature
        case heading, offlineBundle, offlineBundleStatus, source, createdAt, updatedAt
    }

    public init(
        id: String,
        mapCode: String,
        mapName: String,
        accountId: String? = nil,
        status: ResourceStatus = .active,
        storage: Double? = nil,
        location: GeoJSONPoint? = nil,
        coordinates: GeoCoordinates? = nil,
        mapMesh: MapMesh? = nil,
        cameraIntrinsics: MapCameraIntrinsics? = nil,
        resolution: Resolution? = nil,
        thumbnail: String? = nil,
        globalFeature: String? = nil,
        heading: Double? = nil,
        offlineBundle: String? = nil,
        offlineBundleStatus: String? = nil,
        source: SourceInfo? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.mapCode = mapCode
        self.mapName = mapName
        self.accountId = accountId
        self.status = status
        self.storage = storage
        self.location = location
        self.coordinates = coordinates
        self.mapMesh = mapMesh
        self.cameraIntrinsics = cameraIntrinsics
        self.resolution = resolution
        self.thumbnail = thumbnail
        self.globalFeature = globalFeature
        self.heading = heading
        self.offlineBundle = offlineBundle
        self.offlineBundleStatus = offlineBundleStatus
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True when the map carries real-world georeferencing, which unlocks the
    /// MapKit snapshot and GPS-hinted localization.
    public var isGeoreferenced: Bool {
        (coordinates?.isValid ?? false) || (location?.geoCoordinates?.isValid ?? false)
    }

    public var geoPosition: GeoCoordinates? {
        if let coordinates, coordinates.isValid { return coordinates }
        return location?.geoCoordinates
    }

    public var hasOfflineBundle: Bool {
        offlineBundle?.isEmpty == false && offlineBundleStatus?.lowercased() == "active"
    }

    public var storageDisplay: String? {
        guard let storage else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(storage * 1_048_576), countStyle: .file)
    }
}

public struct MapListPage: Codable, Sendable {
    public var totalCount: Int
    public var maps: [VPSMap]

    public init(totalCount: Int, maps: [VPSMap]) {
        self.totalCount = totalCount
        self.maps = maps
    }
}
