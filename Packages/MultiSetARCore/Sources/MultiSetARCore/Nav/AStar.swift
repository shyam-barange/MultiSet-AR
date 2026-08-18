import Foundation
import MultiSetKit

/// Shortest path over a nav graph.
///
/// Costs default to straight-line distance between nodes, but an edge may
/// declare its own — a corridor that doubles back is longer than the gap
/// between its endpoints, and pathing on geometry alone would route people
/// through walls.
public enum AStar {
    public struct Route: Sendable, Equatable {
        public let nodes: [NavGraph.Node]
        public let totalDistance: Double

        public init(nodes: [NavGraph.Node], totalDistance: Double) {
            self.nodes = nodes
            self.totalDistance = totalDistance
        }

        public var positions: [Position] { nodes.map(\.position) }
        public var isEmpty: Bool { nodes.isEmpty }
    }

    public static func route(in graph: NavGraph, from startID: String, to goalID: String) -> Route? {
        guard let start = graph.node(id: startID), let goal = graph.node(id: goalID) else { return nil }
        if startID == goalID {
            return Route(nodes: [start], totalDistance: 0)
        }

        let nodesByID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let adjacency = adjacencyList(graph)

        var openSet: Set<String> = [startID]
        var cameFrom: [String: String] = [:]
        var costFromStart: [String: Double] = [startID: 0]
        var estimatedTotal: [String: Double] = [startID: distance(start.position, goal.position)]

        while !openSet.isEmpty {
            // Small graphs — a linear scan of the open set beats a heap here, and
            // a venue nav graph is tens of nodes, not thousands.
            guard let current = openSet.min(by: {
                (estimatedTotal[$0] ?? .infinity) < (estimatedTotal[$1] ?? .infinity)
            }) else { break }

            if current == goalID {
                return reconstruct(
                    cameFrom: cameFrom,
                    current: current,
                    nodesByID: nodesByID,
                    totalDistance: costFromStart[current] ?? 0
                )
            }

            openSet.remove(current)
            guard let currentNode = nodesByID[current] else { continue }

            for neighbour in adjacency[current] ?? [] {
                guard let neighbourNode = nodesByID[neighbour.id] else { continue }
                let step = neighbour.cost ?? distance(currentNode.position, neighbourNode.position)
                let tentative = (costFromStart[current] ?? .infinity) + step
                guard tentative < (costFromStart[neighbour.id] ?? .infinity) else { continue }

                cameFrom[neighbour.id] = current
                costFromStart[neighbour.id] = tentative
                estimatedTotal[neighbour.id] = tentative + distance(neighbourNode.position, goal.position)
                openSet.insert(neighbour.id)
            }
        }
        return nil
    }

    /// Routes from wherever the user is to a destination node, entering the graph
    /// at the nearest node.
    public static func route(in graph: NavGraph, fromPosition position: Position, to goalID: String) -> Route? {
        guard let entry = graph.node(nearest: position) else { return nil }
        return route(in: graph, from: entry.id, to: goalID)
    }

    struct Neighbour {
        let id: String
        let cost: Double?
    }

    /// Edges are undirected: a corridor walkable one way is walkable the other.
    static func adjacencyList(_ graph: NavGraph) -> [String: [Neighbour]] {
        var adjacency: [String: [Neighbour]] = [:]
        for edge in graph.edges {
            adjacency[edge.from, default: []].append(Neighbour(id: edge.to, cost: edge.cost))
            adjacency[edge.to, default: []].append(Neighbour(id: edge.from, cost: edge.cost))
        }
        return adjacency
    }

    static func distance(_ a: Position, _ b: Position) -> Double {
        NavGraph.squaredDistance(a, b).squareRoot()
    }

    private static func reconstruct(
        cameFrom: [String: String],
        current: String,
        nodesByID: [String: NavGraph.Node],
        totalDistance: Double
    ) -> Route {
        var path = [current]
        var cursor = current
        while let previous = cameFrom[cursor] {
            path.append(previous)
            cursor = previous
        }
        return Route(
            nodes: path.reversed().compactMap { nodesByID[$0] },
            totalDistance: totalDistance
        )
    }
}

public extension AStar.Route {
    /// Distance still to walk from a position along the remainder of the route.
    func remainingDistance(from position: Position) -> Double {
        guard let index = nearestLegIndex(to: position) else { return totalDistance }
        var remaining = AStar.distance(position, nodes[index].position)
        for step in index..<(nodes.count - 1) {
            remaining += AStar.distance(nodes[step].position, nodes[step + 1].position)
        }
        return remaining
    }

    /// The next node the user should head toward.
    func nextNode(from position: Position) -> NavGraph.Node? {
        guard let index = nearestLegIndex(to: position) else { return nodes.last }
        return nodes[index]
    }

    private func nearestLegIndex(to position: Position) -> Int? {
        guard !nodes.isEmpty else { return nil }
        let index = nodes.indices.min {
            NavGraph.squaredDistance(nodes[$0].position, position)
                < NavGraph.squaredDistance(nodes[$1].position, position)
        }
        guard let index else { return nil }
        // Aim at the node after the closest one, unless the closest is the goal.
        return min(index + 1, nodes.count - 1)
    }
}
