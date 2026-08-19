/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// GPS/Geographic Coordinates data structure
/// Used for geoHint in requests and geo coordinates in responses
public struct GeoCoordinates: Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double

    public init(latitude: Double = 0.0, longitude: Double = 0.0, altitude: Double = 0.0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    /// Check if coordinates are valid (not all zeros)
    public func isValid() -> Bool {
        return latitude != 0.0 || longitude != 0.0 || altitude != 0.0
    }

    /// Format as geoHint string for API: "latitude,longitude,altitude"
    public func toGeoHintString() -> String {
        return "\(latitude),\(longitude),\(altitude)"
    }
}
