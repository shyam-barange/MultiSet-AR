import ARKit
import MultiSetKit
import MultiSetUI
import Photos
import SwiftUI

/// The one AR screen, shared by all three modes and by both targets' flows.
///
/// Keeping localize, navigate, and track in one screen is deliberate: they differ
/// only in the overlay above the camera, and three screens would mean three
/// copies of the permission, lifecycle, and escape-hatch handling.
public struct ARExperienceScreen: View {
    public let configuration: ExperienceConfiguration
    public let providerFactory: (ARSceneHost) -> (provider: any PoseProvider, objects: (any ObjectTrackingProvider)?)
    public var onExit: () -> Void

    public init(
        configuration: ExperienceConfiguration,
        providerFactory: @escaping (ARSceneHost) -> (provider: any PoseProvider, objects: (any ObjectTrackingProvider)?),
        onExit: @escaping () -> Void = {}
    ) {
        self.configuration = configuration
        self.providerFactory = providerFactory
        self.onExit = onExit
    }

    @StateObject private var host = ARSceneHost()
    @State private var engine: LocalizationEngine?
    @State private var toast: MSToast?
    @State private var showsDiagnostics = true
    @Environment(\.scenePhase) private var scenePhase

    public var body: some View {
        ZStack {
            if ARSceneHost.isSupported {
                ARSceneView(host: host).ignoresSafeArea()
            } else {
                unsupportedDevice
            }

            if host.cameraAccessDenied {
                cameraDenied
            } else if let engine {
                overlay(engine: engine)
            }
        }
        .background(Color.black)
        .msToast($toast)
        .task { await startSession() }
        .onDisappear {
            engine?.teardown()
            host.pause()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                if engine != nil {
                    host.start()
                    engine?.resume()
                }
            case .background, .inactive:
                engine?.pause()
                host.pause()
            @unknown default:
                break
            }
        }
        .statusBarHidden()
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlay(engine: LocalizationEngine) -> some View {
        // The overlay observes the engine, so state changes re-render only the
        // controls rather than tearing down the ARView beneath them.
        ARExperienceOverlay(
            engine: engine,
            mode: configuration.mode,
            showsDiagnostics: $showsDiagnostics,
            onRetry: { Task { await engine.requestLocalization() } },
            onCapture: { Task { await captureScreenshot() } },
            onExit: {
                engine.teardown()
                onExit()
            }
        )
    }

    private var unsupportedDevice: some View {
        VStack(spacing: MSSpacing.lg) {
            StateArtView(.experienceEnded, size: 96, tint: MSColor.AR.text)
            Text("This device doesn't support ARKit")
                .font(MSFont.title)
                .foregroundStyle(MSColor.AR.text)
            Text("AR positioning needs ARKit, which this device doesn't provide.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.textDim)
                .multilineTextAlignment(.center)
            Button("Close", action: onExit).msButton(.secondary, fullWidth: false)
        }
        .padding(MSSpacing.xl)
    }

    private var cameraDenied: some View {
        VStack(spacing: MSSpacing.lg) {
            StateArtView(.experienceEnded, size: 96, tint: MSColor.AR.text)
            Text("Camera access is off")
                .font(MSFont.title)
                .foregroundStyle(MSColor.AR.text)
            Text(MultiSetError.cameraAccessDenied.errorDescription ?? "")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.textDim)
                .multilineTextAlignment(.center)
            VStack(spacing: MSSpacing.sm) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .msButton(.primary, fullWidth: false)
                Button("Close", action: onExit).msButton(.tertiary, fullWidth: false)
            }
        }
        .padding(MSSpacing.xl)
    }

    // MARK: - Lifecycle

    private func startSession() async {
        await host.requestCameraAccess()
        guard !host.cameraAccessDenied, ARSceneHost.isSupported else { return }
        host.start()

        let providers = providerFactory(host)
        let created = LocalizationEngine(
            configuration: configuration,
            provider: providers.provider,
            objectProvider: providers.objects,
            frames: host.frameSource
        )
        engine = created
        await created.start()
    }

    private func captureScreenshot() async {
        guard let image = await host.snapshot() else {
            toast = MSToast(message: "Couldn't capture the view.", tone: .failure)
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            toast = MSToast(message: "Photo access is off, so the shot wasn't saved.", tone: .failure)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            toast = MSToast(message: "Saved to Photos", tone: .success)
        } catch {
            toast = MSToast(message: "Couldn't save the shot: \(error.localizedDescription)", tone: .failure)
        }
    }
}
