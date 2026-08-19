/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import simd

// MARK: - VPS Map Models

/// VPS Map containing mesh information
internal struct VpsMap: Codable {
    let id: String
    let accountId: String?
    let mapName: String?
    let mapCode: String?
    let status: String?
    let mapMesh: MapMesh?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case accountId
        case mapName
        case mapCode
        case status
        case mapMesh
        case thumbnail
    }
}

internal struct MapMesh: Codable {
    let id: String?
    let rawMesh: RawMesh?
    let texturedMesh: TexturedMesh?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rawMesh
        case texturedMesh
    }
}

internal struct RawMesh: Codable {
    let type: String?
    let meshLink: String?
}

internal struct TexturedMesh: Codable {
    let type: String?
    let meshLink: String?
}

// MARK: - File Data

internal struct FileData: Codable {
    let url: String
}

// MARK: - MapSet Models

internal struct MapSetResult: Codable {
    let mapSet: MapSet
}

internal struct MapSet: Codable {
    let id: String
    let name: String?
    let accountId: String?
    let mapSetCode: String?
    let status: String?
    let mapSetData: [MapSetData]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case accountId
        case mapSetCode
        case status
        case mapSetData
    }
}

internal struct MapSetData: Codable {
    let id: String?
    let order: Int?
    let relativePose: RelativePose?
    let baseRelativePose: RelativePose?
    let map: VpsMap?
    let baseMap: BaseMap?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case order
        case relativePose
        case baseRelativePose
        case map
        case baseMap
    }
}

/// Authoritative map entry used when a map in a mapset has multiple scanned
/// versions. When present (with a non-empty id) `baseMap` + `baseRelativePose`
/// supersede `map` + `relativePose`. Mirrors Unity's `BaseMap`.
/// `id` is optional because the API can return `baseMap` as an empty object.
internal struct BaseMap: Codable {
    let id: String?
    let accountId: String?
    let mapName: String?
    let mapCode: String?
    let status: String?
    let mapMesh: MapMesh?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case accountId
        case mapName
        case mapCode
        case status
        case mapMesh
        case thumbnail
    }

    /// True when this baseMap is a real, populated entry (not an empty `{}`).
    var isValid: Bool {
        if let id = id, !id.isEmpty { return true }
        return false
    }

    func toVpsMap() -> VpsMap {
        VpsMap(
            id: id ?? "",
            accountId: accountId,
            mapName: mapName,
            mapCode: mapCode,
            status: status,
            mapMesh: mapMesh,
            thumbnail: thumbnail
        )
    }
}

internal struct RelativePose: Codable {
    let position: MeshPosition?
    let rotation: MeshRotation?
}

internal struct MeshPosition: Codable {
    let x: Float
    let y: Float
    let z: Float

    init(x: Float = 0, y: Float = 0, z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    func toSIMD3() -> SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

internal struct MeshRotation: Codable {
    let qx: Float
    let qy: Float
    let qz: Float
    let qw: Float

    init(qx: Float = 0, qy: Float = 0, qz: Float = 0, qw: Float = 1) {
        self.qx = qx
        self.qy = qy
        self.qz = qz
        self.qw = qw
    }

    func toQuaternion() -> simd_quatf {
        return simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
    }
}

// MARK: - Mesh Result for Rendering

internal struct MeshResult {
    let mapId: String
    let meshFilePath: URL
    let meshData: Data
    let localPosition: SIMD3<Float>
    let localRotation: simd_quatf
    let visualizationOption: MeshVisualizationOption

    init(
        mapId: String,
        meshFilePath: URL,
        meshData: Data,
        localPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        localRotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        visualizationOption: MeshVisualizationOption = .enableVisualization
    ) {
        self.mapId = mapId
        self.meshFilePath = meshFilePath
        self.meshData = meshData
        self.localPosition = localPosition
        self.localRotation = localRotation
        self.visualizationOption = visualizationOption
    }
}

internal struct MeshPose {
    let position: SIMD3<Float>
    let rotation: simd_quatf

    init(position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
         rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) {
        self.position = position
        self.rotation = rotation
    }

    static let identity = MeshPose()
}

internal enum MeshVisualizationOption {
    case enableVisualization
    case enableOcclusion
    case noMesh
}

// MARK: - Object Tracking Models

/// Object model set containing mesh information
internal struct ModelSet: Codable {
    let id: String
    let objectName: String?
    let objectCode: String
    let objectMesh: ObjectMesh?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case objectName
        case objectCode
        case objectMesh
    }
}

internal struct ObjectMesh: Codable {
    let meshLink: String?
}

/// Result for rendering an object tracking mesh
internal struct ObjectMeshResult {
    let objectCode: String
    let meshData: Data
    let meshFilePath: URL
}
