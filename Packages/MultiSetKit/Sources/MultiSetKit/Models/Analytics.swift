import Foundation

public struct AnalyticsSummary: Codable, Sendable, Equatable {
    public var totalQueries: Int?
    public var successfulQueries: Int?
    public var failedQueries: Int?
    public var mapsCount: Int?
    public var objectsCount: Int?
    public var storageUsed: Double?

    public init(
        totalQueries: Int? = nil,
        successfulQueries: Int? = nil,
        failedQueries: Int? = nil,
        mapsCount: Int? = nil,
        objectsCount: Int? = nil,
        storageUsed: Double? = nil
    ) {
        self.totalQueries = totalQueries
        self.successfulQueries = successfulQueries
        self.failedQueries = failedQueries
        self.mapsCount = mapsCount
        self.objectsCount = objectsCount
        self.storageUsed = storageUsed
    }

    public var successRate: Double? {
        guard let total = totalQueries, total > 0, let succeeded = successfulQueries else { return nil }
        return Double(succeeded) / Double(total)
    }
}

/// One localization attempt as recorded by the analytics endpoint.
public struct QueryRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var mapId: String?
    public var mapCode: String?
    public var objectId: String?
    public var poseFound: Bool?
    public var confidence: Double?
    public var position: Position?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case mapId, mapCode, objectId, poseFound, confidence, position, createdAt
    }

    public init(
        id: String,
        mapId: String? = nil,
        mapCode: String? = nil,
        objectId: String? = nil,
        poseFound: Bool? = nil,
        confidence: Double? = nil,
        position: Position? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.mapId = mapId
        self.mapCode = mapCode
        self.objectId = objectId
        self.poseFound = poseFound
        self.confidence = confidence
        self.position = position
        self.createdAt = createdAt
    }
}

public struct QueryRecordPage: Codable, Sendable {
    public var queries: [QueryRecord]?
    public var data: [QueryRecord]?
    public var totalCount: Int?

    /// The endpoint has shipped both `queries` and `data` as the array key.
    public var records: [QueryRecord] { queries ?? data ?? [] }

    public init(queries: [QueryRecord], totalCount: Int? = nil) {
        self.queries = queries
        self.totalCount = totalCount
    }
}

/// A localization density cell in the map's own coordinate frame.
public struct HeatmapCell: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(x),\(z)" }
    public var x: Double
    public var z: Double
    public var count: Int?
    public var successCount: Int?
    public var failureCount: Int?

    public init(x: Double, z: Double, count: Int? = nil, successCount: Int? = nil, failureCount: Int? = nil) {
        self.x = x
        self.z = z
        self.count = count
        self.successCount = successCount
        self.failureCount = failureCount
    }
}

public struct HeatmapResponse: Codable, Sendable {
    public var heatmap: [HeatmapCell]?
    public var data: [HeatmapCell]?
    public var cells: [HeatmapCell]?

    public var allCells: [HeatmapCell] { heatmap ?? data ?? cells ?? [] }

    public init(cells: [HeatmapCell]) {
        self.cells = cells
    }
}

public struct SimulationDataset: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var simulationCode: String?
    public var fileSize: Int?
    public var originalFilename: String?
    public var status: ResourceStatus?
    public var s3Key: String?
    public var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, simulationCode, fileSize, originalFilename, status, s3Key, createdAt
    }

    public init(
        id: String,
        name: String,
        simulationCode: String? = nil,
        fileSize: Int? = nil,
        originalFilename: String? = nil,
        status: ResourceStatus? = .active,
        s3Key: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.simulationCode = simulationCode
        self.fileSize = fileSize
        self.originalFilename = originalFilename
        self.status = status
        self.s3Key = s3Key
        self.createdAt = createdAt
    }
}

public struct SimulationDataPage: Codable, Sendable {
    public var simulationData: [SimulationDataset]

    public init(simulationData: [SimulationDataset]) {
        self.simulationData = simulationData
    }
}
