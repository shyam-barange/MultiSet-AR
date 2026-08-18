import SwiftUI

/// Localization failures are usually aim failures, so coaching is explicit:
/// what to point at, how long it has been trying, and a way out.
public struct MSCoachingOverlay: View {
    private let hint: String
    private let elapsed: Duration
    private let progress: Double
    private let onCancel: () -> Void

    public init(
        hint: String,
        elapsed: Duration,
        progress: Double,
        onCancel: @escaping () -> Void
    ) {
        self.hint = hint
        self.elapsed = elapsed
        self.progress = progress
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(.searching(progress: progress), size: 96)
                .colorScheme(.dark)

            VStack(spacing: MSSpacing.xs) {
                Text(hint)
                    .font(MSFont.headline)
                    .foregroundStyle(MSColor.AR.text)
                    .multilineTextAlignment(.center)
                Text(elapsedText)
                    .font(MSFont.monoSmall)
                    .foregroundStyle(MSColor.AR.textDim)
                    .monospacedDigit()
            }

            Button("Cancel", action: onCancel)
                .font(MSFont.bodyEmphasis)
                .foregroundStyle(MSColor.AR.text)
                .padding(.horizontal, MSSpacing.xl)
                .frame(minHeight: MSSize.minTouchTarget)
                .background(Color.white.opacity(0.14), in: Capsule())
                .accessibilityHint("Stops looking for your position and closes the camera")
        }
        .padding(MSSpacing.xl)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.xl)
                .strokeBorder(MSColor.AR.panelBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Looking for your position. \(hint). \(elapsedText)")
    }

    private var elapsedText: String {
        "SEARCHING \(elapsed.components.seconds)s"
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        MSCoachingOverlay(
            hint: "Point your camera at the room, not the floor",
            elapsed: .seconds(7),
            progress: 0.4,
            onCancel: {}
        )
        .padding(MSSpacing.xl)
    }
    .ignoresSafeArea()
}
