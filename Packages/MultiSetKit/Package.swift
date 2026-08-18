// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiSetKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MultiSetKit", targets: ["MultiSetKit"])
    ],
    targets: [
        .target(
            name: "MultiSetKit",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(name: "MultiSetKitTests", dependencies: ["MultiSetKit"])
    ]
)
