import MultiSetKit
import MultiSetSDK
import MultiSetUI
import SwiftUI

/// Object tracking against one of the developer's own tracked objects.
///
/// On success the SDK downloads the object's mesh and renders it as an outline
/// traced along the real object's silhouette, parented to a world-fixed anchor
/// rather than to the localization gizmo — so it stays put independently of any
/// map fix. The gizmo is hidden here because there is no map origin to show.
struct SDKObjectTrackingScreen: View {
    let objectCodes: [String]
    let credentials: M2MCredentials
    let environment: APIEnvironment
    var settings = SDKSettings()
    let onExit: () -> Void

    @StateObject private var session = SDKSession()
    @State private var showsDiagnostics = true
    @State private var showsCloseConfirmation = false

    var body: some View {
        ZStack {
            MultiSetARView().ignoresSafeArea()

            switch session.phase {
            case .idle, .authenticating:
                ServerWaitOverlay(statusText: "Authenticating with MultiSet…")
            case .failed(let error):
                SDKFailureOverlay(
                    title: "Couldn't start tracking",
                    message: error,
                    onRetry: start,
                    onExit: onExit
                )
            case .ready:
                controls
            }

            if session.isObjectTrackingActive {
                ServerWaitOverlay(statusText: "Looking for the object…")
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .msToast($session.toast)
        .task {
            start()
            // No map origin is involved in object tracking, so the localization
            // gizmo would only be a distraction.
            session.setGizmoVisible(false)
        }
        .onDisappear {
            session.setGizmoVisible(true)
            session.stop()
        }
        .alert("Tracking failed", isPresented: failureAlert) {
            Button("Try again") { session.startObjectTracking() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.failureMessage ?? "")
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

    private var controls: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: MSSpacing.lg)
            bottomBar
        }
        .padding(.horizontal, MSSpacing.lg)
        .padding(.top, MSSpacing.sm)
        .padding(.bottom, MSSpacing.xl)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: MSSpacing.sm) {
            VStack(alignment: .leading, spacing: MSSpacing.xs) {
                objectChip
                meshChip
            }
            Spacer(minLength: MSSpacing.sm)
            circleButton("info.circle", "Toggle diagnostics") { showsDiagnostics.toggle() }
            circleButton("xmark", "Close session") { showsCloseConfirmation = true }
        }
    }

    private var objectChip: some View {
        HStack(spacing: MSSpacing.xs) {
            Circle()
                .fill(session.hasTrackedObject ? MSColor.AR.good : MSColor.AR.poor)
                .frame(width: 8, height: 8)
            Text(session.trackedObjectCode ?? objectCodes.first ?? "—")
                .font(MSFont.mono)
                .foregroundStyle(MSColor.AR.text)
        }
        .padding(.horizontal, MSSpacing.md)
        .padding(.vertical, MSSpacing.sm)
        .background(MSColor.AR.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(MSColor.AR.panelBorder, lineWidth: 1))
        .accessibilityLabel("Object \(session.trackedObjectCode ?? objectCodes.first ?? "none")")
    }

    @ViewBuilder
    private var meshChip: some View {
        switch session.objectMesh {
        case .none:
            EmptyView()
        case .loading:
            chip("Loading object mesh…", tone: MSColor.AR.poor, symbol: "arrow.down.circle")
        case .loaded(let code):
            chip("Outline \(code)", tone: MSColor.AR.good, symbol: "cube.transparent")
        case .failed:
            chip("Mesh unavailable", tone: MSColor.AR.bad, symbol: "exclamationmark.triangle")
        }
    }

    private func chip(_ text: String, tone: Color, symbol: String) -> some View {
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
                PoseReadout(readout)
            }
            HStack {
                if session.hasTrackedObject {
                    Button("Reset") { session.resetObjectTracking() }
                        .font(MSFont.captionEmphasis)
                        .foregroundStyle(MSColor.AR.text)
                        .padding(.horizontal, MSSpacing.lg)
                        .frame(minHeight: MSSize.minTouchTarget)
                        .background(MSColor.warning.opacity(0.9), in: Capsule())
                        .accessibilityHint("Clears the outline and looks again")
                }
                Spacer(minLength: MSSpacing.sm)
                if !session.isObjectTrackingActive {
                    CaptureButton(isEnabled: session.isTrackingNormal) {
                        session.startObjectTracking()
                    }
                }
            }
        }
    }

    private var readout: PoseReadoutData {
        var data = session.readout
        data.mapCode = session.trackedObjectCode ?? objectCodes.first
        data.confidence = session.trackedObjectConfidence.map(Float.init)
        return data
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

    private func start() {
        session.start(
            target: .objects(codes: objectCodes),
            credentials: credentials,
            environment: environment,
            settings: settings
        )
    }

    private var failureAlert: Binding<Bool> {
        Binding(
            get: { session.failureMessage != nil },
            set: { if !$0 { session.clearFailure() } }
        )
    }
}
