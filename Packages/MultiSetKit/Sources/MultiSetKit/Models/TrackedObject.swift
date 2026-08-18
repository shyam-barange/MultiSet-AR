import Foundation

public struct ObjectMesh: Codable, Sendable, Hashable {
    public var meshLink: String?
}

public struct TrackedObject: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var objectName: String
    public var objectCode: String
    public var accountId: String?
    public var status: ResourceStatus
    public var trackingType: String?
    public var storage: Double?
    public var source: SourceInfo?
    public var objectMesh: ObjectMesh?
    public var thumbnail: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case objectName, objectCode, accountId, status, trackingType
        case storage, source, objectMesh, thumbnail, createdAt, updatedAt
    }

    public init(
        id: String,
        objectName: String,
        objectCode: String,
        accountId: String? = nil,
        status: ResourceStatus = .active,
        trackingType: String? = nil,
        storage: Double? = nil,
        source: SourceInfo? = nil,
        objectMesh: ObjectMesh? = nil,
        thumbnail: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.objectName = objectName
        self.objectCode = objectCode
        self.accountId = accountId
        self.status = status
        self.trackingType = trackingType
        self.storage = storage
        self.source = source
        self.objectMesh = objectMesh
        self.thumbnail = thumbnail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TrackedObjectListPage: Codable, Sendable {
    public var totalCount: Int
    public var objects: [TrackedObject]

    public init(totalCount: Int, objects: [TrackedObject]) {
        self.totalCount = totalCount
        self.objects = objects
    }
}
