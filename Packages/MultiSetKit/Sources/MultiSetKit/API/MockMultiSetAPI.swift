import Foundation

/// Drives previews, unit tests, and the offline demo modes. Latency and failure
/// are injectable so error states can be designed rather than guessed at.
public actor MockMultiSetAPI: MultiSetAPI {
    public struct Behaviour: Sendable {
        public var latency: Duration
        /// When set, every call throws this instead of returning fixtures.
        public var failure: MultiSetError?
        /// Fails the first N calls, then succeeds. Exercises retry affordances.
        public var transientFailures: Int

        public init(
            latency: Duration = .milliseconds(220),
            failure: MultiSetError? = nil,
            transientFailures: Int = 0
        ) {
            self.latency = latency
            self.failure = failure
            self.transientFailures = transientFailures
        }

        public static let instant = Behaviour(latency: .zero)
        public static let offline = Behaviour(latency: .zero, failure: .offline)
        public static let unauthorized = Behaviour(latency: .zero, failure: .unauthorized)
    }

    private var behaviour: Behaviour
    private var remainingTransientFailures: Int
    private var spaces: [ContentSpace]
    private var contents: [String: [SpaceContent]]

    public private(set) var callCount = 0

    public init(behaviour: Behaviour = Behaviour()) {
        self.behaviour = behaviour
        self.remainingTransientFailures = behaviour.transientFailures
        self.spaces = Fixtures.contentSpaces
        self.contents = Fixtures.contentsBySpaceCode
    }

    public func set(behaviour: Behaviour) {
        self.behaviour = behaviour
        self.remainingTransientFailures = behaviour.transientFailures
    }

    private func gate() async throws {
        callCount += 1
        if behaviour.latency > .zero {
            try? await Task.sleep(for: behaviour.latency)
        }
        if remainingTransientFailures > 0 {
            remainingTransientFailures -= 1
            throw MultiSetError.offline
        }
        if let failure = behaviour.failure {
            throw failure
        }
    }

    // MARK: - Account

    public func userProfile() async throws -> UserProfile {
        try await gate()
        return Fixtures.profile
    }

    public func planDetails() async throws -> PlanDetails {
        try await gate()
        return Fixtures.plan
    }

    public func mintM2MCredentials(name: String, scopes: [M2MScope]) async throws -> M2MCredentials {
        try await gate()
        return M2MCredentials(clientId: "mock-client-id", clientSecret: "mock-client-secret")
    }

    public func m2mClients(page: Page) async throws -> [M2MClient] {
        try await gate()
        return []
    }

    // MARK: - Library

    public func maps(page: Page, search: String?, status: ResourceStatus?) async throws -> MapListPage {
        try await gate()
        var results = Fixtures.maps
        if let search, !search.isEmpty {
            results = results.filter {
                $0.mapName.localizedCaseInsensitiveContains(search)
                    || $0.mapCode.localizedCaseInsensitiveContains(search)
            }
        }
        if let status {
            results = results.filter { $0.status == status }
        }
        return MapListPage(totalCount: results.count, maps: results)
    }

    public func map(code: String) async throws -> VPSMap {
        try await gate()
        guard let map = Fixtures.maps.first(where: { $0.mapCode == code || $0.id == code }) else {
            throw MultiSetError.notFound(resource: "map")
        }
        return map
    }

    public func mapSets(page: Page, search: String?) async throws -> MapSetListPage {
        try await gate()
        return MapSetListPage(mapSets: Fixtures.mapSets, totalCount: Fixtures.mapSets.count)
    }

    public func mapSet(code: String) async throws -> MapSet {
        try await gate()
        guard let mapSet = Fixtures.mapSets.first(where: { $0.mapSetCode == code || $0.id == code }) else {
            throw MultiSetError.notFound(resource: "map set")
        }
        return mapSet
    }

    public func trackedObjects(page: Page, search: String?) async throws -> TrackedObjectListPage {
        try await gate()
        var results = Fixtures.objects
        if let search, !search.isEmpty {
            results = results.filter {
                $0.objectName.localizedCaseInsensitiveContains(search)
                    || $0.objectCode.localizedCaseInsensitiveContains(search)
            }
        }
        return TrackedObjectListPage(totalCount: results.count, objects: results)
    }

    public func trackedObject(code: String) async throws -> TrackedObject {
        try await gate()
        guard let object = Fixtures.objects.first(where: { $0.objectCode == code || $0.id == code }) else {
            throw MultiSetError.notFound(resource: "object")
        }
        return object
    }

    public func fileURL(key: String) async throws -> URL {
        try await gate()
        return URL(string: "https://example.invalid/\(key)")!
    }

    // MARK: - Localization

    public func localizeSingleFrame(
        _ query: LocalizationQuery,
        frame: QueryFrame
    ) async throws -> LocalizationResult {
        try await gate()
        return Fixtures.localizationResult(mode: .singleFrame, mapCode: query.target.code)
    }

    public func localizeMultiFrame(
        _ query: LocalizationQuery,
        frames: [QueryFrame]
    ) async throws -> LocalizationResult {
        try await gate()
        return Fixtures.localizationResult(mode: .multiFrame, mapCode: query.target.code)
    }

    public func queryObject(_ query: ObjectQuery, frame: QueryFrame) async throws -> ObjectTrackingResult {
        try await gate()
        return ObjectTrackingResult(
            pose: Pose(
                position: Position(x: 0.12, y: -0.34, z: -0.86),
                rotation: Rotation(x: 0, y: 0.707, z: 0, w: 0.707)
            ),
            confidence: 0.93,
            objectCodes: query.objectCodes,
            latency: .milliseconds(280)
        )
    }

    // MARK: - Experiences

    public func contentSpaces(page: Page, search: String?) async throws -> ContentSpaceListPage {
        try await gate()
        var results = spaces
        if let search, !search.isEmpty {
            results = results.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return ContentSpaceListPage(spaces: results, totalCount: results.count)
    }

    public func contentSpace(id: String, page: Page) async throws -> ContentSpaceDetail {
        try await gate()
        guard let space = spaces.first(where: { $0.spaceCode == id || $0.id == id }) else {
            throw MultiSetError.experienceUnavailable(.unknownCode)
        }
        return ContentSpaceDetail(
            contentSpace: space,
            contents: contents[space.spaceCode] ?? [],
            totalCount: contents[space.spaceCode]?.count ?? 0
        )
    }

    public func createContentSpace(_ draft: ContentSpaceDraft) async throws -> ContentSpace {
        try await gate()
        let code = String(UUID().uuidString.prefix(8)).lowercased()
        let space = ContentSpace(
            id: UUID().uuidString,
            name: draft.name,
            spaceCode: code,
            description: draft.description,
            mapId: { if case .map(let c) = draft.target { return c } else { return nil } }(),
            mapSetId: { if case .mapSet(let c) = draft.target { return c } else { return nil } }(),
            status: "draft",
            isPublic: false,
            createdAt: Date()
        )
        spaces.insert(space, at: 0)
        contents[code] = []
        return space
    }

    public func publishContentSpace(id: String) async throws {
        try await gate()
        mutateSpace(id) { $0.status = "published" }
    }

    public func unpublishContentSpace(id: String) async throws {
        try await gate()
        mutateSpace(id) { $0.status = "draft" }
    }

    public func setContentSpacePublic(id: String, isPublic: Bool) async throws {
        try await gate()
        mutateSpace(id) { $0.isPublic = isPublic }
    }

    public func deleteContentSpace(id: String) async throws {
        try await gate()
        spaces.removeAll { $0.id == id || $0.spaceCode == id }
    }

    public func addContent(_ draft: ContentDraft) async throws -> SpaceContent {
        try await gate()
        let content = SpaceContent(
            id: UUID().uuidString,
            contentSpaceId: draft.contentSpaceId,
            title: draft.title,
            type: draft.type,
            position: draft.position,
            rotation: draft.rotation,
            scale: draft.scale,
            createdAt: Date()
        )
        if let space = spaces.first(where: { $0.id == draft.contentSpaceId || $0.spaceCode == draft.contentSpaceId }) {
            contents[space.spaceCode, default: []].append(content)
        }
        return content
    }

    public func updateContent(id: String, _ draft: ContentUpdate) async throws {
        try await gate()
        for (code, items) in contents {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            var item = items[index]
            if let title = draft.title { item.title = title }
            if let position = draft.position { item.position = position }
            if let rotation = draft.rotation { item.rotation = rotation }
            if let scale = draft.scale { item.scale = scale }
            contents[code]?[index] = item
        }
    }

    public func deleteContent(id: String) async throws {
        try await gate()
        for code in contents.keys {
            contents[code]?.removeAll { $0.id == id }
        }
    }

    public func resolveExperience(spaceCode: String) async throws -> ExperienceManifest {
        try await gate()
        guard let space = spaces.first(where: { $0.spaceCode == spaceCode }) else {
            throw MultiSetError.experienceUnavailable(.unknownCode)
        }
        guard space.isPublished else {
            throw MultiSetError.experienceUnavailable(.deactivated)
        }
        return try ExperienceManifestBuilder.build(
            from: ContentSpaceDetail(contentSpace: space, contents: contents[spaceCode] ?? []),
            token: AuthToken(token: "mock-experience-token", expiresOn: Date().addingTimeInterval(900)),
            spaceCode: spaceCode
        )
    }

    // MARK: - Analytics

    public func accountAnalytics(range: DateRange) async throws -> AnalyticsSummary {
        try await gate()
        return Fixtures.analytics
    }

    public func queryAnalytics(
        mapId: String?,
        objectId: String?,
        range: DateRange,
        page: Page
    ) async throws -> [QueryRecord] {
        try await gate()
        return Fixtures.queryRecords
    }

    public func heatmap(mapId: String, range: DateRange) async throws -> [HeatmapCell] {
        try await gate()
        return Fixtures.heatmapCells
    }

    public func simulationDatasets(page: Page) async throws -> [SimulationDataset] {
        try await gate()
        return Fixtures.simulationDatasets
    }

    private func mutateSpace(_ id: String, _ change: (inout ContentSpace) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.id == id || $0.spaceCode == id }) else { return }
        change(&spaces[index])
    }
}
