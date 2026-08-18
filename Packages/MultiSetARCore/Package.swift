// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiSetARCore",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MultiSetARCore", targets: ["MultiSetARCore"])
    ],
    dependencies: [
        .package(path: "../MultiSetKit")
    ],
    targets: [
        // Deliberately has no dependency on MultiSetSDK. The SDK-backed
        // PoseProvider lives in the App target, which keeps the framework off
        // the App Clip's dependency graph — and therefore keeps every
        // clientSecret out of the Clip binary.
        .target(
            name: "MultiSetARCore",
            dependencies: ["MultiSetKit"],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .testTarget(name: "MultiSetARCoreTests", dependencies: ["MultiSetARCore"])
    ]
)
