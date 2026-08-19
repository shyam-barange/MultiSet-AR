// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiSetUI",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MultiSetUI", targets: ["MultiSetUI"])
    ],
    targets: [
        .target(
            name: "MultiSetUI",
            // The state illustrations live here rather than in the app target
            // because both the app and the Clip render them, and assets in a
            // target are invisible to views defined in a package.
            resources: [.process("Resources/StateArt.xcassets")],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(name: "MultiSetUITests", dependencies: ["MultiSetUI"])
    ]
)
