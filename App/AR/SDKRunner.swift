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
    @State private var credentials: M2MCredentials?
    @State private var resolution: Resolution = .resolving

    private enum Resolution: Equatable {
        case resolving
        case ready
        case missingCredentials
    }

    var body: some View {
        Group {
            switch resolution {
            case .resolving:
                loading
            case .missingCredentials:
                missingCredentials
            case .ready:
                if let credentials {
                    session(with: credentials)
                }
            }
        }
        .task { await resolveCredentials() }
    }

    @ViewBuilder
    private func session(with credentials: M2MCredentials) -> some View {
        switch mode {
        case .localize(let target):
            SDKLocalizationScreen(
                target: target,
                credentials: credentials,
                environment: model.environment,
                onExit: onExit
            )
        case .trackObjects(let codes):
            SDKObjectTrackingScreen(
                objectCodes: codes,
                credentials: credentials,
                environment: model.environment,
                onExit: onExit
            )
        }
    }

    private var loading: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView().tint(MSColor.AR.text)
        }
    }

    private var missingCredentials: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SDKFailureOverlay(
                title: "SDK credentials needed",
                message: """
                This screen runs the MultiSet SDK, which authenticates with a client ID \
                and secret. The app creates those for you after sign-in — try signing in \
                again, or create a set in the developer portal.
                """,
                onRetry: { Task { await mintCredentials() } },
                onExit: onExit
            )
        }
    }

    private func resolveCredentials() async {
        if let stored = await model.auth.storedMachineCredentials {
            credentials = stored
            resolution = .ready
            return
        }
        await mintCredentials()
    }

    private func mintCredentials() async {
        resolution = .resolving
        await model.ensureSDKCredentials()
        if let stored = await model.auth.storedMachineCredentials {
            credentials = stored
            resolution = .ready
        } else {
            resolution = .missingCredentials
        }
    }
}

/// The hosted-experience runner, unchanged: an experience opened from a QR code runs
/// on the REST pose provider so the parent app behaves exactly like the App Clip,
/// which cannot link the SDK at all.
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
