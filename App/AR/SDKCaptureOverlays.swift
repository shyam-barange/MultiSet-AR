import MultiSetUI
import SwiftUI

/// Shown while the SDK captures frames. The scanning animation is the SDK demo's
/// own — it tells the user to keep moving the device, which is what multi-frame
/// capture needs and what a static spinner fails to convey.
struct FrameCaptureOverlay: View {
    let statusText: String

    @State private var phoneOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack(spacing: MSSpacing.xl) {
                ZStack {
                    if let background = SDKImage.arBackground.image {
                        background
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 100)
                    }
                    if let phone = SDKImage.phone.image {
                        phone
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 58, height: 77)
                            .offset(x: phoneOffset)
                    }
                }
                .frame(width: 200, height: 100)
                .accessibilityHidden(true)

                VStack(spacing: MSSpacing.sm) {
                    Text("Hold steady and scan your surroundings")
                        .font(MSFont.headline)
                        .foregroundStyle(MSColor.AR.text)
                        .multilineTextAlignment(.center)
                    Text(statusText)
                        .font(MSFont.mono)
                        .foregroundStyle(MSColor.AR.textDim)
                }
            }
            .padding(MSSpacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capturing frames. \(statusText)")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                phoneOffset = 60
            }
        }
    }
}

/// Shown while the request is in flight, after capture has finished.
struct ServerWaitOverlay: View {
    var statusText = "Matching against the map…"

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: MSSpacing.lg) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(MSColor.AR.accent)
                    .scaleEffect(1.5)
                Text(statusText)
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.AR.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }
}

/// The SDK demo's shutter. Kept rather than replaced with an SF Symbol because it
/// is the affordance developers already recognise from the sample app, and it
/// carries the brand violet.
struct CaptureButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let image = SDKImage.captureButton.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "viewfinder.circle.fill")
                        .resizable()
                        .foregroundStyle(MSColor.accent)
                }
            }
            .frame(width: 72, height: 72)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Capture and localize")
        .accessibilityHint(isEnabled ? "" : "Waiting for AR tracking to stabilise")
    }
}

#Preview("Frame capture") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        FrameCaptureOverlay(statusText: "Frame 2 of 4")
    }
    .ignoresSafeArea()
}

#Preview("Server wait") {
    ServerWaitOverlay()
}
