import SwiftUI

/// The four empty and error states, drawn as geometry so they scale with Dynamic
/// Type, tint with the accent, and cost no bundle bytes. One visual family:
/// a survey registration grid, thin strokes, consistent construction.
public enum MSIllustration: Sendable {
    case noMaps
    case noObjects
    case searching(progress: Double)
    case invalidated
}

public struct MSIllustrationView: View {
    private let kind: MSIllustration
    private let size: CGFloat

    public init(_ kind: MSIllustration, size: CGFloat = 120) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            drawGrid(&context, in: rect)
            switch kind {
            case .noMaps:
                drawControlPoint(&context, at: center(rect), scale: rect.width / 120)
            case .noObjects:
                drawGhostVolume(&context, in: rect)
            case .searching(let progress):
                drawConvergingCross(&context, in: rect, progress: progress)
            case .invalidated:
                drawStruckMark(&context, in: rect)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private func drawGrid(_ context: inout GraphicsContext, in rect: CGRect) {
        let step = rect.width / 6
        var path = Path()
        for i in 0...6 {
            let offset = CGFloat(i) * step
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }
        context.stroke(path, with: .color(MSColor.border.opacity(0.5)), lineWidth: 0.75)
    }

    private func drawControlPoint(_ context: inout GraphicsContext, at point: CGPoint, scale: CGFloat) {
        let arm = 14 * scale
        var cross = Path()
        cross.move(to: CGPoint(x: point.x - arm, y: point.y))
        cross.addLine(to: CGPoint(x: point.x + arm, y: point.y))
        cross.move(to: CGPoint(x: point.x, y: point.y - arm))
        cross.addLine(to: CGPoint(x: point.x, y: point.y + arm))
        context.stroke(cross, with: .color(MSColor.accent), lineWidth: 1.5)

        let r = 7 * scale
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
            with: .color(MSColor.accent),
            lineWidth: 1.5
        )
        let dot = 2.5 * scale
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
            with: .color(MSColor.accent)
        )
    }

    private func drawGhostVolume(_ context: inout GraphicsContext, in rect: CGRect) {
        let inset = rect.width * 0.24
        let box = rect.insetBy(dx: inset, dy: inset)
        let depth = rect.width * 0.12
        let front = Path(box)
        var back = Path()
        back.addRect(box.offsetBy(dx: depth, dy: -depth))
        var edges = Path()
        for corner in [
            (CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.minX + depth, y: box.minY - depth)),
            (CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX + depth, y: box.minY - depth)),
            (CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.minX + depth, y: box.maxY - depth)),
            (CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.maxX + depth, y: box.maxY - depth))
        ] {
            edges.move(to: corner.0)
            edges.addLine(to: corner.1)
        }
        context.stroke(back, with: .color(MSColor.accent.opacity(0.35)), lineWidth: 1)
        context.stroke(edges, with: .color(MSColor.accent.opacity(0.35)), lineWidth: 1)
        context.stroke(front, with: .color(MSColor.accent), lineWidth: 1.5)
    }

    private func drawConvergingCross(_ context: inout GraphicsContext, in rect: CGRect, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        let spread = (1 - clamped) * rect.width * 0.16
        let mid = center(rect)
        let arm = rect.width * 0.2

        var horizontal = Path()
        horizontal.move(to: CGPoint(x: mid.x - arm, y: mid.y - spread))
        horizontal.addLine(to: CGPoint(x: mid.x + arm, y: mid.y - spread))
        var vertical = Path()
        vertical.move(to: CGPoint(x: mid.x + spread, y: mid.y - arm))
        vertical.addLine(to: CGPoint(x: mid.x + spread, y: mid.y + arm))
        context.stroke(horizontal, with: .color(MSColor.accent), lineWidth: 1.5)
        context.stroke(vertical, with: .color(MSColor.accent), lineWidth: 1.5)

        for ring in 1...3 {
            let r = rect.width * 0.08 * CGFloat(ring) * (0.6 + 0.4 * clamped)
            context.stroke(
                Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)),
                with: .color(MSColor.accent.opacity(0.5 - Double(ring) * 0.12)),
                lineWidth: 1
            )
        }
    }

    private func drawStruckMark(_ context: inout GraphicsContext, in rect: CGRect) {
        drawControlPoint(&context, at: center(rect), scale: rect.width / 120)
        var strike = Path()
        let inset = rect.width * 0.18
        strike.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        strike.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        context.stroke(strike, with: .color(MSColor.textMuted), lineWidth: 2)
    }
}

/// An empty state is an invitation with an action, not an apology.
public struct MSEmptyState<Action: View>: View {
    private let art: StateArt
    private let title: String
    private let message: String
    private let action: Action

    public init(
        _ art: StateArt,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.art = art
        self.title = title
        self.message = message
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: MSSpacing.lg) {
            StateArtView(art)
            VStack(spacing: MSSpacing.sm) {
                Text(title)
                    .font(MSFont.title)
                    .foregroundStyle(MSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            action
        }
        .padding(MSSpacing.xl)
        .frame(maxWidth: 420)
    }
}

public extension MSEmptyState where Action == EmptyView {
    init(_ art: StateArt, title: String, message: String) {
        self.init(art, title: title, message: message) { EmptyView() }
    }
}

#Preview("Illustration family") {
    VStack(spacing: MSSpacing.xl) {
        HStack(spacing: MSSpacing.xl) {
            MSIllustrationView(.noMaps)
            MSIllustrationView(.noObjects)
        }
        HStack(spacing: MSSpacing.xl) {
            MSIllustrationView(.searching(progress: 0.35))
            MSIllustrationView(.invalidated)
        }
    }
    .padding()
}

#Preview("Empty state") {
    MSEmptyState(
        StateArt.noMaps,
        title: "No maps yet",
        message: "Scan a space with the MultiSet app, or upload a point cloud in the developer portal."
    ) {
        Button("Open developer portal") {}.msButton(.primary, fullWidth: false)
    }
}
