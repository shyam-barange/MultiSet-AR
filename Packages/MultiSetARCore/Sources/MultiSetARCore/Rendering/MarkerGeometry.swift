import Foundation
import RealityKit
import simd
import UIKit

/// POI markers and object outlines, all generated in code.
public enum MarkerGeometry {
    /// A survey control point: a ring with a vertical stem, echoing the
    /// registration mark used throughout the interface.
    @MainActor
    public static func pointOfInterest(
        color: SIMD3<Float> = SIMD3(0.486, 0.227, 0.929),
        isDestination: Bool = false
    ) -> Entity {
        let root = Entity()
        let tint = UIColor(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 1
        )

        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: tint.withAlphaComponent(0.9))
        // A ring of short bars rather than a cylinder: MeshResource.generateCylinder
        // is iOS 18+, and the deployment target is iOS 16.
        let ringRadius: Float = isDestination ? 0.34 : 0.22
        let segments = 24
        for step in 0..<segments {
            let angle = Float(step) / Float(segments) * 2 * .pi
            let arcLength = 2 * .pi * ringRadius / Float(segments) * 1.15
            let bar = ModelEntity(
                mesh: .generateBox(width: arcLength, height: 0.006, depth: 0.014),
                materials: [ringMaterial]
            )
            bar.position = SIMD3<Float>(cos(angle) * ringRadius, 0, sin(angle) * ringRadius)
            bar.orientation = simd_quatf(angle: -angle, axis: SIMD3<Float>(0, 1, 0))
            root.addChild(bar)
        }

        var stemMaterial = UnlitMaterial()
        stemMaterial.color = .init(tint: tint.withAlphaComponent(0.55))
        let stemHeight: Float = isDestination ? 1.1 : 0.7
        let stem = ModelEntity(
            mesh: .generateBox(width: 0.012, height: stemHeight, depth: 0.012),
            materials: [stemMaterial]
        )
        stem.position = SIMD3<Float>(0, stemHeight / 2, 0)
        root.addChild(stem)

        if isDestination {
            var capMaterial = UnlitMaterial()
            capMaterial.color = .init(tint: tint)
            let cap = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [capMaterial])
            cap.position = SIMD3<Float>(0, stemHeight, 0)
            root.addChild(cap)
        }
        return root
    }

    /// A wireframe box tracing an object's extent. Edges only — the design brief
    /// calls for a registration overlay, nothing filled or glowing.
    @MainActor
    public static func outlineBox(
        size: SIMD3<Float>,
        color: SIMD3<Float> = SIMD3(0.486, 0.227, 0.929),
        thickness: Float = 0.006
    ) -> Entity {
        let root = Entity()
        var material = UnlitMaterial()
        material.color = .init(tint: UIColor(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 0.95
        ))

        let half = size / 2
        for edge in boxEdges(half: half) {
            let delta = edge.1 - edge.0
            let length = simd_length(delta)
            guard length > 1e-5 else { continue }
            let bar = ModelEntity(
                mesh: .generateBox(width: thickness, height: thickness, depth: length),
                materials: [material]
            )
            bar.position = (edge.0 + edge.1) / 2
            bar.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(delta))
            root.addChild(bar)
        }
        return root
    }

    /// The twelve edges of an axis-aligned box, as endpoint pairs.
    static func boxEdges(half: SIMD3<Float>) -> [(SIMD3<Float>, SIMD3<Float>)] {
        let corners: [SIMD3<Float>] = [
            SIMD3(-half.x, -half.y, -half.z), SIMD3(half.x, -half.y, -half.z),
            SIMD3(half.x, -half.y, half.z), SIMD3(-half.x, -half.y, half.z),
            SIMD3(-half.x, half.y, -half.z), SIMD3(half.x, half.y, -half.z),
            SIMD3(half.x, half.y, half.z), SIMD3(-half.x, half.y, half.z)
        ]
        let pairs: [(Int, Int)] = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        return pairs.map { (corners[$0.0], corners[$0.1]) }
    }

    /// The world origin of a localized map, drawn as three axes. Useful to a
    /// developer verifying that a map's origin is where they think it is.
    @MainActor
    public static func originGizmo(length: Float = 0.3) -> Entity {
        let root = Entity()
        let axes: [(SIMD3<Float>, UIColor)] = [
            (SIMD3(length, 0, 0), .systemRed),
            (SIMD3(0, length, 0), .systemGreen),
            (SIMD3(0, 0, length), .systemBlue)
        ]
        for (offset, color) in axes {
            var material = UnlitMaterial()
            material.color = .init(tint: color)
            let bar = ModelEntity(
                mesh: .generateBox(width: 0.008, height: 0.008, depth: length),
                materials: [material]
            )
            bar.position = offset / 2
            bar.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(offset))
            root.addChild(bar)
        }
        return root
    }
}
