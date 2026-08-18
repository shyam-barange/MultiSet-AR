import Foundation

public enum ExperienceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case localize
    case navigate
    case track

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localize: "Localize"
        case .navigate: "Navigate"
        case .track: "Track"
        }
    }

    /// The Clip's single primary button. An action keeps its verb through the flow.
    public var primaryActionTitle: String {
        switch self {
        case .localize: "Start positioning"
        case .navigate: "Start navigating"
        case .track: "Start tracking"
        }
    }

    public var symbolName: String {
        switch self {
        case .localize: "scope"
        case .navigate: "arrow.triangle.turn.up.right.diamond"
        case .track: "cube.transparent"
        }
    }
}

public struct ExperienceBranding: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var accentHex: String?
    public var logoURL: URL?

    public init(title: String, subtitle: String? = nil, accentHex: String? = nil, logoURL: URL? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accentHex = accentHex
        self.logoURL = logoURL
    }
}

public struct PointOfInterest: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var position: Position
    public var rotation: Rotation?

    public init(id: String, title: String, position: Position, rotation: Rotation? = nil) {
        self.id = id
        self.title = title
        self.position = position
        self.rotation = rotation
    }

    public init?(content: SpaceContent) {
        guard content.isPointOfInterest else { return nil }
        self.init(id: content.id, title: content.title, position: content.position, rotation: content.rotation)
    }
}

/// Everything an AR session needs to run, resolved from a `spaceCode`. The Clip
/// obtains this with an anonymous experience token and never holds a credential.
public struct ExperienceManifest: Sendable, Equatable {
    public var spaceCode: String
    public var mode: ExperienceMode
    public var target: MapTarget
    public var branding: ExperienceBranding
    public var pointsOfInterest: [PointOfInterest]
    public var destinationPOIID: String?
    public var objectCodes: [String]
    public var navGraph: NavGraph?
    public var token: AuthToken

    public init(
        spaceCode: String,
        mode: ExperienceMode,
        target: MapTarget,
        branding: ExperienceBranding,
        pointsOfInterest: [PointOfInterest] = [],
        destinationPOIID: String? = nil,
        objectCodes: [String] = [],
        navGraph: NavGraph? = nil,
        token: AuthToken
    ) {
        self.spaceCode = spaceCode
        self.mode = mode
        self.target = target
        self.branding = branding
        self.pointsOfInterest = pointsOfInterest
        self.destinationPOIID = destinationPOIID
        self.objectCodes = objectCodes
        self.navGraph = navGraph
        self.token = token
    }

    public var destination: PointOfInterest? {
        guard let destinationPOIID else { return pointsOfInterest.first }
        return pointsOfInterest.first { $0.id == destinationPOIID }
    }

    /// What the Clip's intro card promises will happen, in the interface's voice.
    public var expectation: String {
        switch mode {
        case .localize:
            "Point your camera at the space around you. We'll work out exactly where you're standing."
        case .navigate:
            if let destination = destination {
                "Point your camera at the space around you, then follow the line to \(destination.title)."
            } else {
                "Point your camera at the space around you, then follow the line to your destination."
            }
        case .track:
            "Point your camera at the object. We'll trace it as you move around it."
        }
    }
}

/// A walkable graph over a map's coordinate frame. The platform has no graph API,
/// so this is stored in Content Space metadata or as an uploaded JSON asset.
public struct NavGraph: Codable, Sendable, Equatable {
    public struct Node: Codable, Sendable, Identifiable, Hashable {
        public var id: String
        public var position: Position
        /// Set when this node coincides with a `location_pin` content item.
        public var poiID: String?

        public init(id: String, position: Position, poiID: String? = nil) {
            self.id = id
            self.position = position
            self.poiID = poiID
        }
    }

    public struct Edge: Codable, Sendable, Hashable {
        public var from: String
        public var to: String
        /// Overrides straight-line distance when the real path is longer.
        public var cost: Double?

        public init(from: String, to: String, cost: Double? = nil) {
            self.from = from
            self.to = to
            self.cost = cost
        }
    }

    public var nodes: [Node]
    public var edges: [Edge]

    public init(nodes: [Node], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }

    public func node(id: String) -> Node? {
        nodes.first { $0.id == id }
    }

    public func node(nearest position: Position) -> Node? {
        nodes.min { lhs, rhs in
            Self.squaredDistance(lhs.position, position) < Self.squaredDistance(rhs.position, position)
        }
    }

    public static func squaredDistance(_ a: Position, _ b: Position) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return dx * dx + dy * dy + dz * dz
    }
}
