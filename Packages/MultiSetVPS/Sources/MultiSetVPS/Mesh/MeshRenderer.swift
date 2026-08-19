/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import RealityKit
import ARKit
import Metal
import simd
import UIKit
import Combine

/// Internal GLB mesh renderer for RealityKit
internal class MeshRenderer {

    // MARK: - Properties

    // Multiple meshes can be displayed simultaneously — e.g. each map in a
    // localized mapset overlays its own portion of the space. Keyed by mapId so
    // meshes accumulate instead of replacing one another (mirrors Unity, where
    // each localized map is a separate persistent child of the shared anchor).
    private var meshEntities: [String: Entity] = [:]
    private var revealAnimators: [String: MeshRevealAnimator] = [:]
    private var renderingMapIds: Set<String> = []
    private var surfaceShader: CustomMaterial.SurfaceShader?
    private var useCustomMaterial: Bool = false

    var meshColor: SIMD4<Float> = SIMD4<Float>(0.482, 0.173, 0.749, 0.7)

    // MARK: - Initialization

    init() {
        loadMetalShader()
    }

    private func loadMetalShader() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("MultiSetVPS >> MeshRenderer: No Metal device available")
            return
        }

        do {
            // Bundle.module, not Bundle(for:). The shaders compile into this
            // package's own resource bundle; in a statically linked package
            // Bundle(for:) resolves to the app bundle, where there is no
            // default.metallib — the load would fail and fall back to a plain
            // material, silently losing the shader.
            let library = try device.makeDefaultLibrary(bundle: .module)
            surfaceShader = CustomMaterial.SurfaceShader(named: "radialRevealSurface", in: library)
            useCustomMaterial = true
            print("MultiSetVPS >> MeshRenderer: Radial reveal shader loaded")
        } catch {
            print("MultiSetVPS >> MeshRenderer: Failed to load Metal shader, using fallback material - \(error)")
        }
    }

    // MARK: - Public Methods

    func renderMesh(meshResult: MeshResult, parentEntity: Entity, cameraWorldPosition: SIMD3<Float>? = nil, arSession: ARSession? = nil) {
        let mapId = meshResult.mapId

        // Already rendered for this map and still attached → nothing to do.
        // (Dedup so re-localization against the same map doesn't reload it.)
        if let existing = meshEntities[mapId], existing.parent != nil {
            return
        }

        // A render for this map is already in flight.
        if renderingMapIds.contains(mapId) {
            return
        }

        // Stale entry (was removed from the scene) → drop it before re-rendering.
        if let stale = meshEntities[mapId] {
            revealAnimators[mapId]?.stopAnimation()
            revealAnimators[mapId] = nil
            stale.removeFromParent()
            meshEntities[mapId] = nil
        }

        renderingMapIds.insert(mapId)

        Task {
            await loadAndRenderMesh(meshResult: meshResult, parent: parentEntity, cameraWorldPosition: cameraWorldPosition, arSession: arSession)
            await MainActor.run {
                self.renderingMapIds.remove(mapId)
            }
        }
    }

    /// Removes all rendered meshes (used when clearing/resetting the scene).
    func removeMesh() {
        for animator in revealAnimators.values {
            animator.stopAnimation()
        }
        revealAnimators.removeAll()

        for entity in meshEntities.values {
            entity.removeFromParent()
        }
        meshEntities.removeAll()
    }

    /// Removes a single map's mesh, leaving any others in place.
    func removeMesh(mapId: String) {
        revealAnimators[mapId]?.stopAnimation()
        revealAnimators[mapId] = nil
        meshEntities[mapId]?.removeFromParent()
        meshEntities[mapId] = nil
    }

    func setMeshVisible(_ visible: Bool) {
        for entity in meshEntities.values {
            entity.isEnabled = visible
        }
    }

    func hasMesh() -> Bool {
        return !meshEntities.isEmpty
    }

    func isMeshRenderedForMap(mapId: String) -> Bool {
        return meshEntities[mapId] != nil
    }

    func forceRerender() {
        removeMesh()
    }

    func setMeshColor(r: Float, g: Float, b: Float, alpha: Float) {
        meshColor = SIMD4<Float>(r, g, b, alpha)
    }

    // MARK: - Private Methods

    @MainActor
    private func loadAndRenderMesh(meshResult: MeshResult, parent: Entity, cameraWorldPosition: SIMD3<Float>?, arSession: ARSession?) async {
        do {
            let containerEntity = try parseGLBFile(data: meshResult.meshData)

            containerEntity.position = meshResult.localPosition
            containerEntity.orientation = meshResult.localRotation
            containerEntity.scale = SIMD3<Float>(1, 1, 1)

            parent.addChild(containerEntity)

            meshEntities[meshResult.mapId] = containerEntity

            // Start radial reveal animation if custom material is active and camera position is available
            if useCustomMaterial, let cameraPos = cameraWorldPosition {
                let animator = MeshRevealAnimator()
                animator.loop = true
                animator.delayBetweenLoops = 20.0
                revealAnimators[meshResult.mapId] = animator
                animator.startRevealAnimation(containerEntity: containerEntity, cameraWorldPosition: cameraPos, arSession: arSession)
            }
        } catch {
            // Mesh loading failed silently
        }
    }

    // MARK: - GLB Parser

    private func parseGLBFile(data: Data) throws -> Entity {
        guard data.count >= 12 else {
            throw GLBError.invalidHeader
        }

        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == 0x46546C67 else {
            throw GLBError.invalidMagic
        }

        var offset = 12
        var jsonData: Data?
        var binaryData: Data?

        while offset < data.count {
            guard offset + 8 <= data.count else { break }

            let chunkLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            let chunkType = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self) }

            offset += 8

            guard offset + Int(chunkLength) <= data.count else { break }

            let chunkData = data.subdata(in: offset..<(offset + Int(chunkLength)))

            if chunkType == 0x4E4F534A {
                jsonData = chunkData
            } else if chunkType == 0x004E4942 {
                binaryData = chunkData
            }

            offset += Int(chunkLength)
        }

        guard let json = jsonData, let binary = binaryData else {
            throw GLBError.missingChunks
        }

        let gltf = try JSONDecoder().decode(GLTFRoot.self, from: json)
        return try createEntityFromGLTF(gltf: gltf, binaryData: binary)
    }

    private func createEntityFromGLTF(gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let containerEntity = Entity()

        guard let meshes = gltf.meshes, !meshes.isEmpty else {
            throw GLBError.noMeshes
        }

        // Walk the scene graph via nodes to respect transforms
        if let nodes = gltf.nodes, let scenes = gltf.scenes, let sceneIndex = gltf.scene,
           sceneIndex < scenes.count, let rootNodeIndices = scenes[sceneIndex].nodes {
            for nodeIndex in rootNodeIndices {
                let nodeEntity = try buildNodeEntity(
                    nodeIndex: nodeIndex, nodes: nodes, meshes: meshes,
                    gltf: gltf, binaryData: binaryData
                )
                containerEntity.addChild(nodeEntity)
            }
        } else {
            // Fallback: no scene graph, iterate meshes directly (original behavior)
            for mesh in meshes {
                let meshEntity = try buildMeshEntity(mesh: mesh, gltf: gltf, binaryData: binaryData)
                containerEntity.addChild(meshEntity)
            }
        }

        return containerEntity
    }

    private func buildNodeEntity(nodeIndex: Int, nodes: [GLTFNode], meshes: [GLTFMesh],
                                 gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let node = nodes[nodeIndex]
        let nodeEntity = Entity()

        // Apply node transform
        if let matrix = node.matrix, matrix.count == 16 {
            // Column-major 4x4 matrix
            let col0 = SIMD4<Float>(matrix[0], matrix[1], matrix[2], matrix[3])
            let col1 = SIMD4<Float>(matrix[4], matrix[5], matrix[6], matrix[7])
            let col2 = SIMD4<Float>(matrix[8], matrix[9], matrix[10], matrix[11])
            let col3 = SIMD4<Float>(matrix[12], matrix[13], matrix[14], matrix[15])
            let transform = float4x4(col0, col1, col2, col3)
            nodeEntity.transform = Transform(matrix: transform)
        } else {
            if let t = node.translation, t.count == 3 {
                nodeEntity.position = SIMD3<Float>(t[0], t[1], t[2])
            }
            if let r = node.rotation, r.count == 4 {
                // glTF quaternion order: [x, y, z, w]
                nodeEntity.orientation = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
            }
            if let s = node.scale, s.count == 3 {
                nodeEntity.scale = SIMD3<Float>(s[0], s[1], s[2])
            }
        }

        // If this node references a mesh, build it
        if let meshIndex = node.mesh, meshIndex < meshes.count {
            let meshEntity = try buildMeshEntity(mesh: meshes[meshIndex], gltf: gltf, binaryData: binaryData)
            nodeEntity.addChild(meshEntity)
        }

        // Recurse into children
        if let children = node.children {
            for childIndex in children where childIndex < nodes.count {
                let childEntity = try buildNodeEntity(
                    nodeIndex: childIndex, nodes: nodes, meshes: meshes,
                    gltf: gltf, binaryData: binaryData
                )
                nodeEntity.addChild(childEntity)
            }
        }

        return nodeEntity
    }

    private func buildMeshEntity(mesh: GLTFMesh, gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let meshContainer = Entity()

        for primitive in mesh.primitives {
            guard let positionAccessorIndex = primitive.attributes["POSITION"],
                  let accessors = gltf.accessors,
                  positionAccessorIndex < accessors.count else {
                continue
            }

            let positionAccessor = accessors[positionAccessorIndex]

            let positions = try extractVec3Data(
                accessor: positionAccessor,
                bufferViews: gltf.bufferViews ?? [],
                binaryData: binaryData
            )

            var normals: [SIMD3<Float>] = []
            if let normalAccessorIndex = primitive.attributes["NORMAL"],
               normalAccessorIndex < accessors.count {
                let normalAccessor = accessors[normalAccessorIndex]
                normals = try extractVec3Data(
                    accessor: normalAccessor,
                    bufferViews: gltf.bufferViews ?? [],
                    binaryData: binaryData
                )
            }

            var indices: [UInt32] = []
            if let indicesAccessorIndex = primitive.indices,
               indicesAccessorIndex < accessors.count {
                let indicesAccessor = accessors[indicesAccessorIndex]
                indices = try extractIndices(
                    accessor: indicesAccessor,
                    bufferViews: gltf.bufferViews ?? [],
                    binaryData: binaryData
                )
            } else {
                indices = (0..<UInt32(positions.count)).map { $0 }
            }

            if let modelEntity = createMeshEntity(positions: positions, normals: normals, indices: indices) {
                meshContainer.addChild(modelEntity)
            }
        }

        return meshContainer
    }

    private func extractVec3Data(accessor: GLTFAccessor, bufferViews: [GLTFBufferView], binaryData: Data) throws -> [SIMD3<Float>] {
        guard let bufferViewIndex = accessor.bufferView,
              bufferViewIndex < bufferViews.count else {
            throw GLBError.invalidBufferView
        }

        let bufferView = bufferViews[bufferViewIndex]
        let byteOffset = (bufferView.byteOffset ?? 0) + (accessor.byteOffset ?? 0)
        let byteStride = bufferView.byteStride ?? 12

        var result: [SIMD3<Float>] = []
        result.reserveCapacity(accessor.count)

        binaryData.withUnsafeBytes { ptr in
            for i in 0..<accessor.count {
                let offset = byteOffset + (i * byteStride)
                let x = ptr.load(fromByteOffset: offset, as: Float.self)
                let y = ptr.load(fromByteOffset: offset + 4, as: Float.self)
                let z = ptr.load(fromByteOffset: offset + 8, as: Float.self)
                result.append(SIMD3<Float>(x, y, z))
            }
        }

        return result
    }

    private func extractIndices(accessor: GLTFAccessor, bufferViews: [GLTFBufferView], binaryData: Data) throws -> [UInt32] {
        guard let bufferViewIndex = accessor.bufferView,
              bufferViewIndex < bufferViews.count else {
            throw GLBError.invalidBufferView
        }

        let bufferView = bufferViews[bufferViewIndex]
        let byteOffset = (bufferView.byteOffset ?? 0) + (accessor.byteOffset ?? 0)

        var result: [UInt32] = []
        result.reserveCapacity(accessor.count)

        binaryData.withUnsafeBytes { ptr in
            for i in 0..<accessor.count {
                let index: UInt32
                switch accessor.componentType {
                case 5121:
                    let offset = byteOffset + i
                    index = UInt32(ptr.load(fromByteOffset: offset, as: UInt8.self))
                case 5123:
                    let offset = byteOffset + (i * 2)
                    index = UInt32(ptr.load(fromByteOffset: offset, as: UInt16.self))
                case 5125:
                    let offset = byteOffset + (i * 4)
                    index = ptr.load(fromByteOffset: offset, as: UInt32.self)
                default:
                    index = 0
                }
                result.append(index)
            }
        }

        return result
    }

    private func createMeshEntity(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) -> ModelEntity? {
        guard !positions.isEmpty else { return nil }

        var meshDescriptor = MeshDescriptor(name: "glb_mesh")
        meshDescriptor.positions = MeshBuffer(positions)

        if !indices.isEmpty {
            meshDescriptor.primitives = .triangles(indices)
        } else {
            let autoIndices = (0..<UInt32(positions.count)).map { $0 }
            meshDescriptor.primitives = .triangles(autoIndices)
        }

        if !normals.isEmpty && normals.count == positions.count {
            meshDescriptor.normals = MeshBuffer(normals)
        }

        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])

            let tintColor = UIColor(
                red: CGFloat(meshColor.x),
                green: CGFloat(meshColor.y),
                blue: CGFloat(meshColor.z),
                alpha: CGFloat(meshColor.w)
            )

            // Try CustomMaterial with radial reveal shader, fallback to UnlitMaterial
            if useCustomMaterial, let shader = surfaceShader {
                do {
                    var material = try CustomMaterial(surfaceShader: shader, lightingModel: .unlit)
                    // Set tint to white so the shader has full control over color output.
                    // RealityKit multiplies baseColor.tint with the shader's set_base_color().
                    material.baseColor.tint = .white
                    material.blending = .transparent(opacity: 1.0)
                    // Start hidden (radius = 0), animator will drive this
                    material.custom.value = SIMD4<Float>(0, 0, 0, 0)

                    if #available(iOS 18.0, *) {
                        material.faceCulling = .back
                    }

                    return ModelEntity(mesh: meshResource, materials: [material])
                } catch {
                    print("MultiSetVPS >> MeshRenderer: CustomMaterial creation failed, using fallback - \(error)")
                }
            }

            // Fallback: standard UnlitMaterial (no animation)
            var material = UnlitMaterial()
            material.color = .init(tint: tintColor)
            material.blending = .transparent(opacity: .init(floatLiteral: Float(meshColor.w)))

            if #available(iOS 18.0, *) {
                material.faceCulling = .back
            }

            return ModelEntity(mesh: meshResource, materials: [material])
        } catch {
            return nil
        }
    }
}

// MARK: - GLB/GLTF Data Structures

internal enum GLBError: Error {
    case invalidHeader
    case invalidMagic
    case missingChunks
    case noMeshes
    case invalidBufferView
    case invalidAccessor
}

internal struct GLTFRoot: Codable {
    let asset: GLTFAsset?
    let scene: Int?
    let scenes: [GLTFScene]?
    let nodes: [GLTFNode]?
    let meshes: [GLTFMesh]?
    let accessors: [GLTFAccessor]?
    let bufferViews: [GLTFBufferView]?
    let buffers: [GLTFBuffer]?
    let materials: [GLTFMaterial]?
}

internal struct GLTFAsset: Codable {
    let version: String
    let generator: String?
}

internal struct GLTFScene: Codable {
    let name: String?
    let nodes: [Int]?
}

internal struct GLTFNode: Codable {
    let name: String?
    let mesh: Int?
    let children: [Int]?
    let translation: [Float]?
    let rotation: [Float]?
    let scale: [Float]?
    let matrix: [Float]?
}

internal struct GLTFMesh: Codable {
    let name: String?
    let primitives: [GLTFPrimitive]
}

internal struct GLTFPrimitive: Codable {
    let attributes: [String: Int]
    let indices: Int?
    let material: Int?
    let mode: Int?
}

internal struct GLTFAccessor: Codable {
    let bufferView: Int?
    let byteOffset: Int?
    let componentType: Int
    let count: Int
    let type: String
    let max: [Float]?
    let min: [Float]?
}

internal struct GLTFBufferView: Codable {
    let buffer: Int
    let byteOffset: Int?
    let byteLength: Int
    let byteStride: Int?
    let target: Int?
}

internal struct GLTFBuffer: Codable {
    let byteLength: Int
    let uri: String?
}

internal struct GLTFMaterial: Codable {
    let name: String?
    let pbrMetallicRoughness: GLTFPBRMetallicRoughness?
    let doubleSided: Bool?
}

internal struct GLTFPBRMetallicRoughness: Codable {
    let baseColorFactor: [Float]?
    let metallicFactor: Float?
    let roughnessFactor: Float?
}
