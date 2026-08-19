// swift-tools-version: 5.9
import PackageDescription

/// The MultiSet VPS engine, ported from the internal SDK source at
/// `iOS-SDK-Internal/MultiSetSDK` so it can authenticate with the signed-in user's
/// own access token instead of an M2M clientId/clientSecret pair.
///
/// Everything below the SDK's `AuthManager` only ever needed a bearer token — the
/// token appears in exactly eight places, as `Bearer <token>`. Replacing that one
/// seam is what makes the whole flow, including the mesh overlay, work for a
/// logged-in user and for the App Clip's anonymous experience token alike.
let package = Package(
    name: "MultiSetVPS",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MultiSetVPS", targets: ["MultiSetVPS"])
    ],
    targets: [
        // The two .metal files compile into this target's default library, which
        // MeshRenderer and OutlineMeshRenderer load from Bundle.module.
        .target(name: "MultiSetVPS"),
        .testTarget(name: "MultiSetVPSTests", dependencies: ["MultiSetVPS"])
    ]
)
