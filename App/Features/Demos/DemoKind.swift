import MultiSetARCore
import MultiSetKit
import MultiSetUI
import SwiftUI

/// The offline demos.
///
/// These are a shipping requirement, not test hooks: VPS localization needs
/// physical presence at a scanned site, and an App Store reviewer cannot travel
/// to one. They are also genuinely useful at a conference booth.
enum DemoKind: String, CaseIterable, Identifiable {
    case objectTracking
    case syntheticNavigation
    case simulatedLocalization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .objectTracking: "Track a printed target"
        case .syntheticNavigation: "Follow a demo route"
        case .simulatedLocalization: "Replay a recorded walk"
        }
    }

    var subtitle: String {
        switch self {
        case .objectTracking:
            "Works anywhere, immediately. Print the target or show it on a screen."
        case .syntheticNavigation:
            "Real pathfinding and real path rendering on a demo map scaled to this room."
        case .simulatedLocalization:
            "Runs a recorded frame sequence through the real localization pipeline."
        }
    }

    var symbolName: String {
        switch self {
        case .objectTracking: "viewfinder.rectangular"
        case .syntheticNavigation: "point.topleft.down.curvedto.point.bottomright.up"
        case .simulatedLocalization: "play.rectangle"
        }
    }

    var deepLinkKind: DeepLinkDestination.DemoKind {
        switch self {
        case .objectTracking: .objectTracking
        case .syntheticNavigation: .syntheticNavigation
        case .simulatedLocalization: .simulatedLocalization
        }
    }
}

/// A small nav graph scaled to a room, so the demo exercises the production A*
/// and ribbon rendering rather than a parallel mock of them.
enum DemoContent {
    static let roomScaleGraph = NavGraph(
        nodes: [
            .init(id: "d1", position: Position(x: 0, y: 0, z: 0)),
            .init(id: "d2", position: Position(x: 1.6, y: 0, z: -0.2)),
            .init(id: "d3", position: Position(x: 2.1, y: 0, z: -1.9)),
            .init(id: "d4", position: Position(x: 0.6, y: 0, z: -2.6), poiID: "demo_destination")
        ],
        edges: [
            .init(from: "d1", to: "d2"),
            .init(from: "d2", to: "d3"),
            .init(from: "d3", to: "d4")
        ]
    )

    static let pointsOfInterest = [
        PointOfInterest(id: "demo_start", title: "Start", position: Position(x: 0, y: 0, z: 0)),
        PointOfInterest(id: "demo_destination", title: "Demo destination", position: Position(x: 0.6, y: 0, z: -2.6))
    ]
}
