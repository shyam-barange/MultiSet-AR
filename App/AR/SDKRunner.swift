import MultiSetARCore
import MultiSetKit
import MultiSetUI
import SwiftUI

/// Presents an SDK-driven session, resolving the credentials it needs first.
///
/// `MultiSetSDK` authenticates with a clientId and clientSecret, which the app mints
/// for itself after sign-in. Without them there is nothing to fall back to on this
/// screen: the SDK is the thing being exercised.
struct SDKRunner: View {
    enum Mode: Equatable, Identifiable {
        case localize(target: SDKSession.Target)
        case trackObjects(codes: [String])

        var id: String {
            switch self {
            case .localize(let target): "localize-\(target.displayCode)-\(target.localizationMode.rawValue)"
            case .trackObjects(let codes): "track-\(codes.joined(separator: ","))"
            }
        }
    }

    let mode: Mode
    let onExit: () -> Void

    @EnvironmentObject private var model: AppModel
    @StateObject private var session = SDKSession()
    @State private var credentials: M2MCredentials?
    @State private var resolution: Resolution = .resolving

    private enum Resolution: Equatable {
        case resolving
        case ready
        /// Signed in, but the SDK credentials the AR screens need could not be
        /// created. Localization still runs — see `restFallback`.
        case restFallback(reason: MultiSetError)
        case signInRequired
    }

    var body: some View {
        Group {
            switch resolution {
            case .resolving:
                loading
            case .signInRequired:
                signInRequired
            case .restFallback(let reason):
                restFallback(reason: reason)
            case .ready:
                startedSession()
            }
        }
        .task { await resolveCredentials() }
        .onDisappear { session.stop() }
    }

    /// The AR view is only built once the SDK is initialized. `MultiSetARView` hands
    /// the SDK its session, mesh parent, object anchor and gizmo handler from
    /// `makeUIView`, and each of those is dropped if the SDK is not ready — so
    /// rendering it too early leaves the SDK with no frames and nothing to move.
    @ViewBuilder
    private func startedSession() -> some View {
        if session.isSDKInitialized {
            switch mode {
            case .localize(let target):
                SDKLocalizationScreen(
                    target: target,
                    onRetry: { Task { await restart() } },
                    onExit: onExit,
                    session: session
                )
            case .trackObjects(let codes):
                SDKObjectTrackingScreen(
                    objectCodes: codes,
                    onRetry: { Task { await restart() } },
                    onExit: onExit,
                    session: session
                )
            }
        } else {
            loading
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
                Localizing runs against the maps in your MultiSet account, so it needs                 you signed in. Everything on the Home tab works without an account.
                """,
                onRetry: { Task { await resolveCredentials() } },
                onExit: onExit
            )
        }
    }

    /// Signed in, but no SDK credentials. Rather than dead-ending, this runs the same
    /// REST localization the App Clip uses — driven by the signed-in user's own access
    /// token, refreshed as needed. The mesh overlay is the one thing lost: the SDK
    /// renders it with its own glTF parser and Metal shader, which the REST path has
    /// no equivalent of.
    @ViewBuilder
    private func restFallback(reason: MultiSetError) -> some View {
        switch mode {
        case .localize(let target):
            ARExperienceScreen(
                configuration: ExperienceConfiguration(
                    mode: .localize,
                    target: target.restTarget,
                    localizationMode: target.restLocalizationMode
                ),
                providerFactory: { _ in (RESTPoseProvider(api: model.api, mode: target.restLocalizationMode), nil) },
                onExit: onExit
            )
            .task { await announceFallback(reason) }
        case .trackObjects(let codes):
            ARExperienceScreen(
                configuration: ExperienceConfiguration(
                    mode: .track,
                    target: .map(code: codes.first ?? ""),
                    objectCodes: codes
                ),
                providerFactory: { _ in
                    let rest = RESTPoseProvider(api: model.api)
                    return (rest, rest)
                },
                onExit: onExit
            )
            .task { await announceFallback(reason) }
        }
    }

    private func announceFallback(_ reason: MultiSetError) async {
        model.toast = MSToast(
            message: "Running without the SDK, so no mesh overlay. \(reason.errorDescription ?? "")",
            tone: .info
        )
    }

    private func resolveCredentials() async {
        resolution = .resolving

        if let stored = await model.auth.storedMachineCredentials {
            startSDK(with: stored)
            return
        }

        guard model.isSignedIn else {
            resolution = .signInRequired
            return
        }

        // A signed-in user has everything needed to create SDK credentials, so this
        // is done for them rather than asked of them.
        if let failure = await model.ensureSDKCredentials() {
            resolution = failure == .unauthorized ? .signInRequired : .restFallback(reason: failure)
            return
        }

        if let stored = await model.auth.storedMachineCredentials {
            startSDK(with: stored)
        } else {
            resolution = .restFallback(reason: .decoding(context: "SDK credentials"))
        }
    }

    /// Initializes the SDK before anything renders `MultiSetARView`.
    private func startSDK(with credentials: M2MCredentials) {
        self.credentials = credentials
        session.start(
            target: sessionTarget,
            credentials: credentials,
            environment: model.environment
        )
        resolution = .ready
    }

    private var sessionTarget: SDKSession.Target {
        switch mode {
        case .localize(let target): target
        case .trackObjects(let codes): .objects(codes: codes)
        }
    }

    private func restart() async {
        session.stop()
        await resolveCredentials()
    }
}

extension SDKSession.Target {
    /// The equivalent target for the REST engine, which addresses maps and map sets
    /// the same way but has no notion of the SDK's localization mode.
    var restTarget: MapTarget {
        switch self {
        case .map(let code, _): .map(code: code)
        case .mapSet(let code, _): .mapSet(code: code)
        case .objects(let codes): .map(code: codes.first ?? "")
        }
    }

    var restLocalizationMode: MultiSetKit.LocalizationMode {
        switch localizationMode {
        case .singleFrame: .singleFrame
        case .multiFrame: .multiFrame
        @unknown default: .multiFrame
        }
    }
}

/// The hosted-experience runner: an experience opened from a QR code runs on the
/// REST pose provider so the parent app behaves exactly like the App Clip, which
/// cannot link the SDK at all.
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
