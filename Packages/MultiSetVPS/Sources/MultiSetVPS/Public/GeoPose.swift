/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// The full geographic pose (WGS-84) the server returns under the `GeoPose` key when
/// `geoCoordinatesInResponse` is enabled.
///
/// `GeoCoordinates` carries only the position and is kept for existing integrations.
/// This type additionally exposes the orientation quaternion and the frame
/// specification, which are what a consumer needs to draw a heading or to record a
/// pose faithfully.
///
/// Every field is optional: the server may omit the block or any part of it.
public struct GeoPose: Sendable {

    /// Geographic position in the frame named by `frameName`.
    public struct Position: Sendable {
        public let latitude: Double
        public let longitude: Double
        public let altitude: Double

        public init(latitude: Double, longitude: Double, altitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
        }
    }

    /// Orientation within the frame named by `frameName`.
    public struct Quaternion: Sendable {
        public let x: Float
        public let y: Float
        public let z: Float
        public let w: Float

        public init(x: Float, y: Float, z: Float, w: Float) {
            self.x = x
            self.y = y
            self.z = z
            self.w = w
        }
    }

    /// `frame_spec.model` — the geodetic model, e.g. `"WGS-84"`.
    public let frameModel: String?

    /// `frame_spec.frame` — the local tangent frame, e.g. `"Y-Up-ENU"`. The axis
    /// convention needed to interpret `quaternion` as a compass heading.
    public let frameName: String?

    public let position: Position?
    public let quaternion: Quaternion?

    public init(
        frameModel: String? = nil,
        frameName: String? = nil,
        position: Position? = nil,
        quaternion: Quaternion? = nil
    ) {
        self.frameModel = frameModel
        self.frameName = frameName
        self.position = position
        self.quaternion = quaternion
    }

    /// The position as the simpler `GeoCoordinates` value, when present.
    public var geoCoordinates: GeoCoordinates? {
        guard let position = position else { return nil }
        return GeoCoordinates(
            latitude: position.latitude,
            longitude: position.longitude,
            altitude: position.altitude
        )
    }
}
