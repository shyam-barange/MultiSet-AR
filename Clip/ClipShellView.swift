import MultiSetARCore
import MultiSetKit
import MultiSetUI
import StoreKit
import SwiftUI

struct ClipShellView: View {
    @EnvironmentObject private var model: ClipModel
    @State private var showsAppStoreOverlay = false

    var body: some View {
        ZStack {
            switch model.state {
            case .awaitingInvocation:
                ClipStatusView(
                    illustration: .searching(progress: 0.5),
                    title: "Opening",
                    message: "Reading the code you scanned."
                )
            case .resolving:
                ClipStatusView(
                    illustration: .searching(progress: 0.75),
                    title: "Getting things ready",
                    message: "Fetching this location's experience."
                )
            case .ready(let manifest):
                ExperienceIntroCard(
                    manifest: manifest,
                    onStart: { model.start() },
                    onCancel: { showsAppStoreOverlay = true }
                )
            case .running:
                runningExperience
            case .finished(let manifest):
                ClipCompletionView(manifest: manifest) {
                    showsAppStoreOverlay = true
                }
            case .failed(let error):
                ClipFailureView(error: error) {
                    Task { await model.retry() }
                }
            }
        }
        .background(MSColor.background.ignoresSafeArea())
        // A soft upsell, never blocking. The experience must be usable and
        // finishable without installing anything.
        .appStoreOverlay(isPresented: $showsAppStoreOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    @ViewBuilder
    private var runningExperience: some View {
        if let configuration = model.configuration {
            ARExperienceScreen(
                configuration: configuration,
                providerFactory: { _ in
                    // The Clip's only pose source. It authenticates with the
                    // anonymous experience token, so no credential is present.
                    let rest = RESTPoseProvider(api: model.experienceAPI)
                    return (rest, configuration.mode == .track ? rest : nil)
                },
                onExit: { model.finish() }
            )
        }
    }
}

struct ClipStatusView: View {
    let illustration: MSIllustration
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(illustration, size: 120)
            Text(title)
                .font(MSFont.title)
                .foregroundStyle(MSColor.textPrimary)
            Text(message)
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(MSSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

/// Every failure the Clip can hit, each stating what happened and what to do
/// next. A dead end with a shrug is the one outcome not allowed here — the person
/// looking at it just scanned a code off a wall.
struct ClipFailureView: View {
    let error: MultiSetError
    let onRetry: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: MSSpacing.xl) {
            MSIllustrationView(illustration, size: 120)

            VStack(spacing: MSSpacing.sm) {
                Text(title)
                    .font(MSFont.title)
                    .foregroundStyle(MSColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(error.errorDescription ?? "")
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: MSSpacing.sm) {
                if error.isRetryable {
                    Button("Try again", action: onRetry)
                        .msButton(.primary, fullWidth: false)
                }
                if case .cameraAccessDenied = error {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .msButton(.primary, fullWidth: false)
                }
                Button("Contact MultiSet") { openURL(ExternalLink.contactEmail) }
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                    .frame(minHeight: MSSize.minTouchTarget)
            }
        }
        .padding(MSSpacing.xl)
    }

    private var title: String {
        switch error {
        case .experienceUnavailable(.unknownCode): "This code isn't valid"
        case .experienceUnavailable(.deactivated): "This experience has ended"
        case .experienceUnavailable(.mapProcessing): "Not ready yet"
        case .experienceUnavailable(.expired): "Session expired"
        case .experienceUnavailable(.deviceUnsupported): "This device can't run it"
        case .arUnsupported: "This device can't run it"
        case .offline: "No connection"
        case .cameraAccessDenied: "Camera access is off"
        case .rateLimited: "Too many people right now"
        default: "Something stopped it"
        }
    }

    private var illustration: MSIllustration {
        switch error {
        case .offline, .rateLimited, .server, .network: .searching(progress: 0.2)
        default: .invalidated
        }
    }
}

struct ClipCompletionView: View {
    let manifest: ExperienceManifest
    let onGetTheApp: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: MSSpacing.xl) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(MSColor.success)

            VStack(spacing: MSSpacing.sm) {
                Text("That's it")
                    .font(MSFont.display)
                    .foregroundStyle(MSColor.textPrimary)
                Text("You just used centimetre-accurate positioning without installing anything.")
                    .font(MSFont.body)
                    .foregroundStyle(MSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: MSSpacing.md) {
                Button("Get the full app", action: onGetTheApp)
                    .msButton()
                Button("Done") { openURL(ExternalLink.website) }
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                    .frame(minHeight: MSSize.minTouchTarget)
            }
        }
        .padding(MSSpacing.xl)
    }
}

#Preview("Resolving") {
    ClipShellView().environmentObject(ClipModel.preview(state: .resolving))
}

#Preview("Invalid code") {
    ClipShellView()
        .environmentObject(ClipModel.preview(state: .failed(.experienceUnavailable(.unknownCode))))
}

#Preview("Ended") {
    ClipShellView()
        .environmentObject(ClipModel.preview(state: .failed(.experienceUnavailable(.deactivated))))
}

#Preview("Offline") {
    ClipShellView().environmentObject(ClipModel.preview(state: .failed(.offline)))
}

#Preview("Map processing") {
    ClipShellView()
        .environmentObject(ClipModel.preview(state: .failed(.experienceUnavailable(.mapProcessing))))
}

#Preview("Camera denied") {
    ClipShellView().environmentObject(ClipModel.preview(state: .failed(.cameraAccessDenied)))
}

#Preview("No ARKit") {
    ClipShellView()
        .environmentObject(ClipModel.preview(state: .failed(.experienceUnavailable(.deviceUnsupported))))
}
