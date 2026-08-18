import Foundation

public struct RelativePose: Codable, Sendable, Hashable {
    public var position: Position
    public var rotation: Rotation

    public init(position: Position, rotation: Rotation) {
        self.position = position
        self.rotation = rotation
    }
}

public struct MapSetEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var order: Int?
    public var relativePose: RelativePose?
    public var map: VPSMap?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case order, relativePose, map, createdAt, updatedAt
    }
}

public struct MapSet: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var mapSetCode: String?
    public var accountId: String?
    public var status: ResourceStatus?
    public var totalMaps: Int?
    public var mapSetData: [MapSetEntry]?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, mapSetCode, accountId, status, totalMaps, mapSetData, createdAt, updatedAt
    }

    public init(
        id: String,
        name: String,
        mapSetCode: String? = nil,
        accountId: String? = nil,
        status: ResourceStatus? = .active,
        totalMaps: Int? = nil,
        mapSetData: [MapSetEntry]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.mapSetCode = mapSetCode
        self.accountId = accountId
        self.status = status
        self.totalMaps = totalMaps
        self.mapSetData = mapSetData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var mapCount: Int {
        totalMaps ?? mapSetData?.count ?? 0
    }
}

public struct MapSetListPage: Codable, Sendable {
    public var mapSets: [MapSet]
    public var totalCount: Int?
    public var totalPages: Int?
    public var currentPage: Int?
    public var pageSize: Int?

    public init(mapSets: [MapSet], totalCount: Int? = nil) {
        self.mapSets = mapSets
        self.totalCount = totalCount
    }
}

public struct MapSetEnvelope: Codable, Sendable {
    public var mapSet: MapSet
}
