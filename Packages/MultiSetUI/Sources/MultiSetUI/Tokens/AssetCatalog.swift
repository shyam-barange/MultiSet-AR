import SwiftUI

/// Typed names for every shipped image.
///
/// No stringly-typed asset names in view code: a typo becomes a blank rectangle
/// discovered in a demo, whereas a missing case is a compile error and a missing
/// *file* is caught by `AssetCatalogTests`.
///
/// Bundle resolution follows one rule, per the integration prompt's §2.4 Option A:
/// content imagery lives in the **app target** and is referenced only from views
/// in `App/`, while state art lives in **this package** and resolves against
/// `Bundle.module` because both the app and the App Clip render it.
public protocol CatalogImage {
    var assetName: String { get }
    /// Where the asset lives. `nil` means the main bundle.
    static var bundle: Bundle? { get }
}

public extension CatalogImage {
    /// Nil when the asset is absent — callers fall back rather than rendering an
    /// empty rectangle.
    var uiImage: UIImage? {
        if let bundle = Self.bundle {
            return UIImage(named: assetName, in: bundle, with: nil)
        }
        return UIImage(named: assetName)
    }

    var image: Image? {
        uiImage.map { Image(uiImage: $0) }
    }

    var exists: Bool { uiImage != nil }

    /// True when the real image is present, not just an On-Demand Resources stub.
    ///
    /// A tagged asset leaves a placeholder in the main catalog, so `UIImage(named:)`
    /// can succeed before the pack has been fetched. Any of this app's images is at
    /// least 1000 px on its short edge, so a small decode means a stub.
    var isFullyLoaded: Bool {
        guard let image = uiImage, let cgImage = image.cgImage else { return false }
        return min(cgImage.width, cgImage.height) >= 256
    }
}

/// Home-screen feature imagery. App target — see `CatalogImage`.
public enum HomeImage: String, CatalogImage, CaseIterable, Sendable {
    case spatialHero = "home-spatial-hero"
    case scanCode = "home-card-scan-code"
    case enterCode = "home-card-enter-code"
    case objectTracking = "home-card-object-tracking"
    case navigation = "home-card-navigation"
    case localization = "home-card-localization"

    public var assetName: String { rawValue }
    public static var bundle: Bundle? { nil }
}

/// Onboarding photography. App target — see `CatalogImage`.
public enum OnboardingImage: String, CatalogImage, CaseIterable, Sendable {
    case map = "onboarding-01-map"
    case localize = "onboarding-02-localize"
    case guide = "onboarding-03-guide"

    public var assetName: String { rawValue }
    public static var bundle: Bundle? { nil }
}

/// Learn tab capability imagery. App target, and tagged for On-Demand Resources
/// under `LearnImage.onDemandResourceTag`.
public enum LearnImage: String, CatalogImage, CaseIterable, Sendable {
    case vps = "learn-vps"
    case objectTracking = "learn-object-tracking"
    case mapping = "learn-mapping"
    case e57 = "learn-e57"
    case gaussianSplat = "learn-3dgs"
    case panorama = "learn-360"

    public var assetName: String { rawValue }
    public static var bundle: Bundle? { nil }

    /// Matches the `on-demand-resource-tags` in each image set's `Contents.json`.
    public static let onDemandResourceTag = "learn-content"
}

/// Art imported from the MultiSet SDK's own sample app, for the SDK-driven
/// localization and object-tracking screens. App target — see `CatalogImage`.
public enum SDKImage: String, CatalogImage, CaseIterable, Sendable {
    case captureButton = "capture_button"
    case arBackground = "bg_ar"
    case phone = "phone_image"

    public var assetName: String { rawValue }
    public static var bundle: Bundle? { nil }
}

/// The four empty and status illustrations, as template-rendered vectors so they
/// tint with the accent. This package's bundle, because the Clip renders them too.
public enum StateArt: String, CatalogImage, CaseIterable, Sendable {
    case noMaps = "empty-no-maps"
    case noObjects = "empty-no-objects"
    case searching = "state-searching"
    case experienceEnded = "state-experience-ended"

    public var assetName: String { rawValue }
    public static var bundle: Bundle? { .module }
}
