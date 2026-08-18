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
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(name: "MultiSetUITests", dependencies: ["MultiSetUI"])
    ]
)
