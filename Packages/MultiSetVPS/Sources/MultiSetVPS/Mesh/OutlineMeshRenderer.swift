/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import RealityKit
import Metal
import simd
import UIKit
import QuartzCore

/// Renders object tracking meshes with animated outline shader effect
/// Creates two entities per mesh:
/// 1. OcclusionMaterial entity (depth-only, hides solid interior)
/// 2. CustomMaterial entity (expanded outline with front-face culling, animated sparks)
internal class OutlineMeshRenderer {

    // MARK: - Properties

    private var meshEntities: [String: Entity] = [:]  // objectCode -> container entity
    private var isRendering: Bool = false

    // Metal shader references
    private var outlineSurfaceShader: CustomMaterial.SurfaceShader?
    private var outlineGeometryModifier: CustomMaterial.GeometryModifier?
    private var useCustomMaterial: Bool = false

    // Animation
    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var outlineWidth: Float = 0.006
    private var animatedEntities: [ModelEntity] = []

    // MARK: - Initialization

    init() {
        loadMetalShaders()
    }

    private func loadMetalShaders() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // No Metal device available
            return
        }

        do {
            // Bundle.module, not Bundle(for:). The shaders compile into this
            // package's own resource bundle; in a statically linked package
            // Bundle(for:) resolves to the app bundle, where there is no
            // default.metallib — the load would fail and fall back to a plain
            // material, silently losing the shader.
            let library = try device.makeDefaultLibrary(bundle: .module)

            outlineSurfaceShader = CustomMaterial.SurfaceShader(named: "outlineSurface", in: library)
            outlineGeometryModifier = CustomMaterial.GeometryModifier(named: "outlineGeometry", in: library)
            useCustomMaterial = true
        } catch {
            // Metal shader load failed, will use fallback material
        }
    }

    // MARK: - Public Methods

    func renderOutlineMesh(meshResult: ObjectMeshResult, parentEntity: Entity) {
        guard !isRendering else { return }

        // Don't re-render if already loaded for this object
        if meshEntities[meshResult.objectCode] != nil { return }

        isRendering = true

        Task {
            await loadAndRenderMesh(meshResult: meshResult, parent: parentEntity)
            await MainActor.run {
                self.isRendering = false
            }
        }
    }

    func removeAllMeshes() {
        stopAnimation()
        for (_, entity) in meshEntities {
            entity.removeFromParent()
        }
        meshEntities.removeAll()
        animatedEntities.removeAll()
    }

    func setMeshVisible(for objectCode: String, visible: Bool) {
        meshEntities[objectCode]?.isEnabled = visible
    }

    // MARK: - Private Methods

    @MainActor
    private func loadAndRenderMesh(meshResult: ObjectMeshResult, parent: Entity) async {
        do {
            let containerEntity = try parseGLBAndCreateOutline(data: meshResult.meshData)

            containerEntity.position = .zero
            containerEntity.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

            parent.addChild(containerEntity)
            meshEntities[meshResult.objectCode] = containerEntity

            // Collect animated entities and start animation
            let newAnimatedEntities = collectModelEntities(from: containerEntity)
                .filter { entity in
                    entity.model?.materials.contains(where: { $0 is CustomMaterial }) ?? false
                }
            animatedEntities.append(contentsOf: newAnimatedEntities)

            if !animatedEntities.isEmpty && displayLink == nil {
                startAnimation()
            }

        } catch {
            // Mesh rendering failed silently
        }
    }

    // MARK: - GLB Parsing & Outline Entity Creation

    private func parseGLBAndCreateOutline(data: Data) throws -> Entity {
        guard data.count >= 12 else { throw GLBError.invalidHeader }

        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        guard magic == 0x46546C67 else { throw GLBError.invalidMagic }

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
        return try createOutlineEntityFromGLTF(gltf: gltf, binaryData: binary)
    }

    private func createOutlineEntityFromGLTF(gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let containerEntity = Entity()

        guard let meshes = gltf.meshes, !meshes.isEmpty else {
            throw GLBError.noMeshes
        }

        if let nodes = gltf.nodes, let scenes = gltf.scenes, let sceneIndex = gltf.scene,
           sceneIndex < scenes.count, let rootNodeIndices = scenes[sceneIndex].nodes {
            for nodeIndex in rootNodeIndices {
                let nodeEntity = try buildOutlineNodeEntity(
                    nodeIndex: nodeIndex, nodes: nodes, meshes: meshes,
                    gltf: gltf, binaryData: binaryData
                )
                containerEntity.addChild(nodeEntity)
            }
        } else {
            for mesh in meshes {
                let meshEntity = try buildOutlineMeshEntity(mesh: mesh, gltf: gltf, binaryData: binaryData)
                containerEntity.addChild(meshEntity)
            }
        }

        return containerEntity
    }

    private func buildOutlineNodeEntity(nodeIndex: Int, nodes: [GLTFNode], meshes: [GLTFMesh],
                                         gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let node = nodes[nodeIndex]
        let nodeEntity = Entity()

        // Apply node transform
        if let matrix = node.matrix, matrix.count == 16 {
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
                nodeEntity.orientation = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
            }
            if let s = node.scale, s.count == 3 {
                nodeEntity.scale = SIMD3<Float>(s[0], s[1], s[2])
            }
        }

        if let meshIndex = node.mesh, meshIndex < meshes.count {
            let meshEntity = try buildOutlineMeshEntity(mesh: meshes[meshIndex], gltf: gltf, binaryData: binaryData)
            nodeEntity.addChild(meshEntity)
        }

        if let children = node.children {
            for childIndex in children where childIndex < nodes.count {
                let childEntity = try buildOutlineNodeEntity(
                    nodeIndex: childIndex, nodes: nodes, meshes: meshes,
                    gltf: gltf, binaryData: binaryData
                )
                nodeEntity.addChild(childEntity)
            }
        }

        return nodeEntity
    }

    private func buildOutlineMeshEntity(mesh: GLTFMesh, gltf: GLTFRoot, binaryData: Data) throws -> Entity {
        let meshContainer = Entity()

        for primitive in mesh.primitives {
            guard let positionAccessorIndex = primitive.attributes["POSITION"],
                  let accessors = gltf.accessors,
                  positionAccessorIndex < accessors.count else {
                continue
            }

            let positionAccessor = accessors[positionAccessorIndex]
            let positions = try extractVec3Data(accessor: positionAccessor, bufferViews: gltf.bufferViews ?? [], binaryData: binaryData)

            var normals: [SIMD3<Float>] = []
            if let normalAccessorIndex = primitive.attributes["NORMAL"],
               normalAccessorIndex < accessors.count {
                normals = try extractVec3Data(accessor: accessors[normalAccessorIndex], bufferViews: gltf.bufferViews ?? [], binaryData: binaryData)
            }

            // Generate normals if not provided (needed for outline expansion)
            if normals.isEmpty {
                normals = generateNormals(positions: positions, indices: nil)
            }

            var indices: [UInt32] = []
            if let indicesAccessorIndex = primitive.indices,
               indicesAccessorIndex < accessors.count {
                indices = try extractIndices(accessor: accessors[indicesAccessorIndex], bufferViews: gltf.bufferViews ?? [], binaryData: binaryData)
            } else {
                indices = (0..<UInt32(positions.count)).map { $0 }
            }

            // Create occlusion entity (depth-only pass - hides mesh interior)
            if let occlusionEntity = createOcclusionEntity(positions: positions, normals: normals, indices: indices) {
                meshContainer.addChild(occlusionEntity)
            }

            // Create outline entity (expanded mesh with front-face culling + animated shader)
            if let outlineEntity = createOutlineEntity(positions: positions, normals: normals, indices: indices) {
                meshContainer.addChild(outlineEntity)
            }
        }

        return meshContainer
    }

    // MARK: - Entity Creation

    private func createOcclusionEntity(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) -> ModelEntity? {
        guard !positions.isEmpty else { return nil }

        var meshDescriptor = MeshDescriptor(name: "occlusion_mesh")
        meshDescriptor.positions = MeshBuffer(positions)
        meshDescriptor.primitives = .triangles(indices)
        if !normals.isEmpty && normals.count == positions.count {
            meshDescriptor.normals = MeshBuffer(normals)
        }

        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])
            let material = OcclusionMaterial()
            return ModelEntity(mesh: meshResource, materials: [material])
        } catch {
            return nil
        }
    }

    private func createOutlineEntity(positions: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]) -> ModelEntity? {
        guard !positions.isEmpty else { return nil }

        var meshDescriptor = MeshDescriptor(name: "outline_mesh")
        meshDescriptor.positions = MeshBuffer(positions)
        meshDescriptor.primitives = .triangles(indices)
        if !normals.isEmpty && normals.count == positions.count {
            meshDescriptor.normals = MeshBuffer(normals)
        }

        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])

            if useCustomMaterial, let surfaceShader = outlineSurfaceShader,
               let geometryModifier = outlineGeometryModifier {
                var material = try CustomMaterial(
                    surfaceShader: surfaceShader,
                    geometryModifier: geometryModifier,
                    lightingModel: .unlit
                )

                material.baseColor.tint = .white
                material.blending = .transparent(opacity: 1.0)
                // x = outlineWidth, y = time (driven by animation)
                material.custom.value = SIMD4<Float>(outlineWidth, 0, 0, 0)

                if #available(iOS 18.0, *) {
                    material.faceCulling = .front  // Cull front faces for outline effect
                }

                let entity = ModelEntity(mesh: meshResource, materials: [material])
                return entity
            }

            // Fallback: simple cyan emissive outline
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(red: 0, green: 1, blue: 1, alpha: 0.7))
            material.blending = .transparent(opacity: 0.7)

            return ModelEntity(mesh: meshResource, materials: [material])
        } catch {
            return nil
        }
    }

    // MARK: - Geometry Helpers

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
                    index = UInt32(ptr.load(fromByteOffset: byteOffset + i, as: UInt8.self))
                case 5123:
                    index = UInt32(ptr.load(fromByteOffset: byteOffset + (i * 2), as: UInt16.self))
                case 5125:
                    index = ptr.load(fromByteOffset: byteOffset + (i * 4), as: UInt32.self)
                default:
                    index = 0
                }
                result.append(index)
            }
        }

        return result
    }

    private func generateNormals(positions: [SIMD3<Float>], indices: [UInt32]?) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)

        let indexList = indices ?? (0..<UInt32(positions.count)).map { $0 }

        for i in stride(from: 0, to: indexList.count - 2, by: 3) {
            let i0 = Int(indexList[i])
            let i1 = Int(indexList[i + 1])
            let i2 = Int(indexList[i + 2])

            guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { continue }

            let v0 = positions[i0]
            let v1 = positions[i1]
            let v2 = positions[i2]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let faceNormal = cross(edge1, edge2)

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }

        return normals.map { length($0) > 0 ? normalize($0) : SIMD3<Float>(0, 1, 0) }
    }

    // MARK: - Animation

    private func startAnimation() {
        animationStartTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateAnimation() {
        let elapsed = Float(CACurrentMediaTime() - animationStartTime)
        let customValue = SIMD4<Float>(outlineWidth, elapsed, 0, 0)

        for entity in animatedEntities {
            guard var model = entity.model else { continue }
            var updatedMaterials: [any Material] = []

            for material in model.materials {
                if var customMaterial = material as? CustomMaterial {
                    customMaterial.custom.value = customValue
                    updatedMaterials.append(customMaterial)
                } else {
                    updatedMaterials.append(material)
                }
            }

            model.materials = updatedMaterials
            entity.model = model
        }
    }

    // MARK: - Helpers

    private func collectModelEntities(from entity: Entity) -> [ModelEntity] {
        var result: [ModelEntity] = []
        for child in entity.children {
            if let modelEntity = child as? ModelEntity {
                result.append(modelEntity)
            }
            result.append(contentsOf: collectModelEntities(from: child))
        }
        return result
    }
}
