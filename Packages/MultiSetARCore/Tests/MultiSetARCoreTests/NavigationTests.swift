import XCTest
import MultiSetKit
import simd
@testable import MultiSetARCore

final class AStarTests: XCTestCase {
    /// A corridor with a shortcut that is geometrically shorter but not walkable,
    /// so cost overrides matter.
    ///
    ///   n1 ── n2 ── n3 ── n4
    ///    └───────── n5 ────┘   (n5 legs carry a high declared cost)
    private func graph() -> NavGraph {
        NavGraph(
            nodes: [
                .init(id: "n1", position: Position(x: 0, y: 0, z: 0)),
                .init(id: "n2", position: Position(x: 5, y: 0, z: 0)),
                .init(id: "n3", position: Position(x: 10, y: 0, z: 0)),
                .init(id: "n4", position: Position(x: 15, y: 0, z: 0), poiID: "poi_end"),
                .init(id: "n5", position: Position(x: 7.5, y: 0, z: 1))
            ],
            edges: [
                .init(from: "n1", to: "n2"),
                .init(from: "n2", to: "n3"),
                .init(from: "n3", to: "n4"),
                .init(from: "n1", to: "n5", cost: 100),
                .init(from: "n5", to: "n4", cost: 100)
            ]
        )
    }

    func testFindsTheDirectRoute() throws {
        let route = try XCTUnwrap(AStar.route(in: graph(), from: "n1", to: "n4"))
        XCTAssertEqual(route.nodes.map(\.id), ["n1", "n2", "n3", "n4"])
        XCTAssertEqual(route.totalDistance, 15, accuracy: 1e-4)
    }

    func testDeclaredEdgeCostOverridesStraightLineDistance() throws {
        // Through n5 is geometrically shorter but declared expensive, so the
        // long way round must win — a corridor that doubles back is not a
        // shortcut just because its endpoints are close.
        let route = try XCTUnwrap(AStar.route(in: graph(), from: "n1", to: "n4"))
        XCTAssertFalse(route.nodes.map(\.id).contains("n5"))
    }

    func testRouteIsSymmetricBecauseEdgesAreUndirected() throws {
        let forward = try XCTUnwrap(AStar.route(in: graph(), from: "n1", to: "n4"))
        let backward = try XCTUnwrap(AStar.route(in: graph(), from: "n4", to: "n1"))
        XCTAssertEqual(forward.nodes.map(\.id), backward.nodes.map(\.id).reversed())
        XCTAssertEqual(forward.totalDistance, backward.totalDistance, accuracy: 1e-4)
    }

    func testRouteToSelfIsASingleNodeAtZeroDistance() throws {
        let route = try XCTUnwrap(AStar.route(in: graph(), from: "n2", to: "n2"))
        XCTAssertEqual(route.nodes.map(\.id), ["n2"])
        XCTAssertEqual(route.totalDistance, 0)
    }

    func testUnknownNodeIDsYieldNoRoute() {
        XCTAssertNil(AStar.route(in: graph(), from: "nope", to: "n4"))
        XCTAssertNil(AStar.route(in: graph(), from: "n1", to: "nope"))
    }

    func testDisconnectedGraphYieldsNoRoute() {
        let split = NavGraph(
            nodes: [
                .init(id: "a", position: Position(x: 0, y: 0, z: 0)),
                .init(id: "b", position: Position(x: 1, y: 0, z: 0)),
                .init(id: "island", position: Position(x: 50, y: 0, z: 0))
            ],
            edges: [.init(from: "a", to: "b")]
        )
        XCTAssertNil(AStar.route(in: split, from: "a", to: "island"))
    }

    func testEmptyGraphYieldsNoRoute() {
        XCTAssertNil(AStar.route(in: NavGraph(nodes: [], edges: []), from: "a", to: "b"))
    }

    func testEntersTheGraphAtTheNearestNode() throws {
        // Standing beside n3, the route should start there rather than walking
        // back to n1 first.
        let route = try XCTUnwrap(
            AStar.route(in: graph(), fromPosition: Position(x: 9.6, y: 0, z: 0.4), to: "n4")
        )
        XCTAssertEqual(route.nodes.first?.id, "n3")
    }

    func testRemainingDistanceShrinksAlongTheRoute() throws {
        let route = try XCTUnwrap(AStar.route(in: graph(), from: "n1", to: "n4"))
        let atStart = route.remainingDistance(from: Position(x: 0, y: 0, z: 0))
        let midway = route.remainingDistance(from: Position(x: 7.5, y: 0, z: 0))
        let atEnd = route.remainingDistance(from: Position(x: 15, y: 0, z: 0))
        XCTAssertGreaterThan(atStart, midway)
        XCTAssertGreaterThan(midway, atEnd)
        XCTAssertEqual(atEnd, 0, accuracy: 1e-4)
    }

    func testNextNodeAdvancesRatherThanPointingAtTheNodeJustPassed() throws {
        let route = try XCTUnwrap(AStar.route(in: graph(), from: "n1", to: "n4"))
        XCTAssertEqual(route.nextNode(from: Position(x: 0, y: 0, z: 0))?.id, "n2")
        XCTAssertEqual(route.nextNode(from: Position(x: 5, y: 0, z: 0))?.id, "n3")
        XCTAssertEqual(route.nextNode(from: Position(x: 15, y: 0, z: 0))?.id, "n4")
    }

    func testDenseGridResolvesWithoutStalling() throws {
        // 20 x 20 lattice: far larger than a real venue graph, and a guard
        // against the linear open-set scan degrading badly.
        var nodes: [NavGraph.Node] = []
        var edges: [NavGraph.Edge] = []
        for row in 0..<20 {
            for column in 0..<20 {
                nodes.append(.init(
                    id: "\(row)_\(column)",
                    position: Position(x: Double(column), y: 0, z: Double(row))
                ))
                if column > 0 { edges.append(.init(from: "\(row)_\(column - 1)", to: "\(row)_\(column)")) }
                if row > 0 { edges.append(.init(from: "\(row - 1)_\(column)", to: "\(row)_\(column)")) }
            }
        }
        let route = try XCTUnwrap(
            AStar.route(in: NavGraph(nodes: nodes, edges: edges), from: "0_0", to: "19_19")
        )
        // Manhattan distance on a unit grid: 19 + 19 steps.
        XCTAssertEqual(route.totalDistance, 38, accuracy: 1e-4)
    }
}

final class NavGuidanceTests: XCTestCase {
    private func turn(heading: SIMD3<Float>, toward target: Position) -> NavGuidance.Turn {
        NavPathPlanner.turn(from: Position(x: 0, y: 0, z: 0), toward: target, heading: heading)
    }

    private let facingNorth = SIMD3<Float>(0, 0, -1)

    func testStraightAheadIsStraight() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 0, y: 0, z: -10)), .straight)
    }

    func testSlightDeviationStillReadsAsStraight() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 1, y: 0, z: -10)), .straight)
    }

    func testLeftAndRightAreNotMirrored() {
        let left = turn(heading: facingNorth, toward: Position(x: -10, y: 0, z: 0))
        let right = turn(heading: facingNorth, toward: Position(x: 10, y: 0, z: 0))
        XCTAssertEqual(left, .left)
        XCTAssertEqual(right, .right)
        XCTAssertNotEqual(left, right)
    }

    func testBehindReadsAsUTurn() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 0, y: 0, z: 10)), .uTurn)
    }

    func testSharpTurnsAreDistinguishedFromRightAngles() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: -6, y: 0, z: 5)), .sharpLeft)
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 6, y: 0, z: 5)), .sharpRight)
    }

    func testVerticalDifferenceIsIgnoredSoARampIsStillStraight() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 0, y: 4, z: -10)), .straight)
    }

    func testDegenerateInputsDefaultToStraightRatherThanCrashing() {
        XCTAssertEqual(turn(heading: facingNorth, toward: Position(x: 0, y: 0, z: 0)), .straight)
        XCTAssertEqual(turn(heading: SIMD3<Float>(0, 1, 0), toward: Position(x: 1, y: 0, z: 0)), .straight)
    }

    func testArrivalIsDeclaredInsideTheArrivalRadius() {
        let route = AStar.Route(
            nodes: [
                .init(id: "a", position: Position(x: 0, y: 0, z: 0)),
                .init(id: "b", position: Position(x: 10, y: 0, z: 0))
            ],
            totalDistance: 10
        )
        let arrived = NavPathPlanner.guidance(
            route: route,
            userPosition: Position(x: 9.5, y: 0, z: 0),
            heading: facingNorth,
            destinationName: "Dispatch"
        )
        XCTAssertTrue(arrived.hasArrived)
        XCTAssertEqual(arrived.turn, .arrive)

        let enRoute = NavPathPlanner.guidance(
            route: route,
            userPosition: Position(x: 2, y: 0, z: 0),
            heading: facingNorth,
            destinationName: "Dispatch"
        )
        XCTAssertFalse(enRoute.hasArrived)
    }

    func testDistanceDescriptionAvoidsFalsePrecision() {
        func description(_ metres: Double) -> String {
            NavGuidance(
                remainingDistance: metres,
                turn: .straight,
                destinationName: "x",
                hasArrived: false
            ).distanceDescription
        }
        XCTAssertEqual(description(1.2), "arriving")
        XCTAssertEqual(description(7.4), "7 m")
        XCTAssertEqual(description(23), "25 m")
        XCTAssertEqual(description(112), "110 m")
    }

    func testEveryTurnHasAnInstructionAndSymbol() {
        for turn in [
            NavGuidance.Turn.straight, .left, .right, .sharpLeft, .sharpRight, .uTurn, .arrive
        ] {
            XCTAssertFalse(turn.instruction.isEmpty)
            XCTAssertFalse(turn.symbolName.isEmpty)
        }
    }
}

final class DensificationTests: XCTestCase {
    func testLongLegsGainIntermediatePoints() {
        let sparse = [Position(x: 0, y: 0, z: 0), Position(x: 10, y: 0, z: 0)]
        let dense = NavPathPlanner.densified(sparse, spacing: 1)
        XCTAssertGreaterThan(dense.count, sparse.count)
        XCTAssertEqual(dense.first?.x, 0)
        XCTAssertEqual(dense.last?.x, 10)
    }

    func testConsecutivePointsRespectTheSpacing() {
        let dense = NavPathPlanner.densified(
            [Position(x: 0, y: 0, z: 0), Position(x: 10, y: 0, z: 0)],
            spacing: 1
        )
        for index in 0..<(dense.count - 1) {
            XCTAssertLessThanOrEqual(AStar.distance(dense[index], dense[index + 1]), 1.05)
        }
    }

    func testShortLegsAreLeftAlone() {
        let short = [Position(x: 0, y: 0, z: 0), Position(x: 0.2, y: 0, z: 0)]
        XCTAssertEqual(NavPathPlanner.densified(short, spacing: 1).count, 2)
    }

    func testSinglePointAndEmptyInputAreReturnedUnchanged() {
        XCTAssertEqual(NavPathPlanner.densified([]).count, 0)
        XCTAssertEqual(NavPathPlanner.densified([Position(x: 1, y: 2, z: 3)]).count, 1)
    }

    func testZeroSpacingDoesNotLoopForever() {
        let result = NavPathPlanner.densified(
            [Position(x: 0, y: 0, z: 0), Position(x: 5, y: 0, z: 0)],
            spacing: 0
        )
        XCTAssertEqual(result.count, 2)
    }
}

final class ThermalGovernorTests: XCTestCase {
    /// The rule is to slow queries before degrading the camera feed: a longer
    /// re-localization interval is barely noticeable, a stuttering feed is not.
    func testIntervalLengthensMonotonicallyWithHeat() {
        let intervals = ThermalGovernor.Level.allCases.map {
            ThermalGovernor(level: $0).relocalizationInterval
        }
        XCTAssertEqual(intervals, intervals.sorted())
        XCTAssertEqual(ThermalGovernor(level: .nominal).relocalizationInterval, .seconds(30))
        XCTAssertEqual(ThermalGovernor(level: .critical).relocalizationInterval, .seconds(180))
    }

    func testFrameCountHoldsUntilThrottlingTheIntervalIsNotEnough() {
        XCTAssertEqual(ThermalGovernor(level: .nominal).frameCount(requested: 4), 4)
        XCTAssertEqual(ThermalGovernor(level: .fair).frameCount(requested: 4), 4)
        XCTAssertEqual(ThermalGovernor(level: .serious).frameCount(requested: 4), 3)
        XCTAssertEqual(ThermalGovernor(level: .critical).frameCount(requested: 4), 1)
    }

    func testFrameCountNeverDropsToZero() {
        for level in ThermalGovernor.Level.allCases {
            XCTAssertGreaterThanOrEqual(ThermalGovernor(level: level).frameCount(requested: 0), 1)
        }
    }

    func testImageQualityDegradesButStaysUsable() {
        let qualities = ThermalGovernor.Level.allCases.map { ThermalGovernor(level: $0).imageQuality }
        XCTAssertEqual(qualities, qualities.sorted().reversed())
        XCTAssertGreaterThanOrEqual(qualities.min() ?? 0, 0.5)
    }

    func testOnlyCriticalWarnsTheUser() {
        XCTAssertFalse(ThermalGovernor(level: .serious).shouldWarnUser)
        XCTAssertTrue(ThermalGovernor(level: .critical).shouldWarnUser)
    }
}

final class SearchCoachingTests: XCTestCase {
    /// Repeating one line while the user does the wrong thing is why AR sessions
    /// read as broken, so the guidance has to escalate.
    func testGuidanceEscalatesRatherThanRepeating() {
        let hints = [0, 5, 15, 25, 60].map {
            SearchCoaching.hint(elapsed: .seconds($0), attempts: 1)
        }
        XCTAssertEqual(Set(hints).count, hints.count, "each stage must say something new")
        XCTAssertTrue(hints.allSatisfy { !$0.isEmpty })
    }

    func testFirstMomentsAskOnlyForPatience() {
        // Both before the first attempt and during it — the camera opening and
        // the first query starting are the same instant to the user.
        XCTAssertTrue(
            SearchCoaching.hint(elapsed: .seconds(1), attempts: 0).contains("Hold steady")
        )
        XCTAssertTrue(
            SearchCoaching.hint(elapsed: .seconds(1), attempts: 1).contains("Hold steady")
        )
    }

    func testPatienceGivesWayToGuidanceOnceAttemptsHaveFailed() {
        XCTAssertFalse(
            SearchCoaching.hint(elapsed: .seconds(1), attempts: 3).contains("Hold steady")
        )
    }

    func testEarlyGuidanceNamesTheMostCommonMistake() {
        XCTAssertTrue(
            SearchCoaching.hint(elapsed: .seconds(6), attempts: 1).contains("not the floor")
        )
    }
}
