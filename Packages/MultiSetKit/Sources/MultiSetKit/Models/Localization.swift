import Foundation

public enum LocalizationMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case singleFrame
    case multiFrame

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .singleFrame: "Single frame"
        case .multiFrame: "Multi frame"
        }
    }

    public var explanation: String {
        switch self {
        case .singleFrame: "One image per query. Fastest, least robust."
        case .multiFrame: "Several images with poses. Slower, far more reliable."
        }
    }
}

/// Which code a query targets. Mutually exclusive — the API accepts one or the
/// other, never both, and a session cannot switch mid-flight.
public enum MapTarget: Sendable, Hashable, Codable {
    case map(code: String)
    case mapSet(code: String)

    public var code: String {
        switch self {
        case .map(let code), .mapSet(let code): code
        }
    }

    public var formFieldName: String {
        switch self {
        case .map: "mapCode"
        case .mapSet: "mapSetCode"
        }
    }
}

public struct LocalizationQuery: Sendable {
    public var target: MapTarget
    public var intrinsics: CameraIntrinsics
    public var resolution: Resolution
    /// ARKit is right-handed. The Unity SDK sends `false`; native iOS sends `true`.
    public var isRightHanded: Bool
    public var geoHint: GeoCoordinates?
    public var hintRadius: Int?
    public var use2DFiltering: Bool
    public var convertToGeoCoordinates: Bool
    public var hintMapCodes: [String]

    public init(
        target: MapTarget,
        intrinsics: CameraIntrinsics,
        resolution: Resolution,
        isRightHanded: Bool = true,
        geoHint: GeoCoordinates? = nil,
        hintRadius: Int? = nil,
        use2DFiltering: Bool = false,
        convertToGeoCoordinates: Bool = false,
        hintMapCodes: [String] = []
    ) {
        self.target = target
        self.intrinsics = intrinsics
        self.resolution = resolution
        self.isRightHanded = isRightHanded
        self.geoHint = geoHint
        self.hintRadius = hintRadius
        self.use2DFiltering = use2DFiltering
        self.convertToGeoCoordinates = convertToGeoCoordinates
        self.hintMapCodes = hintMapCodes
    }
}

/// One captured frame plus the ARKit pose it was captured at.
public struct QueryFrame: Sendable {
    public var jpegData: Data
    public var pose: Pose?

    public init(jpegData: Data, pose: Pose? = nil) {
        self.jpegData = jpegData
        self.pose = pose
    }

    /// The `metadata_N` JSON the multi-image endpoint expects, which flattens
    /// position and quaternion into one object with `qx`-style rotation keys.
    public var metadataJSON: String? {
        guard let pose else { return nil }
        let fields: [(String, Double)] = [
            ("x", pose.position.x), ("y", pose.position.y), ("z", pose.position.z),
            ("qx", pose.rotation.x), ("qy", pose.rotation.y),
            ("qz", pose.rotation.z), ("qw", pose.rotation.w)
        ]
        let body = fields
            .map { "\"\($0.0)\":\(String(format: "%.6f", $0.1))" }
            .joined(separator: ",")
        return "{\(body)}"
    }
}

/// A successful localization, normalised from either endpoint's response shape.
public struct LocalizationResult: Sendable, Equatable {
    public var pose: Pose
    /// Present only on multi-frame queries: the ARKit pose the server matched against.
    public var trackingPose: Pose?
    public var confidence: Double?
    public var mapCodes: [String]
    public var mapIds: [String]
    public var geoCoordinates: GeoCoordinates?
    public var mode: LocalizationMode
    public var latency: Duration

    public init(
        pose: Pose,
        trackingPose: Pose? = nil,
        confidence: Double? = nil,
        mapCodes: [String] = [],
        mapIds: [String] = [],
        geoCoordinates: GeoCoordinates? = nil,
        mode: LocalizationMode,
        latency: Duration = .zero
    ) {
        self.pose = pose
        self.trackingPose = trackingPose
        self.confidence = confidence
        self.mapCodes = mapCodes
        self.mapIds = mapIds
        self.geoCoordinates = geoCoordinates
        self.mode = mode
        self.latency = latency
    }

    public var primaryMapCode: String? { mapCodes.first }
}

// MARK: - Wire shapes

/// `POST /v1/vps/map/query-form` and `/query`, which nest the pose inside
/// `localizationSuccess` and spell the fields inconsistently across API versions.
struct SingleFrameLocalizeResponse: Decodable {
    struct Success: Decodable {
        var poseFound: Bool?
        var position: Position?
        var rotation: Rotation?
        var estimatedPose: Pose?
        var trackingPose: Pose?
        var confidence: Double?
        var mapIds: [String]?
        var mapCodes: [String]?

        /// Older responses put the pose under `estimatedPose`; newer ones inline
        /// `position` and `rotation` directly.
        var resolvedPose: Pose? {
            if let estimatedPose { return estimatedPose }
            guard let position, let rotation else { return nil }
            return Pose(position: position, rotation: rotation)
        }
    }

    struct Failure: Decodable {
        var poseFound: Bool?
        var message: String?
    }

    var poseFound: Bool?
    var localizationSuccess: Success?
    var localizationFailure: Failure?
}

/// `POST /v1/vps/map/multi-image-query`, which returns the pose at the top level.
struct MultiFrameLocalizeResponse: Decodable {
    var poseFound: Bool?
    var estimatedPose: Pose?
    var trackingPose: Pose?
    var confidence: Double?
    var mapIds: [String]?
    var mapCodes: [String]?
    var geoCoordinates: GeoCoordinates?
    var localizationFailure: SingleFrameLocalizeResponse.Failure?
}

extension SingleFrameLocalizeResponse {
    func normalized(latency: Duration) throws -> LocalizationResult {
        guard poseFound == true || localizationSuccess?.poseFound == true,
              let success = localizationSuccess,
              let pose = success.resolvedPose
        else {
            throw MultiSetError.notLocalized(message: localizationFailure?.message)
        }
        return LocalizationResult(
            pose: pose,
            trackingPose: success.trackingPose,
            confidence: success.confidence,
            mapCodes: success.mapCodes ?? [],
            mapIds: success.mapIds ?? [],
            mode: .singleFrame,
            latency: latency
        )
    }
}

extension MultiFrameLocalizeResponse {
    func normalized(latency: Duration) throws -> LocalizationResult {
        guard poseFound == true, let pose = estimatedPose else {
            throw MultiSetError.notLocalized(message: localizationFailure?.message)
        }
        return LocalizationResult(
            pose: pose,
            trackingPose: trackingPose,
            confidence: confidence,
            mapCodes: mapCodes ?? [],
            mapIds: mapIds ?? [],
            geoCoordinates: geoCoordinates,
            mode: .multiFrame,
            latency: latency
        )
    }
}

// MARK: - Object tracking

public struct ObjectQuery: Sendable {
    public var objectCodes: [String]
    public var intrinsics: CameraIntrinsics
    public var resolution: Resolution
    public var isRightHanded: Bool

    public init(
        objectCodes: [String],
        intrinsics: CameraIntrinsics,
        resolution: Resolution,
        isRightHanded: Bool = true
    ) {
        self.objectCodes = objectCodes
        self.intrinsics = intrinsics
        self.resolution = resolution
        self.isRightHanded = isRightHanded
    }
}

public struct ObjectTrackingResult: Sendable, Equatable {
    public var pose: Pose
    public var confidence: Double?
    public var objectCodes: [String]
    public var latency: Duration

    public init(pose: Pose, confidence: Double? = nil, objectCodes: [String] = [], latency: Duration = .zero) {
        self.pose = pose
        self.confidence = confidence
        self.objectCodes = objectCodes
        self.latency = latency
    }

    public var primaryObjectCode: String? { objectCodes.first }
}

struct ObjectTrackingResponse: Decodable {
    var poseFound: Bool?
    var position: Position?
    var rotation: Rotation?
    var confidence: Double?
    var objectCodes: [String]?
    var message: String?

    func normalized(latency: Duration) throws -> ObjectTrackingResult {
        guard poseFound == true, let position, let rotation else {
            throw MultiSetError.notLocalized(message: message)
        }
        return ObjectTrackingResult(
            pose: Pose(position: position, rotation: rotation),
            confidence: confidence,
            objectCodes: objectCodes ?? [],
            latency: latency
        )
    }
}
