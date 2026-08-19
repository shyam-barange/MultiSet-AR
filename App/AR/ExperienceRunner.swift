import MultiSetARCore
import MultiSetKit
import MultiSetSDK
import SwiftUI

/// Chooses the pose provider and runs the AR screen.
///
/// The SDK is preferred in the parent app when credentials exist, because that is
/// what a customer ships and what a developer wants to evaluate. The REST
/// provider is the fallback and is the only option in the App Clip.
struct TestLocalizationRunner: View {
    let configuration: ExperienceConfiguration
    let onExit: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var credentials: M2MCredentials?
    @State private var hasResolvedCredentials = false

    var body: some View {
        Group {
            if hasResolvedCredentials {
                ARExperienceScreen(
                    configuration: configuration,
                    providerFactory: makeProviders,
                    onExit: onExit
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
            }
        }
        .task {
            credentials = await model.auth.storedMachineCredentials
            hasResolvedCredentials = true
        }
    }

    private func makeProviders(
        _ host: ARSceneHost
    ) -> (provider: any PoseProvider, objects: (any ObjectTrackingProvider)?) {
        if let credentials {
            let sdkMode: MultiSetSDK.LocalizationMode =
                configuration.localizationMode == .singleFrame ? .singleFrame : .multiFrame
            return (
                SDKPoseProvider(
                    credentials: credentials,
                    localizationMode: sdkMode,
                    session: host.session,
                    anchorEntity: host.mapAnchor
                ),
                configuration.mode == .track ? SDKObjectTrackingProvider() : nil
            )
        }
        let rest = RESTPoseProvider(api: model.api, mode: configuration.localizationMode)
        return (rest, configuration.mode == .track ? rest : nil)
    }
}

/// Runs a hosted experience opened from a QR code or a link. Always uses the REST
/// provider so behaviour matches the App Clip exactly.
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
