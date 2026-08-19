import Combine
import Foundation
import MultiSetKit
import simd

/// One AR session, in one of three modes.
///
/// `ObservableObject` rather than `@Observable` because the deployment target is
/// iOS 16, where the Observation framework is unavailable.
@MainActor
public protocol ARExperience: AnyObject, ObservableObject {
    var state: ARExperienceState { get }
    var diagnostics: ARDiagnostics { get }
    var worldFromMap: simd_float4x4? { get }

    func start() async
    func requestLocalization() async
    func pause()
    func resume()
    func teardown()
}

public struct ExperienceConfiguration: Sendable, Identifiable {
    public var mode: ExperienceMode
    public var target: MapTarget
    public var localizationMode: LocalizationMode
    public var frameCount: Int
    public var frameInterval: Duration
    /// Keeps retrying the first fix until it succeeds — the user has just opened
    /// the camera expecting something to happen, so giving up immediately reads
    /// as a failure of the product.
    public var retryFirstLocalizationUntilSuccess: Bool
    public var backgroundRelocalization: Bool
    public var confidenceThreshold: Double?
    public var geoHint: GeoCoordinates?
    public var objectCodes: [String]
    public var pointsOfInterest: [PointOfInterest]
    public var destinationPOIID: String?
    public var navGraph: NavGraph?

    /// Distinguishes one configured session from another, so a `fullScreenCover`
    /// keyed on it rebuilds when the mode or target changes.
    public var id: String {
        "\(mode.rawValue)-\(target.code)-\(localizationMode.rawValue)"
    }

    public init(
        mode: ExperienceMode,
        target: MapTarget,
        localizationMode: LocalizationMode = .multiFrame,
        frameCount: Int = 4,
        frameInterval: Duration = .milliseconds(500),
        retryFirstLocalizationUntilSuccess: Bool = true,
        backgroundRelocalization: Bool = true,
        confidenceThreshold: Double? = nil,
        geoHint: GeoCoordinates? = nil,
        objectCodes: [String] = [],
        pointsOfInterest: [PointOfInterest] = [],
        destinationPOIID: String? = nil,
        navGraph: NavGraph? = nil
    ) {
        self.mode = mode
        self.target = target
        self.localizationMode = localizationMode
        self.frameCount = frameCount
        self.frameInterval = frameInterval
        self.retryFirstLocalizationUntilSuccess = retryFirstLocalizationUntilSuccess
        self.backgroundRelocalization = backgroundRelocalization
        self.confidenceThreshold = confidenceThreshold
        self.geoHint = geoHint
        self.objectCodes = objectCodes
        self.pointsOfInterest = pointsOfInterest
        self.destinationPOIID = destinationPOIID
        self.navGraph = navGraph
    }

    public init(manifest: ExperienceManifest, modeOverride: ExperienceMode? = nil) {
        self.init(
            mode: modeOverride ?? manifest.mode,
            target: manifest.target,
            objectCodes: manifest.objectCodes,
            pointsOfInterest: manifest.pointsOfInterest,
            destinationPOIID: manifest.destination?.id,
            navGraph: manifest.navGraph
        )
    }
}
