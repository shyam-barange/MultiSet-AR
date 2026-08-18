import Foundation
import simd

public struct Position: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var simd: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }

    public init(_ vector: SIMD3<Float>) {
        self.init(x: Double(vector.x), y: Double(vector.y), z: Double(vector.z))
    }
}

/// Rotation quaternion. The API spells the keys two different ways depending on
/// the endpoint — `x/y/z/w` in localization responses, `qx/qy/qz/qw` in MapSet
/// relative poses — so both spellings decode into this one type.
public struct Rotation: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(_ quaternion: simd_quatf) {
        self.init(
            x: Double(quaternion.imag.x),
            y: Double(quaternion.imag.y),
            z: Double(quaternion.imag.z),
            w: Double(quaternion.real)
        )
    }

    public var simd: simd_quatf {
        simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w))
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, z, w, qx, qy, qz, qw
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let x = try container.decodeIfPresent(Double.self, forKey: .x) {
            self.x = x
            self.y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
            self.z = try container.decodeIfPresent(Double.self, forKey: .z) ?? 0
            self.w = try container.decodeIfPresent(Double.self, forKey: .w) ?? 1
        } else {
            self.x = try container.decodeIfPresent(Double.self, forKey: .qx) ?? 0
            self.y = try container.decodeIfPresent(Double.self, forKey: .qy) ?? 0
            self.z = try container.decodeIfPresent(Double.self, forKey: .qz) ?? 0
            self.w = try container.decodeIfPresent(Double.self, forKey: .qw) ?? 1
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
        try container.encode(w, forKey: .w)
    }
}

public struct Scale: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double = 1, y: Double = 1, z: Double = 1) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var simd: SIMD3<Float> { SIMD3(Float(x), Float(y), Float(z)) }
}

public struct Pose: Codable, Sendable, Hashable {
    public var position: Position
    public var rotation: Rotation

    public init(position: Position, rotation: Rotation) {
        self.position = position
        self.rotation = rotation
    }
}

public struct CameraIntrinsics: Codable, Sendable, Hashable {
    public var fx: Double
    public var fy: Double
    public var px: Double
    public var py: Double

    public init(fx: Double, fy: Double, px: Double, py: Double) {
        self.fx = fx
        self.fy = fy
        self.px = px
        self.py = py
    }
}

public struct Resolution: Codable, Sendable, Hashable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct GeoCoordinates: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double

    public init(latitude: Double, longitude: Double, altitude: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    public var isValid: Bool {
        latitude != 0 || longitude != 0
    }

    /// The `geoHint` form the query endpoints expect: `"lat,lon,alt"`.
    public var geoHintString: String {
        "\(latitude),\(longitude),\(altitude)"
    }
}

/// GeoJSON point as returned in `VPSMap.location`, where `coordinates` is
/// `[longitude, latitude]` — the reverse of the `GeoCoordinates` field order.
public struct GeoJSONPoint: Codable, Sendable, Hashable {
    public var type: String
    public var coordinates: [Double]

    public var geoCoordinates: GeoCoordinates? {
        guard coordinates.count >= 2 else { return nil }
        return GeoCoordinates(
            latitude: coordinates[1],
            longitude: coordinates[0],
            altitude: coordinates.count > 2 ? coordinates[2] : 0
        )
    }
}
