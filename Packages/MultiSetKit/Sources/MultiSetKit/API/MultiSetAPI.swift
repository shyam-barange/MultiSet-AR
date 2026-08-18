import Foundation

public struct DateRange: Sendable, Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public static func lastDays(_ days: Int, now: Date = Date()) -> DateRange {
        DateRange(start: now.addingTimeInterval(-Double(days) * 86_400), end: now)
    }
}

public struct Page: Sendable, Equatable {
    public var index: Int
    public var limit: Int

    public init(index: Int = 1, limit: Int = 50) {
        self.index = index
        self.limit = limit
    }

    public static let first = Page()
}

/// The whole API surface this app needs, in one protocol so previews, tests, and
/// the Clip can all be driven by a mock.
public protocol MultiSetAPI: Sendable {
    // Account
    func userProfile() async throws -> UserProfile
    func planDetails() async throws -> PlanDetails
    func mintM2MCredentials(name: String) async throws -> M2MCredentials
    func m2mClients(page: Page) async throws -> [M2MClient]

    // Library
    func maps(page: Page, search: String?, status: ResourceStatus?) async throws -> MapListPage
    func map(code: String) async throws -> VPSMap
    func mapSets(page: Page, search: String?) async throws -> MapSetListPage
    func mapSet(code: String) async throws -> MapSet
    func trackedObjects(page: Page, search: String?) async throws -> TrackedObjectListPage
    func trackedObject(code: String) async throws -> TrackedObject
    func fileURL(key: String) async throws -> URL

    // Localization
    func localizeSingleFrame(_ query: LocalizationQuery, frame: QueryFrame) async throws -> LocalizationResult
    func localizeMultiFrame(_ query: LocalizationQuery, frames: [QueryFrame]) async throws -> LocalizationResult
    func queryObject(_ query: ObjectQuery, frame: QueryFrame) async throws -> ObjectTrackingResult

    // Experiences
    func contentSpaces(page: Page, search: String?) async throws -> ContentSpaceListPage
    func contentSpace(id: String, page: Page) async throws -> ContentSpaceDetail
    func createContentSpace(_ draft: ContentSpaceDraft) async throws -> ContentSpace
    func publishContentSpace(id: String) async throws
    func unpublishContentSpace(id: String) async throws
    func setContentSpacePublic(id: String, isPublic: Bool) async throws
    func deleteContentSpace(id: String) async throws
    func addContent(_ draft: ContentDraft) async throws -> SpaceContent
    func updateContent(id: String, _ draft: ContentUpdate) async throws
    func deleteContent(id: String) async throws

    /// Resolves a public experience without any credential. The App Clip's only
    /// entry point.
    func resolveExperience(spaceCode: String) async throws -> ExperienceManifest

    // Analytics
    func accountAnalytics(range: DateRange) async throws -> AnalyticsSummary
    func queryAnalytics(mapId: String?, objectId: String?, range: DateRange, page: Page) async throws -> [QueryRecord]
    func heatmap(mapId: String, range: DateRange) async throws -> [HeatmapCell]

    // Simulation
    func simulationDatasets(page: Page) async throws -> [SimulationDataset]
}

public struct ContentSpaceDraft: Sendable, Equatable {
    public var name: String
    public var description: String?
    public var target: MapTarget
    public var thumbnailKey: String?

    public init(name: String, description: String? = nil, target: MapTarget, thumbnailKey: String? = nil) {
        self.name = name
        self.description = description
        self.target = target
        self.thumbnailKey = thumbnailKey
    }
}

public struct ContentDraft: Sendable, Equatable {
    public var contentSpaceId: String
    public var title: String
    public var type: ContentKind
    public var position: Position
    public var rotation: Rotation
    public var scale: Scale
    public var assetId: String?

    public init(
        contentSpaceId: String,
        title: String,
        type: ContentKind,
        position: Position,
        rotation: Rotation = Rotation(x: 0, y: 0, z: 0, w: 1),
        scale: Scale = Scale(),
        assetId: String? = nil
    ) {
        self.contentSpaceId = contentSpaceId
        self.title = title
        self.type = type
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.assetId = assetId
    }
}

public struct ContentUpdate: Sendable, Equatable {
    public var title: String?
    public var position: Position?
    public var rotation: Rotation?
    public var scale: Scale?

    public init(
        title: String? = nil,
        position: Position? = nil,
        rotation: Rotation? = nil,
        scale: Scale? = nil
    ) {
        self.title = title
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
}
