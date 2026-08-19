/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import simd

// MARK: - Single Frame Localization Response

/// Internal response model for single-frame localization API
internal struct SingleFrameLocalizationResponse: Codable {
    let poseFound: Bool
    let position: Position?
    let rotation: Rotation?
    let mapIds: [String]?
    let mapCodes: [String]?
    let confidence: Float?
    let retrievalScores: [Float]?
    let numMatches: [Int]?
    let message: String?

    let GeoPose: GeoPoseResponse?

    var safeMapCodes: [String] {
        return mapCodes ?? []
    }

    struct Position: Codable {
        let x: Float
        let y: Float
        let z: Float

        func toSIMD3() -> SIMD3<Float> {
            return SIMD3<Float>(x, y, z)
        }
    }

    struct Rotation: Codable {
        let x: Float
        let y: Float
        let z: Float
        let w: Float

        func toQuaternion() -> simd_quatf {
            return simd_quatf(ix: x, iy: y, iz: z, r: w)
        }
    }
}

// MARK: - Multi-Frame Localization Response

internal struct MultiFrameLocalizationResponse: Codable {
    let poseFound: Bool
    let estimatedPose: EstimatedPose?
    let trackingPose: TrackingPose?
    let confidence: Float?
    let mapIds: [String]?
    let mapCodes: [String]?
    let message: String?

    let GeoPose: GeoPoseResponse?

    var safeMapCodes: [String] {
        return mapCodes ?? []
    }

    struct EstimatedPose: Codable {
        let position: Position
        let rotation: Rotation

        struct Position: Codable {
            let x: Float
            let y: Float
            let z: Float

            func toSIMD3() -> SIMD3<Float> {
                return SIMD3<Float>(x, y, z)
            }
        }

        struct Rotation: Codable {
            let x: Float
            let y: Float
            let z: Float
            let w: Float

            func toQuaternion() -> simd_quatf {
                return simd_quatf(ix: x, iy: y, iz: z, r: w)
            }
        }
    }

    struct TrackingPose: Codable {
        let position: Position
        let rotation: Rotation

        struct Position: Codable {
            let x: Float
            let y: Float
            let z: Float

            func toSIMD3() -> SIMD3<Float> {
                return SIMD3<Float>(x, y, z)
            }
        }

        struct Rotation: Codable {
            let x: Float
            let y: Float
            let z: Float
            let w: Float

            func toQuaternion() -> simd_quatf {
                return simd_quatf(ix: x, iy: y, iz: z, r: w)
            }
        }
    }
}

/// Geographic pose (WGS-84) returned under the "GeoPose" key when convertToGeoCoordinates=true.
/// The server may omit this object entirely, so every field is optional.
internal struct GeoPoseResponse: Codable {
    let frame_spec: FrameSpec?
    let pose: Pose?

    struct FrameSpec: Codable {
        let model: String?
        let frame: String?
    }

    struct Pose: Codable {
        let position: GeoPosition?
        let quaternion: Quaternion?

        struct GeoPosition: Codable {
            let lat: Double?
            let lon: Double?
            let h: Double?
        }

        struct Quaternion: Codable {
            let x: Float?
            let y: Float?
            let z: Float?
            let w: Float?
        }
    }

    /// Map the geographic position into the SDK's public GeoCoordinates (lat/lon/altitude).
    func toGeoCoordinates() -> GeoCoordinates? {
        guard let position = pose?.position, let lat = position.lat, let lon = position.lon else { return nil }
        return GeoCoordinates(latitude: lat, longitude: lon, altitude: position.h ?? 0)
    }

    /// Map the whole block into the SDK's public GeoPose, preserving the orientation
    /// quaternion and frame spec that `toGeoCoordinates()` discards. Returns nil when
    /// the server sent nothing usable.
    func toGeoPose() -> GeoPose? {
        let position: GeoPose.Position? = {
            guard let p = pose?.position, let lat = p.lat, let lon = p.lon else { return nil }
            return GeoPose.Position(latitude: lat, longitude: lon, altitude: p.h ?? 0)
        }()

        let quaternion: GeoPose.Quaternion? = {
            guard let q = pose?.quaternion,
                  let x = q.x, let y = q.y, let z = q.z, let w = q.w else { return nil }
            return GeoPose.Quaternion(x: x, y: y, z: z, w: w)
        }()

        guard position != nil || quaternion != nil || frame_spec != nil else { return nil }

        return GeoPose(
            frameModel: frame_spec?.model,
            frameName: frame_spec?.frame,
            position: position,
            quaternion: quaternion
        )
    }
}

// MARK: - Object Tracking Response

internal struct ObjectTrackingResponse: Codable {
    let poseFound: Bool
    let position: OTPosition?
    let rotation: OTRotation?
    let confidence: Double?
    let objectCodes: [String]?

    struct OTPosition: Codable {
        let x: Float
        let y: Float
        let z: Float

        func toSIMD3() -> SIMD3<Float> {
            return SIMD3<Float>(x, y, z)
        }
    }

    struct OTRotation: Codable {
        let x: Float
        let y: Float
        let z: Float
        let w: Float

        func toQuaternion() -> simd_quatf {
            return simd_quatf(ix: x, iy: y, iz: z, r: w)
        }
    }
}

// MARK: - Localization Failure Response

internal struct LocalizationFailureResponse: Codable {
    let poseFound: Bool
    let message: String?
}

// MARK: - Image Data for Multi-Frame Request

internal struct ImageData {
    let imageBytes: Data
    let metadata: ImageMetadata
}

internal struct ImageMetadata: Codable {
    let x: Float
    let y: Float
    let z: Float
    let qx: Float
    let qy: Float
    let qz: Float
    let qw: Float

    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

// MARK: - Camera Intrinsics

internal struct CameraIntrinsics {
    let fx: Float
    let fy: Float
    let px: Float
    let py: Float
    let width: Int
    let height: Int
}

// MARK: - Captured Frame

internal struct CapturedFrame {
    let imageData: Data
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let intrinsics: CameraIntrinsics
}

// MARK: - Internal Localization Config

/// Internal configuration struct used by LocalizationManager
internal struct LocalizationConfig {
    var localizationMode: LocalizationMode = .multiFrame
    var autoLocalize: Bool = true
    var backgroundLocalization: Bool = true
    var bgLocalizationDurationSeconds: Float = 30.0
    var relocalization: Bool = true
    var numberOfFrames: Int = 4
    var frameCaptureIntervalMs: Int = 500
    var confidenceCheck: Bool = false
    var confidenceThreshold: Float = 0.3
    var poseConsistencyCheck: Bool = false
    var poseConsistencyThreshold: Float = 10.0
    var firstLocalizationUntilSuccess: Bool = true
    var showAlerts: Bool = true
    var meshVisualization: Bool = true
    var passGeoPose: Bool = false
    var geoCoordinatesInResponse: Bool = false
    var hintRadius: Int = 25
    var use2DFiltering: Bool = false
    var hintMapCodes: [String] = []
    var hintPosition: String = ""
    var hintFloorHeight: String = ""
    var imageQuality: Int = 90

    func validated() -> LocalizationConfig {
        var config = self
        config.bgLocalizationDurationSeconds = min(max(bgLocalizationDurationSeconds, 15), 180)
        config.numberOfFrames = min(max(numberOfFrames, 4), 6)
        config.frameCaptureIntervalMs = min(max(frameCaptureIntervalMs, 300), 800)
        config.confidenceThreshold = min(max(confidenceThreshold, 0.2), 0.8)
        config.poseConsistencyThreshold = min(max(poseConsistencyThreshold, 3), 30)
        config.hintRadius = min(max(hintRadius, 1), 100)
        config.imageQuality = min(max(imageQuality, 50), 100)
        return config
    }

    var frameCaptureIntervalSeconds: TimeInterval {
        return TimeInterval(frameCaptureIntervalMs) / 1000.0
    }

    var bgLocalizationDuration: TimeInterval {
        return TimeInterval(bgLocalizationDurationSeconds)
    }
}

// MARK: - Internal Localization Result

/// Internal result used within the SDK
internal struct InternalLocalizationResult {
    let mapCodes: [String]
    let resultPosition: SIMD3<Float>
    let resultRotation: simd_quatf
    let confidence: Float
    let mode: LocalizationMode
    let geoCoordinates: GeoCoordinates?

    init(response: MultiFrameLocalizationResponse, resultPosition: SIMD3<Float>, resultRotation: simd_quatf) {
        self.mapCodes = response.safeMapCodes
        self.resultPosition = resultPosition
        self.resultRotation = resultRotation
        self.confidence = response.confidence ?? 1.0
        self.mode = .multiFrame
        self.geoCoordinates = response.GeoPose?.toGeoCoordinates()
    }

    init(response: SingleFrameLocalizationResponse, resultPosition: SIMD3<Float>, resultRotation: simd_quatf) {
        self.mapCodes = response.safeMapCodes
        self.resultPosition = resultPosition
        self.resultRotation = resultRotation
        self.confidence = response.confidence ?? 1.0
        self.mode = .singleFrame
        self.geoCoordinates = response.GeoPose?.toGeoCoordinates()
    }

    /// Convert to public LocalizationResult
    func toPublicResult() -> LocalizationResult {
        return LocalizationResult(
            mapCode: mapCodes.first ?? "",
            mapCodes: mapCodes,
            position: resultPosition,
            rotation: resultRotation,
            confidence: confidence,
            geoCoordinates: geoCoordinates,
            mode: mode
        )
    }
}
