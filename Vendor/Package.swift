// swift-tools-version: 5.9
import PackageDescription

/// Wraps MultiSetSDK.xcframework as a binary target.
///
/// A package rather than a bare framework reference in the project, because
/// SwiftPM binary targets get slice selection, embedding, and code signing
/// handled for us, and because the dependency then shows up explicitly in each
/// target's dependency list.
///
/// The App Clip does not depend on this package, and must not: MultiSetConfig
/// requires a clientId and clientSecret, so a Clip that linked the SDK would
/// have to carry a credential for anonymous strangers to read.
let package = Package(
    name: "MultiSetSDKBinary",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MultiSetSDKBinary", targets: ["MultiSetSDK"])
    ],
    targets: [
        .binaryTarget(name: "MultiSetSDK", path: "MultiSetSDK.xcframework")
    ]
)
