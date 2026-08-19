import AVFoundation
import MultiSetKit
import MultiSetUI
import SwiftUI

/// Scans a MultiSet experience code. Only URLs the shared `DeepLinkRouter`
/// recognises are accepted, so the scanner cannot be used to open arbitrary
/// links.
struct QRScannerSheet: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var permissionDenied = false
    @State private var lastRejection: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if permissionDenied {
                    permissionMessage
                } else {
                    CameraCodeScanner(
                        onPayload: handle(payload:),
                        onPermissionDenied: { permissionDenied = true }
                    )
                    .ignoresSafeArea()
                    reticle
                }
            }
            .background(Color.black)
            .navigationTitle("Scan a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var reticle: some View {
        VStack(spacing: MSSpacing.lg) {
            Spacer()
            RoundedRectangle(cornerRadius: MSRadius.lg)
                .strokeBorder(MSColor.AR.text.opacity(0.85), lineWidth: 2)
                .frame(width: 240, height: 240)
            Text(lastRejection ?? "Point the camera at a MultiSet code")
                .font(MSFont.callout)
                .foregroundStyle(lastRejection == nil ? MSColor.AR.text : MSColor.AR.bad)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MSSpacing.xl)
            Spacer()
        }
    }

    private var permissionMessage: some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(.invalidated, size: 88).colorScheme(.dark)
            Text("Camera access is off")
                .font(MSFont.title)
                .foregroundStyle(MSColor.AR.text)
            Text("Scanning needs the camera. You can also enter the code by hand.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.AR.textDim)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .msButton(.primary, fullWidth: false)
        }
        .padding(MSSpacing.xl)
    }

    private func handle(payload: String) {
        let router = DeepLinkRouter()
        if let url = URL(string: payload),
           case .experience(let code, _)? = router.destination(for: url) {
            onCode(code)
            return
        }
        // A bare code is also acceptable — some venues print the code, not a URL.
        if router.validated(payload) != nil, !payload.contains("/") {
            onCode(payload)
            return
        }
        lastRejection = "That code isn't a MultiSet experience."
    }
}

private struct CameraCodeScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void
    let onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onPayload = onPayload
        controller.onPermissionDenied = onPermissionDenied
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onPayload: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// One payload per presentation. A QR sits in frame for many samples, and
    /// re-firing would push the same experience repeatedly.
    private var hasDelivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { await configure() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                onPermissionDenied?()
                return
            }
        } else if status != .authorized {
            onPermissionDenied?()
            return
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }

        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        // startRunning() blocks briefly. Running it as a detached task keeps the
        // main actor responsive without capturing the non-Sendable session across
        // an isolation boundary.
        let runner = SessionStarter(session: session)
        await runner.start()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDelivered,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = object.stringValue
        else { return }
        hasDelivered = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onPayload?(payload)
    }
}

/// Confines the non-Sendable `AVCaptureSession` to one actor so starting it off
/// the main thread does not cross an isolation boundary with a shared reference.
private actor SessionStarter {
    private let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }

    func start() {
        session.startRunning()
    }
}

/// Manual entry, for when a camera can't reach the printed code.
struct CodeEntrySheet: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        DeepLinkRouter().validated(trimmed) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: MSSpacing.lg) {
                Text("Enter the code printed beneath the QR, or paste the full link.")
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)

                TextField("k7m2p9xq", text: $text)
                    .font(MSFont.monoLarge)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.go)
                    .focused($isFocused)
                    .padding(MSSpacing.md)
                    .background(MSColor.surfaceSunken, in: RoundedRectangle(cornerRadius: MSRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSRadius.md)
                            .strokeBorder(isFocused ? MSColor.accent : MSColor.border, lineWidth: 1.5)
                    )
                    .onSubmit(submit)

                Button("Open", action: submit)
                    .msButton()
                    .disabled(!isValid)

                Spacer()
            }
            .padding(MSSpacing.lg)
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Enter a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { isFocused = true }
        }
    }

    private func submit() {
        // Accept a pasted link as readily as a bare code — people paste links.
        if let url = URL(string: trimmed),
           case .experience(let code, _)? = DeepLinkRouter().destination(for: url) {
            onCode(code)
            return
        }
        guard isValid else { return }
        onCode(trimmed)
    }
}

#Preview("Code entry") {
    CodeEntrySheet { _ in }
}
