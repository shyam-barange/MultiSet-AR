/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import simd

/// Result of a successful localization request
/// Contains the localized pose and associated metadata
public struct LocalizationResult: Sendable {
    /// The map code where localization was successful
    public let mapCode: String

    /// All map codes returned from the localization (may include multiple for MapSets)
    public let mapCodes: [String]

    /// The 3D position in world coordinates
    public let position: SIMD3<Float>

    /// The rotation quaternion in world coordinates
    public let rotation: simd_quatf

    /// Confidence score of the localization (0.0 - 1.0)
    public let confidence: Float?

    /// Geographic coordinates if requested in config
    public let geoCoordinates: GeoCoordinates?

    /// The full geographic pose if requested in config — position plus the orientation
    /// quaternion and frame spec that `geoCoordinates` omits.
    public let geoPose: GeoPose?

    /// The raw estimated camera pose the server returned, in the map frame.
    ///
    /// `position` / `rotation` above are the *computed* pose — the transform between the
    /// AR session frame and the map frame. These two are the untransformed server values,
    /// exposed for diagnostics and for recording a fix faithfully.
    public let estimatedPosition: SIMD3<Float>?

    /// The raw estimated camera rotation the server returned, in the map frame.
    public let estimatedRotation: simd_quatf?

    /// The AR camera position that produced this fix, in the AR session frame.
    public let queryCameraPosition: SIMD3<Float>?

    /// The AR camera rotation that produced this fix, in the AR session frame.
    public let queryCameraRotation: simd_quatf?

    /// When this result was produced.
    public let timestamp: Date

    /// The localization mode used
    public let mode: LocalizationMode

    public init(
        mapCode: String,
        mapCodes: [String],
        position: SIMD3<Float>,
        rotation: simd_quatf,
        confidence: Float? = nil,
        geoCoordinates: GeoCoordinates? = nil,
        geoPose: GeoPose? = nil,
        estimatedPosition: SIMD3<Float>? = nil,
        estimatedRotation: simd_quatf? = nil,
        queryCameraPosition: SIMD3<Float>? = nil,
        queryCameraRotation: simd_quatf? = nil,
        timestamp: Date = Date(),
        mode: LocalizationMode
    ) {
        self.mapCode = mapCode
        self.mapCodes = mapCodes
        self.position = position
        self.rotation = rotation
        self.confidence = confidence
        self.geoCoordinates = geoCoordinates
        self.geoPose = geoPose
        self.estimatedPosition = estimatedPosition
        self.estimatedRotation = estimatedRotation
        self.queryCameraPosition = queryCameraPosition
        self.queryCameraRotation = queryCameraRotation
        self.timestamp = timestamp
        self.mode = mode
    }
}
