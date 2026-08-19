/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Handles downloading and caching object tracking meshes
/// Two-step download: GET object details -> GET signed URL -> download GLB
internal class ObjectMeshHandler {

    // MARK: - Properties

    /// Read at request time so a refresh mid-session is picked up.
    private let tokenBox: VPSTokenBox

    private var meshCacheDir: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let meshDir = cacheDir.appendingPathComponent("object_mesh_cache")

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

    /// Download mesh for an object code
    /// Step 1: GET /v1/vps/object/{objectCode} -> ModelSet with meshLink
    /// Step 2: GET /v1/file?key={meshLink} -> signed URL
    /// Step 3: Download GLB from signed URL, cache to disk
    func downloadObjectMesh(objectCode: String) async throws -> ObjectMeshResult? {
        // Step 1: Get object details
        guard let modelSet = try await fetchObjectDetails(objectCode: objectCode) else {
            return nil
        }

        guard let meshLink = modelSet.objectMesh?.meshLink, !meshLink.isEmpty else {
            return nil
        }

        let fileName = "\(modelSet.id)_textured.glb"
        let cacheFile = meshCacheDir.appendingPathComponent(fileName)

        // Check cache first
        if FileManager.default.fileExists(atPath: cacheFile.path) {
            let meshData = try Data(contentsOf: cacheFile)
            return ObjectMeshResult(
                objectCode: objectCode,
                meshData: meshData,
                meshFilePath: cacheFile
            )
        }

        // Step 2: Get signed URL
        guard let signedUrl = try await getSignedUrl(meshLink: meshLink) else {
            return nil
        }

        // Step 3: Download GLB
        guard let meshData = try await downloadFile(from: signedUrl, cacheFile: cacheFile) else {
            return nil
        }

        return ObjectMeshResult(
            objectCode: objectCode,
            meshData: meshData,
            meshFilePath: cacheFile
        )
    }

    func clearCache() {
        let files = try? FileManager.default.contentsOfDirectory(at: meshCacheDir, includingPropertiesForKeys: nil)
        files?.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Private Methods

    private func fetchObjectDetails(objectCode: String) async throws -> ModelSet? {
        let urlString = "\(SDKEndpoints.getObjectURL)\(objectCode)"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(tokenBox.value)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        return try JSONDecoder().decode(ModelSet.self, from: data)
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

    private func downloadFile(from urlString: String, cacheFile: URL) async throws -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        try data.write(to: cacheFile)
        return data
    }
}
