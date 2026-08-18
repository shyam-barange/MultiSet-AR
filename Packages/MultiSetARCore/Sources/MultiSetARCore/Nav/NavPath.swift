import Foundation
import MultiSetKit
import simd

/// Turn-by-turn guidance derived from a route and the user's current position.
public struct NavGuidance: Sendable, Equatable {
    public enum Turn: String, Sendable {
        case straight, left, right, sharpLeft, sharpRight, uTurn, arrive

        public var instruction: String {
            switch self {
            case .straight: "Continue straight"
            case .left: "Turn left"
            case .right: "Turn right"
            case .sharpLeft: "Bear sharply left"
            case .sharpRight: "Bear sharply right"
            case .uTurn: "Turn around"
            case .arrive: "You've arrived"
            }
        }

        public var symbolName: String {
            switch self {
            case .straight: "arrow.up"
            case .left: "arrow.turn.up.left"
            case .right: "arrow.turn.up.right"
            case .sharpLeft: "arrow.uturn.left"
            case .sharpRight: "arrow.uturn.right"
            case .uTurn: "arrow.uturn.down"
            case .arrive: "flag.checkered"
            }
        }
    }

    public var remainingDistance: Double
    public var turn: Turn
    public var destinationName: String
    public var hasArrived: Bool

    public init(remainingDistance: Double, turn: Turn, destinationName: String, hasArrived: Bool) {
        self.remainingDistance = remainingDistance
        self.turn = turn
        self.destinationName = destinationName
        self.hasArrived = hasArrived
    }

    /// Distance rounded the way people describe it — no false precision.
    public var distanceDescription: String {
        if remainingDistance < 2 { return "arriving" }
        if remainingDistance < 10 { return "\(Int(remainingDistance.rounded())) m" }
        return "\(Int((remainingDistance / 5).rounded() * 5)) m"
    }
}

public enum NavPathPlanner {
    /// Within this radius of the destination the user has arrived. Set to the
    /// scale of a room feature rather than VPS accuracy, because standing
    /// "at the dispatch desk" is a metre-scale idea, not a centimetre one.
    public static let arrivalRadius: Double = 1.5

    public static func guidance(
        route: AStar.Route,
        userPosition: Position,
        heading: SIMD3<Float>,
        destinationName: String
    ) -> NavGuidance {
        let remaining = route.remainingDistance(from: userPosition)
        let arrived = remaining <= arrivalRadius

        guard !arrived, let next = route.nextNode(from: userPosition) else {
            return NavGuidance(
                remainingDistance: remaining,
                turn: .arrive,
                destinationName: destinationName,
                hasArrived: true
            )
        }

        return NavGuidance(
            remainingDistance: remaining,
            turn: turn(from: userPosition, toward: next.position, heading: heading),
            destinationName: destinationName,
            hasArrived: false
        )
    }

    /// Classifies the bearing change on the horizontal plane. Vertical
    /// difference is ignored — a ramp is still "straight ahead".
    static func turn(from position: Position, toward target: Position, heading: SIMD3<Float>) -> NavGuidance.Turn {
        let toTarget = SIMD2<Float>(Float(target.x - position.x), Float(target.z - position.z))
        let facing = SIMD2<Float>(heading.x, heading.z)
        guard simd_length(toTarget) > 1e-4, simd_length(facing) > 1e-4 else { return .straight }

        let a = simd_normalize(facing)
        let b = simd_normalize(toTarget)
        let dot = max(-1, min(1, simd_dot(a, b)))
        let angle = acos(dot) * 180 / .pi
        // Cross product sign on the XZ plane gives the turn direction.
        let side = a.x * b.y - a.y * b.x

        switch angle {
        case ..<25: return .straight
        case ..<115: return side < 0 ? .left : .right
        case ..<150: return side < 0 ? .sharpLeft : .sharpRight
        default: return .uTurn
        }
    }

    /// Resamples the route into evenly spaced points for the ribbon geometry, so
    /// a long straight leg still gets enough vertices to look continuous.
    public static func densified(_ positions: [Position], spacing: Double = 0.35) -> [Position] {
        guard positions.count > 1, spacing > 0 else { return positions }
        var result: [Position] = [positions[0]]
        for index in 0..<(positions.count - 1) {
            let start = positions[index]
            let end = positions[index + 1]
            let length = AStar.distance(start, end)
            guard length > spacing else {
                result.append(end)
                continue
            }
            let steps = Int((length / spacing).rounded(.down))
            for step in 1...steps {
                let t = Double(step) / Double(steps + 1)
                result.append(Position(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t,
                    z: start.z + (end.z - start.z) * t
                ))
            }
            result.append(end)
        }
        return result
    }
}
