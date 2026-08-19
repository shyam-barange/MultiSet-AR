import MultiSetKit
import MultiSetUI
import SwiftUI

/// Everything drawn over the camera feed. Controls sit clear of the home
/// indicator, and every state offers a way out.
public struct ARExperienceOverlay: View {
    @ObservedObject public var engine: LocalizationEngine
    public let mode: ExperienceMode
    @Binding public var showsDiagnostics: Bool
    public let onRetry: () -> Void
    public let onCapture: () -> Void
    public let onExit: () -> Void

    public init(
        engine: LocalizationEngine,
        mode: ExperienceMode,
        showsDiagnostics: Binding<Bool>,
        onRetry: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onExit: @escaping () -> Void
    ) {
        self.engine = engine
        self.mode = mode
        self._showsDiagnostics = showsDiagnostics
        self.onRetry = onRetry
        self.onCapture = onCapture
        self.onExit = onExit
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: MSSpacing.lg)
            centrePanel
            Spacer(minLength: MSSpacing.lg)
            bottomBar
        }
        .padding(.horizontal, MSSpacing.lg)
        .padding(.top, MSSpacing.sm)
        // Keeps controls off the home indicator, per the design system's rule
        // that nothing interactive sits bottom-edge-adjacent.
        .padding(.bottom, MSSpacing.xl)
        .animation(.easeInOut(duration: 0.2), value: engine.state)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top, spacing: MSSpacing.sm) {
            statusChip
            Spacer(minLength: MSSpacing.sm)
            circleButton("info.circle", label: "Toggle diagnostics") {
                showsDiagnostics.toggle()
            }
            circleButton("xmark", label: "Close AR session", action: onExit)
        }
    }

    private var statusChip: some View {
        HStack(spacing: MSSpacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(MSFont.captionEmphasis)
                .foregroundStyle(MSColor.AR.text)
        }
        .padding(.horizontal, MSSpacing.md)
        .padding(.vertical, MSSpacing.sm)
        .background(MSColor.AR.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session status: \(statusLabel)")
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MSColor.AR.text)
                .frame(width: MSSize.minTouchTarget, height: MSSize.minTouchTarget)
                .background(MSColor.AR.panel, in: Circle())
                .overlay(Circle().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Centre

    @ViewBuilder
    private var centrePanel: some View {
        switch engine.state {
        case .searching(let hint, let elapsed, let attempts):
            MSCoachingOverlay(
                hint: hint,
                elapsed: elapsed,
                progress: min(Double(attempts) / 4, 0.95),
                onCancel: onExit
            )
        case .initializing:
            MSCoachingOverlay(
                hint: "Starting the camera",
                elapsed: .zero,
                progress: 0,
                onCancel: onExit
            )
        case .failed(let error):
            failurePanel(error)
        case .lost(let since):
            lostPanel(since: since)
        case .arrived(let destination):
            arrivedPanel(destination)
        default:
            EmptyView()
        }
    }

    private func failurePanel(_ error: MultiSetError) -> some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(.invalidated, size: 88).colorScheme(.dark)
            Text(error.errorDescription ?? "Something stopped the session.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.text)
                .multilineTextAlignment(.center)
            HStack(spacing: MSSpacing.sm) {
                if error.isRetryable {
                    Button("Try again", action: onRetry).msButton(.primary, fullWidth: false)
                }
                Button("Close", action: onExit).msButton(.secondary, fullWidth: false)
            }
        }
        .padding(MSSpacing.xl)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.xl)
                .strokeBorder(MSColor.AR.panelBorder, lineWidth: 1)
        )
    }

    private func lostPanel(since: Duration) -> some View {
        VStack(spacing: MSSpacing.md) {
            Text("Your position has drifted")
                .font(MSFont.headline)
                .foregroundStyle(MSColor.AR.text)
            Text("It's been \(since.components.seconds)s since the last fix. Point the camera at the room to re-anchor.")
                .font(MSFont.caption)
                .foregroundStyle(MSColor.AR.textDim)
                .multilineTextAlignment(.center)
            Button("Re-localize", action: onRetry).msButton(.primary, fullWidth: false)
        }
        .padding(MSSpacing.lg)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.lg))
    }

    private func arrivedPanel(_ destination: String) -> some View {
        VStack(spacing: MSSpacing.md) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(MSColor.AR.good)
            Text("You've arrived")
                .font(MSFont.title)
                .foregroundStyle(MSColor.AR.text)
            Text(destination)
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.textDim)
            Button("Done", action: onExit).msButton(.primary, fullWidth: false)
        }
        .padding(MSSpacing.xl)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.xl))
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: MSSpacing.md) {
            if case .navigating(let remaining, let nextTurn, let destination) = engine.state {
                navigationBanner(remaining: remaining, nextTurn: nextTurn, destination: destination)
            }
            if showsDiagnostics {
                PoseReadout(readoutData)
            }
            HStack(spacing: MSSpacing.md) {
                Button(action: onRetry) {
                    Label("Re-localize", systemImage: "scope")
                        .font(MSFont.captionEmphasis)
                        .foregroundStyle(MSColor.AR.text)
                        .padding(.horizontal, MSSpacing.lg)
                        .frame(minHeight: MSSize.minTouchTarget)
                        .background(MSColor.AR.panel, in: Capsule())
                        .overlay(Capsule().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1))
                }
                .accessibilityLabel("Localize again")

                Spacer(minLength: MSSpacing.sm)

                Button(action: onCapture) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MSColor.AR.text)
                        .frame(width: 56, height: 56)
                        .background(MSColor.AR.panel, in: Circle())
                        .overlay(Circle().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1.5))
                }
                .accessibilityLabel("Save a screenshot to Photos")
            }
        }
    }

    private func navigationBanner(remaining: Double, nextTurn: String?, destination: String) -> some View {
        HStack(spacing: MSSpacing.md) {
            Image(systemName: engine.guidance?.turn.symbolName ?? "arrow.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MSColor.AR.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(nextTurn ?? "Continue")
                    .font(MSFont.bodyEmphasis)
                    .foregroundStyle(MSColor.AR.text)
                Text("\(engine.guidance?.distanceDescription ?? "—") to \(destination)")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.AR.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(MSSpacing.md)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.lg)
                .strokeBorder(MSColor.AR.panelBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nextTurn ?? "Continue"), \(engine.guidance?.distanceDescription ?? "") to \(destination)")
    }

    // MARK: - Derived values

    private var readoutData: PoseReadoutData {
        let diagnostics = engine.diagnostics
        var position: (x: Float, y: Float, z: Float)?
        var rotation: (x: Float, y: Float, z: Float, w: Float)?
        var mapCode: String?

        if case .localized(let result) = engine.state {
            position = (Float(result.pose.position.x), Float(result.pose.position.y), Float(result.pose.position.z))
            rotation = (
                Float(result.pose.rotation.x), Float(result.pose.rotation.y),
                Float(result.pose.rotation.z), Float(result.pose.rotation.w)
            )
            mapCode = result.primaryMapCode
        }

        return PoseReadoutData(
            position: position,
            rotation: rotation,
            confidence: diagnostics.lastConfidence.map(Float.init),
            latency: diagnostics.lastLatency,
            framesSubmitted: diagnostics.framesSubmitted,
            queryCount: diagnostics.queryCount,
            mapCode: mapCode ?? diagnostics.providerName,
            trackingState: diagnostics.trackingState
        )
    }

    private var statusLabel: String {
        switch engine.state {
        case .idle: "Idle"
        case .initializing: "Starting"
        case .searching: "Searching"
        case .localized: "Localized"
        case .lost: "Drifted"
        case .navigating: "Navigating"
        case .arrived: "Arrived"
        case .tracking: "Tracking"
        case .failed: "Stopped"
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .localized, .navigating, .arrived, .tracking: MSColor.AR.good
        case .searching, .initializing, .lost: MSColor.AR.poor
        case .failed: MSColor.AR.bad
        case .idle: MSColor.AR.textDim
        }
    }
}
