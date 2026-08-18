import Foundation

public actor LiveMultiSetAPI: MultiSetAPI {
    private let client: HTTPClient
    private let auth: AuthStore
    private let clock: @Sendable () -> ContinuousClock.Instant

    public init(
        environment: APIEnvironment = .production,
        auth: AuthStore,
        transport: any HTTPTransport = URLSession.shared
    ) {
        self.client = HTTPClient(baseURL: environment.baseURL, transport: transport)
        self.auth = auth
        self.clock = { ContinuousClock.now }
    }

    // MARK: - Request plumbing

    /// Sends with a valid token, and retries exactly once on a 401 in case the
    /// token was revoked server-side before its stated expiry.
    private func authorized<Response: Decodable>(
        _ endpoint: Endpoint,
        as type: Response.Type,
        context: String
    ) async throws -> Response {
        let token = endpoint.requiresAuthentication ? try await auth.validToken() : nil
        do {
            return try await client.send(endpoint, as: type, bearerToken: token, context: context)
        } catch MultiSetError.unauthorized where endpoint.requiresAuthentication {
            await auth.invalidateToken()
            let retryToken = try await auth.validToken()
            return try await client.send(endpoint, as: type, bearerToken: retryToken, context: context)
        }
    }

    private func authorizedVoid(_ endpoint: Endpoint, context: String) async throws {
        let token = endpoint.requiresAuthentication ? try await auth.validToken() : nil
        do {
            try await client.sendForData(endpoint, bearerToken: token, context: context)
        } catch MultiSetError.unauthorized where endpoint.requiresAuthentication {
            await auth.invalidateToken()
            let retryToken = try await auth.validToken()
            try await client.sendForData(endpoint, bearerToken: retryToken, context: context)
        }
    }

    private func measure<T>(_ work: () async throws -> T) async rethrows -> (T, Duration) {
        let start = ContinuousClock.now
        let value = try await work()
        return (value, ContinuousClock.now - start)
    }

    // MARK: - Account

    public func userProfile() async throws -> UserProfile {
        try await authorized(Endpoint(path: "/v1/user"), as: UserProfile.self, context: "your profile")
    }

    public func planDetails() async throws -> PlanDetails {
        try await authorized(
            Endpoint(path: "/v1/account/plan-details"),
            as: PlanDetails.self,
            context: "plan details"
        )
    }

    public func mintM2MCredentials(name: String) async throws -> M2MCredentials {
        struct Payload: Encodable {
            let name: String
        }
        let endpoint = try Endpoint.json(.post, "/v1/m2m", body: Payload(name: name))
        let client = try await authorized(endpoint, as: M2MClient.self, context: "SDK credentials")
        guard let secret = client.clientSecret else {
            throw MultiSetError.decoding(context: "SDK credentials")
        }
        return M2MCredentials(clientId: client.clientId, clientSecret: secret)
    }

    public func m2mClients(page: Page = .first) async throws -> [M2MClient] {
        let endpoint = Endpoint.paged("/v1/m2m", page: page.index, limit: page.limit)
        return try await authorized(endpoint, as: M2MClientListPage.self, context: "SDK credentials")
            .clients ?? []
    }

    // MARK: - Library

    public func maps(
        page: Page = .first,
        search: String? = nil,
        status: ResourceStatus? = nil
    ) async throws -> MapListPage {
        let endpoint = Endpoint.paged(
            "/v1/vps/map",
            page: page.index,
            limit: page.limit,
            searchKey: "query",
            searchText: search,
            extra: ["status": status.flatMap { $0 == .unknown ? nil : $0.rawValue }]
        )
        return try await authorized(endpoint, as: MapListPage.self, context: "your maps")
    }

    public func map(code: String) async throws -> VPSMap {
        try await authorized(
            Endpoint(path: "/v1/vps/map/\(code)"),
            as: VPSMap.self,
            context: "map \(code)"
        )
    }

    public func mapSets(page: Page = .first, search: String? = nil) async throws -> MapSetListPage {
        // MapSets spell the search parameter `search`, not `query`.
        let endpoint = Endpoint.paged(
            "/v1/vps/map-set",
            page: page.index,
            limit: page.limit,
            searchKey: "search",
            searchText: search
        )
        return try await authorized(endpoint, as: MapSetListPage.self, context: "your map sets")
    }

    public func mapSet(code: String) async throws -> MapSet {
        try await authorized(
            Endpoint(path: "/v1/vps/map-set/\(code)"),
            as: MapSetEnvelope.self,
            context: "map set \(code)"
        ).mapSet
    }

    public func trackedObjects(page: Page = .first, search: String? = nil) async throws -> TrackedObjectListPage {
        let endpoint = Endpoint.paged(
            "/v1/vps/object",
            page: page.index,
            limit: page.limit,
            searchKey: "query",
            searchText: search
        )
        return try await authorized(endpoint, as: TrackedObjectListPage.self, context: "your objects")
    }

    public func trackedObject(code: String) async throws -> TrackedObject {
        try await authorized(
            Endpoint(path: "/v1/vps/object/\(code)"),
            as: TrackedObject.self,
            context: "object \(code)"
        )
    }

    public func fileURL(key: String) async throws -> URL {
        let endpoint = Endpoint(path: "/v1/file", query: ["key": key])
        let response = try await authorized(endpoint, as: FileURL.self, context: "file")
        guard let url = response.resolved else {
            throw MultiSetError.decoding(context: "file URL")
        }
        return url
    }

    // MARK: - Localization

    public func localizeSingleFrame(
        _ query: LocalizationQuery,
        frame: QueryFrame
    ) async throws -> LocalizationResult {
        var form = MultipartFormData()
        appendCommonFields(&form, query: query)
        form.append(frame.jpegData, name: "queryImage", filename: "image.JPG")

        let endpoint = Endpoint.multipart("/v1/vps/map/query-form", form: form)
        let (response, latency) = try await measure {
            try await authorized(endpoint, as: SingleFrameLocalizeResponse.self, context: "localization")
        }
        return try response.normalized(latency: latency)
    }

    public func localizeMultiFrame(
        _ query: LocalizationQuery,
        frames: [QueryFrame]
    ) async throws -> LocalizationResult {
        guard !frames.isEmpty else {
            throw MultiSetError.notLocalized(message: "No frames were captured.")
        }
        var form = MultipartFormData()
        appendCommonFields(&form, query: query)
        for code in query.hintMapCodes {
            form.append(code, name: "hintMapCodes")
        }
        for (index, frame) in frames.enumerated() {
            form.append(frame.jpegData, name: "queryImage_\(index)", filename: "image_\(index).JPG")
            if let metadata = frame.metadataJSON {
                form.append(metadata, name: "metadata_\(index)")
            }
        }

        let endpoint = Endpoint.multipart("/v1/vps/map/multi-image-query", form: form)
        let (response, latency) = try await measure {
            try await authorized(endpoint, as: MultiFrameLocalizeResponse.self, context: "localization")
        }
        return try response.normalized(latency: latency)
    }

    public func queryObject(_ query: ObjectQuery, frame: QueryFrame) async throws -> ObjectTrackingResult {
        var form = MultipartFormData()
        for code in query.objectCodes {
            form.append(code, name: "objectCode")
        }
        form.append(query.isRightHanded, name: "isRightHanded")
        form.append(String(format: "%.4f", query.intrinsics.fx), name: "fx")
        form.append(String(format: "%.4f", query.intrinsics.fy), name: "fy")
        form.append(String(format: "%.4f", query.intrinsics.px), name: "px")
        form.append(String(format: "%.4f", query.intrinsics.py), name: "py")
        form.append("\(query.resolution.width)", name: "width")
        form.append("\(query.resolution.height)", name: "height")
        form.append(frame.jpegData, name: "queryImage", filename: "image.JPG")

        let endpoint = Endpoint.multipart("/v1/vps/object/query", form: form)
        let (response, latency) = try await measure {
            try await authorized(endpoint, as: ObjectTrackingResponse.self, context: "object tracking")
        }
        return try response.normalized(latency: latency)
    }

    private func appendCommonFields(_ form: inout MultipartFormData, query: LocalizationQuery) {
        form.append(query.target.code, name: query.target.formFieldName)
        form.append(query.isRightHanded, name: "isRightHanded")
        form.append(String(format: "%.4f", query.intrinsics.fx), name: "fx")
        form.append(String(format: "%.4f", query.intrinsics.fy), name: "fy")
        form.append(String(format: "%.4f", query.intrinsics.px), name: "px")
        form.append(String(format: "%.4f", query.intrinsics.py), name: "py")
        form.append("\(query.resolution.width)", name: "width")
        form.append("\(query.resolution.height)", name: "height")
        if let geoHint = query.geoHint, geoHint.isValid {
            form.append(geoHint.geoHintString, name: "geoHint")
        }
        if let hintRadius = query.hintRadius {
            form.append("\(hintRadius)", name: "hintRadius")
        }
        if query.use2DFiltering {
            form.append(true, name: "use2DFiltering")
        }
        if query.convertToGeoCoordinates {
            form.append(true, name: "convertToGeoCoordinates")
        }
    }

    // MARK: - Experiences

    public func contentSpaces(page: Page = .first, search: String? = nil) async throws -> ContentSpaceListPage {
        // Content Spaces spell the search parameter `name`.
        let endpoint = Endpoint.paged(
            "/v1/content-space",
            page: page.index,
            limit: page.limit,
            searchKey: "name",
            searchText: search
        )
        return try await authorized(endpoint, as: ContentSpaceListPage.self, context: "your experiences")
    }

    public func contentSpace(id: String, page: Page = Page(index: 1, limit: 100)) async throws -> ContentSpaceDetail {
        let endpoint = Endpoint(
            path: "/v1/content-space/\(id)",
            query: ["page": "\(page.index)", "limit": "\(page.limit)"]
        )
        return try await authorized(endpoint, as: ContentSpaceDetail.self, context: "experience \(id)")
    }

    public func createContentSpace(_ draft: ContentSpaceDraft) async throws -> ContentSpace {
        struct Payload: Encodable {
            let name: String
            let description: String?
            let thumbnail: String?
            let mapId: String?
            let mapSetId: String?
        }
        struct Response: Decodable {
            let contentSpace: ContentSpace
        }
        let payload = Payload(
            name: draft.name,
            description: draft.description,
            thumbnail: draft.thumbnailKey,
            mapId: { if case .map(let code) = draft.target { return code } else { return nil } }(),
            mapSetId: { if case .mapSet(let code) = draft.target { return code } else { return nil } }()
        )
        let endpoint = try Endpoint.json(.post, "/v1/content-space", body: payload)
        return try await authorized(endpoint, as: Response.self, context: "the experience").contentSpace
    }

    public func publishContentSpace(id: String) async throws {
        try await authorizedVoid(
            Endpoint(method: .put, path: "/v1/content-space/\(id)/publish"),
            context: "publishing"
        )
    }

    public func unpublishContentSpace(id: String) async throws {
        try await authorizedVoid(
            Endpoint(method: .put, path: "/v1/content-space/\(id)/unpublish"),
            context: "revoking"
        )
    }

    public func setContentSpacePublic(id: String, isPublic: Bool) async throws {
        let suffix = isPublic ? "public" : "private"
        try await authorizedVoid(
            Endpoint(method: .put, path: "/v1/content-space/\(id)/\(suffix)"),
            context: "sharing settings"
        )
    }

    public func deleteContentSpace(id: String) async throws {
        try await authorizedVoid(
            Endpoint(method: .delete, path: "/v1/content-space/\(id)"),
            context: "the experience"
        )
    }

    public func addContent(_ draft: ContentDraft) async throws -> SpaceContent {
        struct AssetRef: Encodable {
            let assetId: String
        }
        struct Payload: Encodable {
            let contentSpaceId: String
            let title: String
            let type: String
            let position: Position
            let rotation: Rotation
            let scale: Scale
            let contentData: AssetRef?

            enum CodingKeys: String, CodingKey {
                case contentSpaceId, title, type, position, rotation, scale
                case contentData = "content_data"
            }
        }
        struct Response: Decodable {
            let content: SpaceContent
        }
        let payload = Payload(
            contentSpaceId: draft.contentSpaceId,
            title: draft.title,
            type: draft.type.rawValue,
            position: draft.position,
            rotation: draft.rotation,
            scale: draft.scale,
            contentData: draft.assetId.map(AssetRef.init)
        )
        let endpoint = try Endpoint.json(.post, "/v1/content", body: payload)
        return try await authorized(endpoint, as: Response.self, context: "the point of interest").content
    }

    public func updateContent(id: String, _ update: ContentUpdate) async throws {
        struct Payload: Encodable {
            let title: String?
            let position: Position?
            let rotation: Rotation?
            let scale: Scale?
        }
        let endpoint = try Endpoint.json(
            .put, "/v1/content/\(id)",
            body: Payload(
                title: update.title,
                position: update.position,
                rotation: update.rotation,
                scale: update.scale
            )
        )
        try await authorizedVoid(endpoint, context: "the point of interest")
    }

    public func deleteContent(id: String) async throws {
        try await authorizedVoid(
            Endpoint(method: .delete, path: "/v1/content/\(id)"),
            context: "the point of interest"
        )
    }

    /// Assembles a manifest from the anonymous experience token plus the space's
    /// own contents. Requires no developer credential at any step.
    public func resolveExperience(spaceCode: String) async throws -> ExperienceManifest {
        let token = try await auth.resolveExperience(spaceCode: spaceCode)
        let detail = try await contentSpace(id: spaceCode, page: Page(index: 1, limit: 100))
        return try ExperienceManifestBuilder.build(from: detail, token: token, spaceCode: spaceCode)
    }

    // MARK: - Analytics

    public func accountAnalytics(range: DateRange) async throws -> AnalyticsSummary {
        let endpoint = Endpoint(
            path: "/v1/account/analytics",
            query: [
                "startDate": ISO8601DateFormatter().string(from: range.start),
                "endDate": ISO8601DateFormatter().string(from: range.end)
            ]
        )
        return try await authorized(endpoint, as: AnalyticsSummary.self, context: "usage")
    }

    public func queryAnalytics(
        mapId: String?,
        objectId: String?,
        range: DateRange,
        page: Page = Page(index: 1, limit: 200)
    ) async throws -> [QueryRecord] {
        let formatter = ISO8601DateFormatter()
        let endpoint = Endpoint(
            path: "/v1/account/analytics/query-api",
            query: [
                "mapId": mapId,
                "objectId": objectId,
                "startDate": formatter.string(from: range.start),
                "endDate": formatter.string(from: range.end),
                "page": "\(page.index)",
                "limit": "\(page.limit)"
            ]
        )
        return try await authorized(endpoint, as: QueryRecordPage.self, context: "query history").records
    }

    public func heatmap(mapId: String, range: DateRange) async throws -> [HeatmapCell] {
        let formatter = ISO8601DateFormatter()
        let endpoint = Endpoint(
            path: "/v1/account/analytics/heatmap/\(mapId)",
            query: [
                "startDate": formatter.string(from: range.start),
                "endDate": formatter.string(from: range.end)
            ]
        )
        return try await authorized(endpoint, as: HeatmapResponse.self, context: "the heatmap").allCells
    }

    // MARK: - Simulation

    public func simulationDatasets(page: Page = .first) async throws -> [SimulationDataset] {
        let endpoint = Endpoint.paged("/v1/simulation-data", page: page.index, limit: page.limit)
        return try await authorized(endpoint, as: SimulationDataPage.self, context: "simulation data")
            .simulationData
    }
}
