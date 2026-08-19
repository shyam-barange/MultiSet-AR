/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import simd

/// Internal handler for mesh downloading and caching
internal class MeshHandler {

    // MARK: - Properties

    /// Read at request time so a refresh mid-session is picked up.
    private let tokenBox: VPSTokenBox
    private var currentMapSet: MapSet?
    private var currentVpsMap: VpsMap?
    private var isMapSet = false

    var visualizationOption: MeshVisualizationOption = .enableVisualization

    private var meshCacheDir: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let meshDir = cacheDir.appendingPathComponent("mesh_cache")

        if !FileManager.default.fileExists(atPath: meshDir.path) {
            try? FileManager.default.createDirectory(at: meshDir, withIntermediateDirectories: true)
        }

        return meshDir
    }

    // MARK: - Initialization

    init(tokenBox: VPSTokenBox) {
        self.tokenBox = tokenBox
    }

    // MARK: - Public Methods

    func loadMeshForMap(mapId: String) async throws -> MeshResult? {
        isMapSet = false

        guard let vpsMap = try await fetchMapDetails(mapId: mapId) else {
            print("MultiSetVPS >> Failed to fetch map details for mapId: \(mapId)")
            return nil
        }

        currentVpsMap = vpsMap
        return try await loadMesh(vpsMap: vpsMap)
    }

    func loadMeshForMapSet(mapSetCode: String, localizedMapId: String) async throws -> MeshResult? {
        isMapSet = true

        guard let mapSetResult = try await fetchMapSetDetails(mapSetCode: mapSetCode) else {
            print("MultiSetVPS >> Failed to fetch MapSet details for code: \(mapSetCode)")
            return nil
        }

        currentMapSet = mapSetResult.mapSet

        guard let vpsMap = findVpsMapInMapSet(mapSet: mapSetResult.mapSet, mapId: localizedMapId) else {
            print("MultiSetVPS >> VpsMap with ID '\(localizedMapId)' not found in MapSet")
            return nil
        }

        currentVpsMap = vpsMap
        return try await loadMesh(vpsMap: vpsMap)
    }

    func clearCache() {
        let files = try? FileManager.default.contentsOfDirectory(at: meshCacheDir, includingPropertiesForKeys: nil)
        files?.forEach { try? FileManager.default.removeItem(at: $0) }
        print("MultiSetVPS >> Mesh cache cleared")
    }

    // MARK: - Private Methods

    /// Resolves the VpsMap to load for the localized map code. When an entry
    /// carries a populated `baseMap` (map with multiple scanned versions), the
    /// baseMap is authoritative and is used instead of `map` — matching the
    /// Unity `getVpsMapFromMapSet` logic. Falls back to `map` otherwise.
    private func findVpsMapInMapSet(mapSet: MapSet, mapId: String) -> VpsMap? {
        guard let dataList = mapSet.mapSetData else { return nil }

        for data in dataList {
            if let baseMap = data.baseMap, baseMap.isValid {
                if baseMap.id == mapId || baseMap.mapCode == mapId {
                    return baseMap.toVpsMap()
                }
                continue
            }

            if let map = data.map, map.id == mapId || map.mapCode == mapId {
                return map
            }
        }

        return nil
    }

    private func loadMesh(vpsMap: VpsMap) async throws -> MeshResult? {
        // print("MultiSetVPS >> loadMesh called for map: \(vpsMap.id)")

        guard visualizationOption != .noMesh else {
            print("MultiSetVPS >> Mesh loading disabled (noMesh option)")
            return nil
        }

        guard let meshLink = vpsMap.mapMesh?.rawMesh?.meshLink, !meshLink.isEmpty else {
            print("MultiSetVPS >> No mesh link available for map \(vpsMap.id)")
            return nil
        }

        let cacheFile = meshCacheDir.appendingPathComponent("\(vpsMap.id).glb")

        if FileManager.default.fileExists(atPath: cacheFile.path) {
            print("MultiSetVPS >> Loading mesh from cache: \(cacheFile.path)")
            let meshData = try Data(contentsOf: cacheFile)
            let pose = calculateMeshPose(mapId: vpsMap.id)

            return MeshResult(
                mapId: vpsMap.id,
                meshFilePath: cacheFile,
                meshData: meshData,
                localPosition: pose.position,
                localRotation: pose.rotation,
                visualizationOption: visualizationOption
            )
        }

        // print("MultiSetVPS >> Downloading mesh for map \(vpsMap.id)")
        guard let meshData = try await downloadMesh(meshLink: meshLink, cacheFile: cacheFile) else {
            print("MultiSetVPS >> Failed to download mesh")
            return nil
        }

        let pose = calculateMeshPose(mapId: vpsMap.id)

        return MeshResult(
            mapId: vpsMap.id,
            meshFilePath: cacheFile,
            meshData: meshData,
            localPosition: pose.position,
            localRotation: pose.rotation,
            visualizationOption: visualizationOption
        )
    }

    private func fetchMapDetails(mapId: String) async throws -> VpsMap? {
        let urlString = "\(SDKEndpoints.getMapURL)\(mapId)"

        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("MultiSetVPS >> Failed to fetch map details: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            return nil
        }

        return try JSONDecoder().decode(VpsMap.self, from: data)
    }

    private func fetchMapSetDetails(mapSetCode: String) async throws -> MapSetResult? {
        guard let url = URL(string: "\(SDKEndpoints.getMapSetURL)\(mapSetCode)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        return try JSONDecoder().decode(MapSetResult.self, from: data)
    }

    private func downloadMesh(meshLink: String, cacheFile: URL) async throws -> Data? {
        guard let signedUrl = try await getSignedUrl(meshLink: meshLink) else {
            return nil
        }
        return try await downloadFromUrl(signedUrl, cacheFile: cacheFile)
    }

    private func getSignedUrl(meshLink: String) async throws -> String? {
        guard let encodedKey = meshLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(SDKEndpoints.getFileURL)?key=\(encodedKey)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let fileData = try JSONDecoder().decode(FileData.self, from: data)
        return fileData.url
    }

    private func downloadFromUrl(_ urlString: String, cacheFile: URL) async throws -> Data? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        try data.write(to: cacheFile)
        return data
    }

    /// Computes the mesh's pose relative to the localized mapset origin. When an
    /// entry carries a populated `baseMap`, its `baseRelativePose` is authoritative
    /// (matching Unity's `UpdateMeshPoseAndRotation`); otherwise `relativePose` on
    /// `map` is used. Returns identity when no matching entry/pose is found.
    private func calculateMeshPose(mapId: String) -> MeshPose {
        guard isMapSet, let mapSet = currentMapSet, let dataList = mapSet.mapSetData else {
            return MeshPose.identity
        }

        for data in dataList {
            if let baseMap = data.baseMap, baseMap.isValid {
                if baseMap.id == mapId || baseMap.mapCode == mapId {
                    return meshPose(from: data.baseRelativePose)
                }
                continue
            }

            if let map = data.map, map.id == mapId || map.mapCode == mapId {
                return meshPose(from: data.relativePose)
            }
        }

        return MeshPose.identity
    }

    private func meshPose(from relativePose: RelativePose?) -> MeshPose {
        guard let relativePose = relativePose else {
            return MeshPose.identity
        }

        // The mapset `relativePose` / `baseRelativePose` values are static data
        // authored by the (left-handed) Unity mapping tool and returned as-is by
        // the map-set endpoint — they are NOT converted by `isRightHanded` the way
        // the localization `estimatedPose` is. ARKit is right-handed, so we must
        // convert each offset from left-handed to right-handed to match the
        // backend's `isRightHanded=true` convention; otherwise every non-identity
        // map offset (i.e. every map except the one at the mapset origin) lands in
        // the wrong place. Single-map localization never exercises this (identity
        // offset), so it always looks correct regardless.
        //
        // Using the X-axis flip convention (basis change S = diag(-1, 1, 1)):
        //   position: (x, y, z)        -> (-x, y, z)
        //   rotation: (qx, qy, qz, qw) -> (qx, -qy, -qz, qw)
        // (Derived from the similarity transform R' = S·R·S for a full rigid pose.)
        let x = relativePose.position?.x ?? 0
        let y = relativePose.position?.y ?? 0
        let z = relativePose.position?.z ?? 0
        let position = SIMD3<Float>(-x, y, z)

        let qx = relativePose.rotation?.qx ?? 0
        let qy = relativePose.rotation?.qy ?? 0
        let qz = relativePose.rotation?.qz ?? 0
        let qw = relativePose.rotation?.qw ?? 1
        let rotation = simd_quatf(ix: qx, iy: -qy, iz: -qz, r: qw)

        return MeshPose(position: position, rotation: rotation)
    }
}
