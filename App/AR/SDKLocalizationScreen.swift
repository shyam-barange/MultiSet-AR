import MultiSetKit
import MultiSetSDK
import MultiSetUI
import SwiftUI

/// Localization against one of the developer's own maps, driven by `MultiSetSDK`.
///
/// This is the screen a developer standing in their own building uses to check that
/// VPS places them where it should. It uses `MultiSetARView` so the SDK owns the AR
/// session — which is what makes the map mesh download and render on success.
struct SDKLocalizationScreen: View {
    let target: SDKSession.Target
    let credentials: M2MCredentials
    let environment: APIEnvironment
    var settings = SDKSettings()
    let onExit: () -> Void

    @StateObject private var session = SDKSession()
    @State private var showsDiagnostics = true
    @State private var showsCloseConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            MultiSetARView().ignoresSafeArea()

            switch session.phase {
            case .idle, .authenticating:
                ServerWaitOverlay(statusText: "Authenticating with MultiSet…")
            case .failed(let error):
                SDKFailureOverlay(
                    title: "Couldn't start the session",
                    message: error,
                    onRetry: start,
                    onExit: onExit
                )
            case .ready:
                controls
            }

            if session.isCapturingFrames {
                FrameCaptureOverlay(statusText: captureStatus)
            } else if session.isShowingOverlay {
                ServerWaitOverlay()
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .msToast($session.toast)
        .task { start() }
        .onDisappear { session.stop() }
        .onChange(of: scenePhase) { phase in
            // The SDK's pose-consistency check trusts the session frame, and a
            // suspended ARSession may resume having moved, so it is told directly.
            if phase != .active {
                MultiSet.shared.stopLocalization()
            }
        }
        .alert("Localization failed", isPresented: failureAlert) {
            Button("Try again") { session.localize() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.failureMessage ?? "")
        }
        .alert("Response discarded", isPresented: falsePositiveAlert) {
            Button("Localize again") { session.localize() }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(session.falsePositive.map(Self.falsePositiveText) ?? "")
        }
        .confirmationDialog(
            "Close this session?",
            isPresented: $showsCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                session.stop()
                onExit()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: MSSpacing.lg)
            bottomBar
        }
        .padding(.horizontal, MSSpacing.lg)
        .padding(.top, MSSpacing.sm)
        // Clear of the home indicator, per the design system.
        .padding(.bottom, MSSpacing.xl)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: MSSpacing.sm) {
            VStack(alignment: .leading, spacing: MSSpacing.xs) {
                statusChip
                meshChip
            }
            Spacer(minLength: MSSpacing.sm)
            circleButton("info.circle", "Toggle diagnostics") { showsDiagnostics.toggle() }
            circleButton("xmark", "Close session") { showsCloseConfirmation = true }
        }
    }

    private var statusChip: some View {
        HStack(spacing: MSSpacing.xs) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusLabel)
                .font(MSFont.captionEmphasis)
                .foregroundStyle(MSColor.AR.text)
        }
        .padding(.horizontal, MSSpacing.md)
        .padding(.vertical, MSSpacing.sm)
        .background(MSColor.AR.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1))
        .accessibilityLabel("Status: \(statusLabel)")
    }

    /// Mesh state is called out separately: a fix can succeed while the mesh is
    /// still downloading, and a developer needs to see which of the two is which.
    @ViewBuilder
    private var meshChip: some View {
        switch session.mapMesh {
        case .none:
            EmptyView()
        case .loading:
            meshLabel("Loading map mesh…", tone: MSColor.AR.poor, symbol: "arrow.down.circle")
        case .loaded(let code):
            meshLabel("Mesh \(code)", tone: MSColor.AR.good, symbol: "cube.transparent")
        case .failed:
            meshLabel("Mesh unavailable", tone: MSColor.AR.bad, symbol: "exclamationmark.triangle")
        }
    }

    private func meshLabel(_ text: String, tone: Color, symbol: String) -> some View {
        HStack(spacing: MSSpacing.xs) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text)
        }
        .font(MSFont.monoSmall)
        .foregroundStyle(tone)
        .padding(.horizontal, MSSpacing.sm)
        .padding(.vertical, MSSpacing.xxs + 1)
        .background(MSColor.AR.panel, in: Capsule())
        .accessibilityLabel(text)
    }

    private var bottomBar: some View {
        VStack(spacing: MSSpacing.md) {
            if showsDiagnostics {
                PoseReadout(session.readout)
                if session.falsePositiveCount > 0 {
                    discardedNotice
                }
            }
            HStack(alignment: .center) {
                if session.hasLocalized {
                    Button("Reset") { session.resetWorldOrigin() }
                        .font(MSFont.captionEmphasis)
                        .foregroundStyle(MSColor.AR.text)
                        .padding(.horizontal, MSSpacing.lg)
                        .frame(minHeight: MSSize.minTouchTarget)
                        .background(MSColor.warning.opacity(0.9), in: Capsule())
                        .accessibilityHint("Discards the current fix and the pose reference")
                }
                Spacer(minLength: MSSpacing.sm)
                if !session.isShowingOverlay && !session.isLocalizing {
                    CaptureButton(isEnabled: session.isTrackingNormal) { session.localize() }
                }
            }
        }
    }

    private var discardedNotice: some View {
        HStack(spacing: MSSpacing.xs) {
            Image(systemName: "arrow.uturn.backward")
            Text("\(session.falsePositiveCount) response\(session.falsePositiveCount == 1 ? "" : "s") discarded as inconsistent")
        }
        .font(MSFont.monoSmall)
        .foregroundStyle(MSColor.AR.poor)
        .padding(.horizontal, MSSpacing.sm)
        .padding(.vertical, MSSpacing.xs)
        .background(MSColor.AR.panel, in: Capsule())
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Derived

    private func start() {
        session.start(
            target: target,
            credentials: credentials,
            environment: environment,
            settings: settings
        )
    }

    private var captureStatus: String {
        switch target.localizationMode {
        case .singleFrame: "Capturing one frame"
        case .multiFrame: "Capturing \(settings.frameCount) frames"
        // The SDK ships as a binary framework, so a future mode could appear
        // without this app being recompiled against it.
        @unknown default: "Capturing frames"
        }
    }

    private var statusLabel: String {
        if session.isCapturingFrames { return "Capturing" }
        if session.isShowingOverlay { return "Matching" }
        if session.hasLocalized { return "Localized" }
        if !session.isTrackingNormal { return "Stabilising" }
        return "Ready"
    }

    private var statusColor: Color {
        if session.hasLocalized { return MSColor.AR.good }
        if session.failureMessage != nil { return MSColor.AR.bad }
        return MSColor.AR.poor
    }

    private var failureAlert: Binding<Bool> {
        Binding(
            get: { session.failureMessage != nil },
            set: { if !$0 { session.clearFailure() } }
        )
    }

    private var falsePositiveAlert: Binding<Bool> {
        Binding(
            get: { session.falsePositive != nil },
            set: { if !$0 { session.clearFalsePositive() } }
        )
    }

    /// Says what came back, what was done with it, and what to do next. A discard is
    /// not a failure — the request succeeded and the scene was deliberately left alone.
    static func falsePositiveText(_ info: FalsePositiveInfo) -> String {
        var lines = [
            "MultiSet matched your camera image to a different part of the space."
        ]
        lines.append(String(
            format: "That pose sits %.1f m from where this device's own motion says the map is (limit %.0f m), so it was discarded and the map was left where it is.",
            info.jumpMeters, info.thresholdMeters
        ))
        if info.consecutiveCount > 1 {
            lines.append("\(info.consecutiveCount) responses in a row have been discarded.")
        }
        lines.append("Move a few steps, aim at a well-lit, distinctive area, and localize again.")
        if info.consecutiveCount >= 3 {
            lines.append("If the map itself looks misplaced, tap Reset — the next response becomes the new reference.")
        }
        return lines.joined(separator: "\n\n")
    }
}

/// Shown when the SDK could not be configured or authenticated at all.
struct SDKFailureOverlay: View {
    let title: String
    let message: String
    let onRetry: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: MSSpacing.lg) {
            StateArtView(.experienceEnded, size: 96, tint: MSColor.AR.text)
            Text(title)
                .font(MSFont.title)
                .foregroundStyle(MSColor.AR.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.textDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: MSSpacing.sm) {
                Button("Try again", action: onRetry).msButton(.primary, fullWidth: false)
                Button("Close", action: onExit).msButton(.secondary, fullWidth: false)
            }
        }
        .padding(MSSpacing.xl)
        .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.xl))
        .padding(MSSpacing.lg)
    }
}
