import Foundation
import MultiSetKit
import RealityKit
import simd
import UIKit

/// Builds the navigation path as geometry generated at runtime.
///
/// Nothing here is a bundled asset: the App Clip has no room for meshes, and a
/// procedural ribbon also adapts to whatever the route turns out to be. The look
/// follows the design brief — flat and matte, like painted floor marking rather
/// than a glowing hologram.
public enum PathRibbon {
    public struct Style: Sendable {
        public var width: Float
        public var heightAboveFloor: Float
        public var color: SIMD3<Float>
        public var opacity: Float

        public init(
            width: Float = 0.26,
            heightAboveFloor: Float = 0.012,
            color: SIMD3<Float> = SIMD3(0.486, 0.227, 0.929),
            opacity: Float = 0.85
        ) {
            self.width = width
            self.heightAboveFloor = heightAboveFloor
            self.color = color
            self.opacity = opacity
        }

        public static let `default` = Style()
    }

    /// Generates a flat ribbon following the given points.
    ///
    /// Returns nil for fewer than two points, since a one-point path has no
    /// direction and would produce degenerate geometry.
    public static func mesh(through points: [SIMD3<Float>], style: Style = .default) -> MeshResource? {
        guard points.count >= 2 else { return nil }

        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let half = style.width / 2
        var travelled: Float = 0

        for (index, point) in points.enumerated() {
            let direction = tangent(at: index, in: points)
            // Perpendicular on the horizontal plane, so the ribbon lies flat
            // regardless of how the path rises or falls.
            var side = simd_cross(SIMD3<Float>(0, 1, 0), direction)
            if simd_length(side) < 1e-5 {
                side = SIMD3<Float>(1, 0, 0)
            }
            side = simd_normalize(side) * half

            let lifted = point + SIMD3<Float>(0, style.heightAboveFloor, 0)
            vertices.append(lifted - side)
            vertices.append(lifted + side)
            normals.append(SIMD3<Float>(0, 1, 0))
            normals.append(SIMD3<Float>(0, 1, 0))

            if index > 0 {
                travelled += simd_distance(points[index - 1], point)
            }
            uvs.append(SIMD2<Float>(0, travelled))
            uvs.append(SIMD2<Float>(1, travelled))
        }

        for segment in 0..<(points.count - 1) {
            let base = UInt32(segment * 2)
            indices.append(contentsOf: [base, base + 2, base + 1])
            indices.append(contentsOf: [base + 1, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "navPath")
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return try? MeshResource.generate(from: [descriptor])
    }

    /// Central difference along the path, clamped at the ends.
    static func tangent(at index: Int, in points: [SIMD3<Float>]) -> SIMD3<Float> {
        let previous = points[max(index - 1, 0)]
        let next = points[min(index + 1, points.count - 1)]
        let delta = next - previous
        guard simd_length(delta) > 1e-5 else { return SIMD3<Float>(0, 0, -1) }
        return simd_normalize(delta)
    }

    @MainActor
    public static func entity(through points: [SIMD3<Float>], style: Style = .default) -> ModelEntity? {
        guard let mesh = mesh(through: points, style: style) else { return nil }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(
            red: CGFloat(style.color.x),
            green: CGFloat(style.color.y),
            blue: CGFloat(style.color.z),
            alpha: 1
        ))
        material.roughness = 0.85
        material.metallic = 0.0
        material.blending = .transparent(opacity: .init(floatLiteral: style.opacity))
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Chevrons laid along the path, marking direction of travel.
    @MainActor
    public static func directionMarkers(
        along points: [SIMD3<Float>],
        spacing: Float = 1.6,
        style: Style = .default
    ) -> [ModelEntity] {
        guard points.count >= 2 else { return [] }
        var markers: [ModelEntity] = []
        var distanceSinceLast: Float = spacing

        for index in 0..<(points.count - 1) {
            let step = simd_distance(points[index], points[index + 1])
            distanceSinceLast += step
            guard distanceSinceLast >= spacing else { continue }
            distanceSinceLast = 0

            let mesh = MeshResource.generateBox(
                width: style.width * 0.5,
                height: 0.004,
                depth: style.width * 0.5,
                cornerRadius: 0.004
            )
            var material = UnlitMaterial()
            material.color = .init(tint: .white.withAlphaComponent(0.7))
            let marker = ModelEntity(mesh: mesh, materials: [material])
            marker.position = points[index] + SIMD3<Float>(0, style.heightAboveFloor + 0.002, 0)

            let direction = tangent(at: index, in: points)
            marker.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: direction)
            markers.append(marker)
        }
        return markers
    }
}
