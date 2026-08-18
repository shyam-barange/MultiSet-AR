import Foundation

public enum ContentKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case locationPin = "location_pin"

    public var displayName: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .locationPin: "Point of interest"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: "textformat"
        case .image: "photo"
        case .locationPin: "mappin.and.ellipse"
        }
    }
}

public struct ContentData: Codable, Sendable, Hashable {
    public var assetId: String?
    public var assetKey: String?
    public var assetUrl: String?
    public var text: String?

    public init(assetId: String? = nil, assetKey: String? = nil, assetUrl: String? = nil, text: String? = nil) {
        self.assetId = assetId
        self.assetKey = assetKey
        self.assetUrl = assetUrl
        self.text = text
    }
}

/// An item placed in a Content Space. `location_pin` items are the platform's
/// POI store — there is no separate POI API.
public struct SpaceContent: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var contentSpaceId: String?
    public var title: String
    public var type: ContentKind
    public var position: Position
    public var rotation: Rotation?
    public var scale: Scale?
    public var contentData: ContentData?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case contentSpaceId, title, type, position, rotation, scale
        case contentData = "content_data"
        case createdAt, updatedAt
    }

    public init(
        id: String,
        contentSpaceId: String? = nil,
        title: String,
        type: ContentKind,
        position: Position,
        rotation: Rotation? = nil,
        scale: Scale? = nil,
        contentData: ContentData? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.contentSpaceId = contentSpaceId
        self.title = title
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.contentData = contentData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isPointOfInterest: Bool { type == .locationPin }
}

public struct ContentSpace: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var spaceCode: String
    public var description: String?
    public var accountId: String?
    public var mapId: String?
    public var mapSetId: String?
    public var thumbnail: String?
    public var status: String?
    public var isPublic: Bool?
    public var metadata: [String: ContentData]?
    public var createdAt: Date?
    public var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, spaceCode, description, accountId, mapId, mapSetId
        case thumbnail, status, isPublic, metadata, createdAt, updatedAt
    }

    public init(
        id: String,
        name: String,
        spaceCode: String,
        description: String? = nil,
        accountId: String? = nil,
        mapId: String? = nil,
        mapSetId: String? = nil,
        thumbnail: String? = nil,
        status: String? = nil,
        isPublic: Bool? = nil,
        metadata: [String: ContentData]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.spaceCode = spaceCode
        self.description = description
        self.accountId = accountId
        self.mapId = mapId
        self.mapSetId = mapSetId
        self.thumbnail = thumbnail
        self.status = status
        self.isPublic = isPublic
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isPublished: Bool { status?.lowercased() == "published" }

    /// The URL printed on a QR code. Also the App Clip invocation URL.
    public var shareURL: URL? {
        URL(string: "https://app.multiset.ai/space/\(spaceCode)")
    }
}

public struct ContentSpaceListPage: Codable, Sendable {
    public var spaces: [ContentSpace]
    public var totalCount: Int?
    public var totalPages: Int?
    public var currentPage: Int?

    public init(spaces: [ContentSpace], totalCount: Int? = nil) {
        self.spaces = spaces
        self.totalCount = totalCount
    }
}

public struct ContentSpaceDetail: Codable, Sendable {
    public var contentSpace: ContentSpace
    public var contents: [SpaceContent]
    public var totalCount: Int?
    public var totalPages: Int?
    public var currentPage: Int?

    public init(contentSpace: ContentSpace, contents: [SpaceContent], totalCount: Int? = nil) {
        self.contentSpace = contentSpace
        self.contents = contents
        self.totalCount = totalCount
    }

    public var pointsOfInterest: [SpaceContent] {
        contents.filter(\.isPointOfInterest)
    }
}

public struct FileURL: Codable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }

    public var resolved: URL? { URL(string: url) }
}
