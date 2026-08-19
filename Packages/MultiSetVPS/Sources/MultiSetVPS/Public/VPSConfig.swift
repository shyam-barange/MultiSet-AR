/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Configuration for the MultiSet SDK
/// Contains credentials, map settings, and localization parameters
public struct VPSConfig: Sendable {

    // MARK: - Required Credentials

    /// Client ID for API authentication (required)
    /// Client Secret for API authentication (required)
    // MARK: - API Environment

    /// The production MultiSet API, and the default value of `baseURL`
    public static let productionBaseURL = "https://api.multiset.ai/v1"

    /// Base URL of the MultiSet API, without a trailing slash.
    ///
    /// Defaults to the production API (`https://api.multiset.ai/v1`). Override it to
    /// point the SDK at a staging, on-premise or proxied deployment; every endpoint the
    /// SDK calls is built from this value.
    ///
    /// Applied when `MultiSet.initialize(config:callback:)` runs, before authentication
    /// — an auth token is only valid against the host that issued it, so changing this
    /// afterwards needs `release()` followed by a fresh `initialize(...)`. An empty or
    /// malformed value is refused and the previous host is kept.
    public var baseURL: String

    // MARK: - Map Configuration

    /// Map code for single map localization
    public var mapCode: String

    /// Map set code for multi-map localization
    public var mapSetCode: String

    // MARK: - Localization Mode

    /// Localization mode: single-frame or multi-frame
    public var localizationMode: LocalizationMode

    // MARK: - Auto Localization

    /// Automatically start localization after AR setup
    public var autoLocalize: Bool

    /// Enable background localization to continuously re-localize at intervals
    public var backgroundLocalization: Bool

    /// Duration in seconds between background localization requests (15-180 seconds)
    public var bgLocalizationDurationSeconds: Float

    /// Enable re-localization when AR tracking is lost
    public var relocalization: Bool

    // MARK: - Frame Capture

    /// Number of frames to capture for localization (4-6)
    /// Only used in multi-frame mode
    public var numberOfFrames: Int

    /// Interval in milliseconds between frame captures (300-800ms)
    /// Only used in multi-frame mode
    public var frameCaptureIntervalMs: Int

    // MARK: - Confidence Settings

    /// Enable confidence threshold check after localization
    public var confidenceCheck: Bool

    /// Minimum confidence value for localization to be considered successful (0.2-0.8)
    public var confidenceThreshold: Float

    // MARK: - Pose Consistency Settings

    /// Reject localization results that contradict the device's own ARKit trajectory.
    /// Every fix in a session measures the same map-to-session transform, so a result
    /// that moves it further than ARKit could have drifted is not physically possible.
    /// Catches high-confidence false matches that a confidence threshold cannot.
    public var poseConsistencyCheck: Bool

    /// Tolerance in meters for the pose consistency check (3-30, default 10)
    public var poseConsistencyThreshold: Float

    // MARK: - First Localization

    /// If enabled, the first localization request will retry silently until it succeeds
    /// without showing failure messages or triggering failure callbacks
    public var firstLocalizationUntilSuccess: Bool

    // MARK: - UI Settings

    /// Show toast alerts on localization success/failure
    public var showAlerts: Bool

    // MARK: - Mesh Settings

    /// Enable mesh visualization after successful localization
    /// If false, mesh download and rendering will be skipped
    public var meshVisualization: Bool

    // MARK: - GPS Settings

    /// Enable passing GPS coordinates (geoHint) in localization request
    /// If enabled, will request location permission and include lat/lng/alt in API call
    public var passGeoPose: Bool

    /// Enable receiving geo coordinates in localization response
    /// If true, adds convertToGeoCoordinates=true to the API request
    public var geoCoordinatesInResponse: Bool

    /// Search radius in meters for spatial filtering (1-100, default 25)
    /// Only applies when a geoHint or hintPosition is provided. Sent when greater than 0.
    public var hintRadius: Int

    /// When true, skips altitude (Y-axis) in geoHint spatial filtering, using only
    /// horizontal distance (X and Z). Only applies when a geoHint is provided.
    public var use2DFiltering: Bool

    // MARK: - Localization Hints

    /// Hint map codes to narrow candidate maps during MapSet localization.
    /// Only sent when localizing a MapSet. Each code is sent as a separate `hintMapCodes` field.
    public var hintMapCodes: [String]

    /// Positional hint to seed localization, in "X,Y,Z" format. Sent when non-empty.
    public var hintPosition: String

    /// Floor/ceiling height hint, in "floor,ceiling" format (e.g. "0,5"). Sent when non-empty.
    public var hintFloorHeight: String

    // MARK: - Object Tracking Settings

    /// Object codes for object tracking mode (max 10)
    public var objectCodes: [String]

    /// Enable auto object tracking after AR setup
    public var autoObjectTracking: Bool

    /// Enable background re-tracking at intervals
    public var backgroundObjectTracking: Bool

    /// Duration in seconds between background object tracking requests (5-30s)
    public var bgObjectTrackingDurationSeconds: Float

    /// Enable re-tracking when AR tracking is lost
    public var restartObjectTracking: Bool

    /// Delay before capturing frame for object tracking (seconds)
    public var objectTrackingCaptureDelay: Float

    /// Retry first object tracking until success
    public var firstObjectTrackingUntilSuccess: Bool

    // MARK: - Image Settings

    /// JPEG compression quality (50-100)
    public var imageQuality: Int

    // MARK: - Initialization

    /// Initialize with required credentials
    /// - Parameters:
    public init(
        mapCode: String = "",
        mapSetCode: String = "",
        localizationMode: LocalizationMode = .multiFrame,
        autoLocalize: Bool = true,
        backgroundLocalization: Bool = true,
        bgLocalizationDurationSeconds: Float = 30.0,
        relocalization: Bool = true,
        numberOfFrames: Int = 4,
        frameCaptureIntervalMs: Int = 500,
        confidenceCheck: Bool = false,
        confidenceThreshold: Float = 0.3,
        poseConsistencyCheck: Bool = false,
        poseConsistencyThreshold: Float = 10.0,
        firstLocalizationUntilSuccess: Bool = true,
        showAlerts: Bool = true,
        meshVisualization: Bool = true,
        passGeoPose: Bool = false,
        geoCoordinatesInResponse: Bool = false,
        hintRadius: Int = 25,
        use2DFiltering: Bool = false,
        hintMapCodes: [String] = [],
        hintPosition: String = "",
        hintFloorHeight: String = "",
        imageQuality: Int = 90,
        objectCodes: [String] = [],
        autoObjectTracking: Bool = true,
        backgroundObjectTracking: Bool = true,
        bgObjectTrackingDurationSeconds: Float = 15.0,
        restartObjectTracking: Bool = true,
        objectTrackingCaptureDelay: Float = 1.0,
        firstObjectTrackingUntilSuccess: Bool = true,
        baseURL: String = VPSConfig.productionBaseURL
    ) {
        self.baseURL = baseURL
        self.mapCode = mapCode
        self.mapSetCode = mapSetCode
        self.localizationMode = localizationMode
        self.autoLocalize = autoLocalize
        self.backgroundLocalization = backgroundLocalization
        self.bgLocalizationDurationSeconds = bgLocalizationDurationSeconds
        self.relocalization = relocalization
        self.numberOfFrames = numberOfFrames
        self.frameCaptureIntervalMs = frameCaptureIntervalMs
        self.confidenceCheck = confidenceCheck
        self.confidenceThreshold = confidenceThreshold
        self.poseConsistencyCheck = poseConsistencyCheck
        self.poseConsistencyThreshold = poseConsistencyThreshold
        self.firstLocalizationUntilSuccess = firstLocalizationUntilSuccess
        self.showAlerts = showAlerts
        self.meshVisualization = meshVisualization
        self.passGeoPose = passGeoPose
        self.geoCoordinatesInResponse = geoCoordinatesInResponse
        self.hintRadius = hintRadius
        self.use2DFiltering = use2DFiltering
        self.hintMapCodes = hintMapCodes
        self.hintPosition = hintPosition
        self.hintFloorHeight = hintFloorHeight
        self.imageQuality = imageQuality
        self.objectCodes = objectCodes
        self.autoObjectTracking = autoObjectTracking
        self.backgroundObjectTracking = backgroundObjectTracking
        self.bgObjectTrackingDurationSeconds = bgObjectTrackingDurationSeconds
        self.restartObjectTracking = restartObjectTracking
        self.objectTrackingCaptureDelay = objectTrackingCaptureDelay
        self.firstObjectTrackingUntilSuccess = firstObjectTrackingUntilSuccess
    }

    // MARK: - Factory Methods

    /// Default configuration with multi-frame localization
    public static func `default`(mapCode: String) -> VPSConfig {
        return VPSConfig(mapCode: mapCode)
    }

    /// Configuration for single-frame localization
    public static func singleFrame(mapCode: String) -> VPSConfig {
        var config = VPSConfig(mapCode: mapCode)
        config.localizationMode = .singleFrame
        config.autoLocalize = false
        config.backgroundLocalization = false
        config.firstLocalizationUntilSuccess = false
        return config
    }

    /// Configuration for multi-frame localization (explicit)
    public static func multiFrame(mapCode: String) -> VPSConfig {
        var config = VPSConfig(mapCode: mapCode)
        config.localizationMode = .multiFrame
        return config
    }

    /// Configuration for continuous localization with aggressive settings
    public static func continuous(mapCode: String) -> VPSConfig {
        var config = VPSConfig(mapCode: mapCode)
        config.autoLocalize = true
        config.backgroundLocalization = true
        config.bgLocalizationDurationSeconds = 15.0
        config.relocalization = true
        config.firstLocalizationUntilSuccess = true
        return config
    }

    // MARK: - Map Type

    /// Returns the active map type based on configuration
    public var activeMapType: MapType {
        if !mapSetCode.isEmpty {
            return .mapSet
        }
        return .map
    }

    /// Returns the active map or mapSet code
    public var activeMapCode: String {
        switch activeMapType {
        case .map:
            return mapCode
        case .mapSet:
            return mapSetCode
        }
    }

    /// Check if credentials are configured
    /// Always true: credentials are the host's business now, supplied as a
    /// `VPSTokenProviding`. Kept so the initialize-time guard reads unchanged.
    public var hasCredentials: Bool { true }

    /// Check if map is configured
    public var hasMapConfiguration: Bool {
        return !mapCode.isEmpty || !mapSetCode.isEmpty
    }

    /// Check if object tracking is configured
    public var hasObjectTrackingConfiguration: Bool {
        return !objectCodes.isEmpty
    }

    // MARK: - Validation

    /// Validate configuration values and return a corrected config
    public func validated() -> VPSConfig {
        var config = self
        config.bgLocalizationDurationSeconds = min(max(bgLocalizationDurationSeconds, 15), 180)
        config.numberOfFrames = min(max(numberOfFrames, 4), 6)
        config.frameCaptureIntervalMs = min(max(frameCaptureIntervalMs, 300), 800)
        config.confidenceThreshold = min(max(confidenceThreshold, 0.2), 0.8)
        config.poseConsistencyThreshold = min(max(poseConsistencyThreshold, 3), 30)
        config.hintRadius = min(max(hintRadius, 1), 100)
        config.imageQuality = min(max(imageQuality, 50), 100)
        config.objectCodes = Array(objectCodes.prefix(10))
        config.bgObjectTrackingDurationSeconds = min(max(bgObjectTrackingDurationSeconds, 5), 30)
        config.objectTrackingCaptureDelay = min(max(objectTrackingCaptureDelay, 0.5), 3.0)
        return config
    }

    /// Frame capture interval in seconds
    public var frameCaptureIntervalSeconds: TimeInterval {
        return TimeInterval(frameCaptureIntervalMs) / 1000.0
    }

    /// Background localization duration as TimeInterval
    public var bgLocalizationDuration: TimeInterval {
        return TimeInterval(bgLocalizationDurationSeconds)
    }
}

// MARK: - Map Type

/// Map type enumeration
public enum MapType: Sendable {
    case map
    case mapSet
}
