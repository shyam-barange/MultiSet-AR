import MultiSetARCore
import MultiSetKit
import MultiSetUI
import MultiSetVPS
import SwiftUI

/// Presents a VPS session for one of the developer's own maps, map sets, or objects.
///
/// No SDK credentials are involved. The engine is the internal SDK's own
/// implementation, ported so its one credential-bound seam — `AuthManager`, which
/// exchanged a clientId and clientSecret for a token — is replaced by a token
/// provider. Everything below that only ever needed a bearer token, so the
/// signed-in user's access token drives the whole flow: single-frame and
/// multi-frame localization, object tracking, and the mesh overlay that follows.
struct SDKRunner: View {
    enum Mode: Equatable, Identifiable {
        case localize(target: SDKSession.Target)
        case trackObjects(codes: [String])

        var id: String {
            switch self {
            case .localize(let target):
                "localize-\(target.displayCode)-\(target.localizationMode.rawValue)"
            case .trackObjects(let codes):
                "track-\(codes.joined(separator: ","))"
            }
        }
    }

    let mode: Mode
    let onExit: () -> Void

    @EnvironmentObject private var model: AppModel
    @StateObject private var session = SDKSession()
    @State private var isStarted = false

    var body: some View {
        Group {
            if !model.isSignedIn {
                signInRequired
            } else if isStarted && session.isSDKInitialized {
                startedSession
            } else {
                loading
            }
        }
        .task { start() }
        .onDisappear { session.stop() }
    }

    /// The AR view is only built once the engine is initialized. `VPSARView` hands the
    /// engine its AR session, mesh parent, object anchor and gizmo handler from
    /// `makeUIView`, and each of those is dropped if the engine has no internal
    /// manager yet — leaving it with no frames and nothing to move.
    @ViewBuilder
    private var startedSession: some View {
        switch mode {
        case .localize(let target):
            SDKLocalizationScreen(
                target: target,
                onRetry: restart,
                onExit: onExit,
                session: session
            )
        case .trackObjects(let codes):
            SDKObjectTrackingScreen(
                objectCodes: codes,
                onRetry: restart,
                onExit: onExit,
                session: session
            )
        }
    }

    private var loading: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: MSSpacing.md) {
                ProgressView().tint(MSColor.AR.text)
                Text("Preparing the session…")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.AR.textDim)
            }
        }
    }

    private var signInRequired: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SDKFailureOverlay(
                title: "Sign in to localize",
                message: """
                Localizing runs against the maps in your MultiSet account, so it needs \
                you signed in. Everything on the Home tab works without an account.
                """,
                onRetry: start,
                onExit: onExit
            )
        }
    }

    private func start() {
        guard model.isSignedIn, !isStarted else { return }
        // The engine asks this for a token per run, so a session that outlives the
        // 30-minute access token keeps working: AuthStore refreshes from the refresh
        // token, single-flighted so concurrent requests cannot race it.
        let auth = model.auth
        session.start(
            target: sessionTarget,
            tokenProvider: ClosureVPSToken(
                fetch: { try await auth.validToken() },
                invalidate: { await auth.invalidateToken() }
            ),
            environment: model.environment
        )
        isStarted = true
    }

    private func restart() {
        session.stop()
        isStarted = false
        start()
    }

    private var sessionTarget: SDKSession.Target {
        switch mode {
        case .localize(let target): target
        case .trackObjects(let codes): .objects(codes: codes)
        }
    }
}

/// The hosted-experience runner: an experience opened from a QR code runs on the
/// REST pose provider, matching the App Clip exactly.
struct ExperienceRunner: View {
    let manifest: ExperienceManifest
    let onExit: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var hasStarted = false

    var body: some View {
        Group {
            if hasStarted {
                ARExperienceScreen(
                    configuration: ExperienceConfiguration(manifest: manifest),
                    providerFactory: { _ in
                        let rest = RESTPoseProvider(api: model.api)
                        return (rest, manifest.mode == .track ? rest : nil)
                    },
                    onExit: onExit
                )
            } else {
                ExperienceIntroCard(
                    manifest: manifest,
                    onStart: { hasStarted = true },
                    onCancel: onExit
                )
            }
        }
    }
}
