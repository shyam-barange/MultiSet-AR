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
    @State private var showsCredentialEntry = false

    private enum Resolution: Equatable {
        case resolving
        case ready
        /// Signed in, but SDK credentials could not be created. The reason is shown
        /// rather than worked around: substituting a different AR engine silently
        /// answers a question the user did not ask.
        case credentialsUnavailable(reason: MultiSetError)
        case signInRequired
        /// The user chose to continue without the SDK, knowing what that costs.
        case runningWithoutSDK
    }

    var body: some View {
        Group {
            switch resolution {
            case .resolving:
                loading
            case .signInRequired:
                signInRequired
            case .credentialsUnavailable(let reason):
                credentialsUnavailable(reason: reason)
            case .runningWithoutSDK:
                withoutSDK
            case .ready:
                startedSession()
            }
        }
        .task { await resolveCredentials() }
        .onDisappear { session.stop() }
        .sheet(isPresented: $showsCredentialEntry) {
            SDKCredentialsSheet { credentials in
                startSDK(with: credentials)
            }
        }
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
                Localizing runs against the maps in your MultiSet account, so it needs \
                you signed in. Everything on the Home tab works without an account.
                """,
                onRetry: { Task { await resolveCredentials() } },
                onExit: onExit
            )
        }
    }

    /// States the actual failure and offers the three things that can be done about
    /// it, rather than quietly running a different engine.
    private func credentialsUnavailable(reason: MultiSetError) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: MSSpacing.lg) {
                StateArtView(.experienceEnded, size: 88, tint: MSColor.AR.text)

                Text("Couldn't create SDK credentials")
                    .font(MSFont.title)
                    .foregroundStyle(MSColor.AR.text)
                    .multilineTextAlignment(.center)

                Text("""
                The MultiSet SDK authenticates with a client ID and secret, and \
                creating one for this device failed.
                """)
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.AR.textDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // The server's own words, so the cause is diagnosable rather than guessed at.
                Text(reason.errorDescription ?? "")
                    .font(MSFont.monoSmall)
                    .foregroundStyle(MSColor.AR.poor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(MSSpacing.sm)
                    .background(MSColor.AR.panel, in: RoundedRectangle(cornerRadius: MSRadius.sm))
                    .textSelection(.enabled)

                VStack(spacing: MSSpacing.sm) {
                    Button("Enter SDK credentials") { showsCredentialEntry = true }
                        .msButton(.primary, fullWidth: false)
                    Button("Try again") { Task { await resolveCredentials() } }
                        .msButton(.secondary, fullWidth: false)
                    Button("Continue without the SDK") { resolution = .runningWithoutSDK }
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.AR.textDim)
                        .frame(minHeight: MSSize.minTouchTarget)
                        .accessibilityHint("Localizes without the mesh overlay")
                    Button("Close", action: onExit)
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.AR.textDim)
                        .frame(minHeight: MSSize.minTouchTarget)
                }
            }
            .padding(MSSpacing.xl)
        }
    }

    /// Chosen deliberately, never substituted. Uses the same REST engine the App Clip
    /// runs on, driven by the signed-in user's own access token. The mesh overlay is
    /// what is lost: the SDK renders it with a hand-written glTF parser and a Metal
    /// shader that the REST path has no equivalent of.
    @ViewBuilder
    private var withoutSDK: some View {
        switch mode {
        case .localize(let target):
            ARExperienceScreen(
                configuration: ExperienceConfiguration(
                    mode: .localize,
                    target: target.restTarget,
                    localizationMode: target.restLocalizationMode
                ),
                providerFactory: { _ in
                    (RESTPoseProvider(api: model.api, mode: target.restLocalizationMode), nil)
                },
                onExit: onExit
            )
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
        }
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
            resolution = failure == .unauthorized ? .signInRequired : .credentialsUnavailable(reason: failure)
            return
        }

        if let stored = await model.auth.storedMachineCredentials {
            startSDK(with: stored)
        } else {
            resolution = .credentialsUnavailable(reason: .decoding(context: "SDK credentials"))
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
