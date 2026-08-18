import SwiftUI

/// One localization attempt, projected to the map's floor plane.
public struct HeatmapSample: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let x: Double
    public let z: Double
    public let weight: Double
    public let succeeded: Bool

    public init(id: UUID = UUID(), x: Double, z: Double, weight: Double = 1, succeeded: Bool = true) {
        self.id = id
        self.x = x
        self.z = z
        self.weight = weight
        self.succeeded = succeeded
    }
}

/// Plan-view density plot of where a map has been localized against, drawn with
/// `Canvas` so it tints with the accent and costs no bundle bytes.
public struct LocalizationHeatmap: View {
    private let samples: [HeatmapSample]
    private let showsFailures: Bool

    public init(samples: [HeatmapSample], showsFailures: Bool = true) {
        self.samples = samples
        self.showsFailures = showsFailures
    }

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let bounds = Self.bounds(of: samples) else { return }
                drawGrid(in: &context, size: size)
                for sample in samples where showsFailures || sample.succeeded {
                    let point = Self.project(sample, bounds: bounds, into: size)
                    let radius = 6 + 10 * sample.weight
                    let color = sample.succeeded ? MSColor.accent : MSColor.danger
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - radius, y: point.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.5), color.opacity(0)]),
                            center: point, startRadius: 0, endRadius: radius
                        )
                    )
                }
                for sample in samples where showsFailures || sample.succeeded {
                    let point = Self.project(sample, bounds: bounds, into: size)
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                        with: .color(sample.succeeded ? MSColor.accent : MSColor.danger)
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(MSColor.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.md)
                .strokeBorder(MSColor.borderSubtle, lineWidth: 1)
        )
        .accessibilityLabel("Localization heatmap")
        .accessibilityValue("\(samples.filter(\.succeeded).count) successful of \(samples.count) attempts")
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = 32
        var path = Path()
        for x in stride(from: 0, through: size.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, through: size.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(MSColor.border.opacity(0.4)), lineWidth: 0.5)
    }

    static func bounds(of samples: [HeatmapSample]) -> (minX: Double, maxX: Double, minZ: Double, maxZ: Double)? {
        guard let first = samples.first else { return nil }
        var result = (minX: first.x, maxX: first.x, minZ: first.z, maxZ: first.z)
        for sample in samples.dropFirst() {
            result.minX = min(result.minX, sample.x)
            result.maxX = max(result.maxX, sample.x)
            result.minZ = min(result.minZ, sample.z)
            result.maxZ = max(result.maxZ, sample.z)
        }
        return result
    }

    /// Projects a sample into view space, preserving aspect ratio so the plan
    /// view is not stretched. A degenerate extent collapses to the centre.
    static func project(
        _ sample: HeatmapSample,
        bounds: (minX: Double, maxX: Double, minZ: Double, maxZ: Double),
        into size: CGSize,
        inset: CGFloat = 20
    ) -> CGPoint {
        let spanX = bounds.maxX - bounds.minX
        let spanZ = bounds.maxZ - bounds.minZ
        let usable = CGSize(width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
        guard spanX > 0 || spanZ > 0 else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let scale = min(usable.width / max(spanX, .ulpOfOne), usable.height / max(spanZ, .ulpOfOne))
        let drawn = CGSize(width: spanX * scale, height: spanZ * scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        return CGPoint(
            x: origin.x + (sample.x - bounds.minX) * scale,
            y: origin.y + (sample.z - bounds.minZ) * scale
        )
    }
}

#Preview {
    LocalizationHeatmap(samples: (0..<160).map { index in
        let angle = Double(index) * 0.31
        let radius = 3 + Double(index % 17) * 0.5
        return HeatmapSample(
            x: cos(angle) * radius,
            z: sin(angle) * radius * 0.6,
            weight: Double(index % 5) / 4,
            succeeded: index % 11 != 0
        )
    })
    .frame(height: 240)
    .padding()
}
