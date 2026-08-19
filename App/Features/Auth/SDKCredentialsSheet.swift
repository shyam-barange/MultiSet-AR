import MultiSetKit
import MultiSetUI
import SwiftUI

/// Manual entry for an SDK client ID and secret.
///
/// The app normally creates these itself after sign-in, but that can fail — an
/// account whose plan does not allow it, for instance. This is the way back in:
/// developers already have a pair from the portal, and the SDK cannot run without
/// one because `MultiSetConfig` accepts no other form of credential.
///
/// Entry is validated by actually exchanging the pair for a token, so a typo is
/// caught here rather than surfacing later as a failed AR session.
struct SDKCredentialsSheet: View {
    let onStored: (M2MCredentials) -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var revealsSecret = false
    @State private var isValidating = false
    @State private var error: MultiSetError?
    @State private var showsScanner = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case id, secret }

    private var trimmedId: String { clientId.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSecret: String { clientSecret.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        !isValidating && !trimmedId.isEmpty && !trimmedSecret.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSSpacing.xl) {
                    explanation
                    fields
                    if let error {
                        errorBanner(error)
                    }
                    Button("Verify and save", action: submit)
                        .msButton()
                        .disabled(!canSubmit)
                        .overlay { if isValidating { ProgressView().tint(MSColor.onAccent) } }
                    keychainNote
                    portalLink
                }
                .padding(MSSpacing.lg)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("SDK credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel("Scan credentials")
                }
            }
            .sheet(isPresented: $showsScanner) {
                CredentialScannerSheet { id, secret in
                    clientId = id
                    clientSecret = secret
                    showsScanner = false
                }
            }
            .task { focus = .id }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: MSSpacing.sm) {
            Text("Paste a pair from the developer portal")
                .font(MSFont.title)
                .foregroundStyle(MSColor.textPrimary)
            Text("The MultiSet SDK authenticates with a client ID and secret. The app usually creates one for you after sign-in — this is for when it can't.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: MSSpacing.lg) {
            field("Client ID") {
                TextField("f423e6cd-1fd3-42f0-…", text: $clientId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(MSFont.mono)
                    .focused($focus, equals: .id)
                    .submitLabel(.next)
                    .onSubmit { focus = .secret }
            }
            field("Client secret") {
                HStack(spacing: MSSpacing.sm) {
                    Group {
                        if revealsSecret {
                            TextField("Client secret", text: $clientSecret)
                        } else {
                            SecureField("Client secret", text: $clientSecret)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(MSFont.mono)
                    .focused($focus, equals: .secret)
                    .submitLabel(.go)
                    .onSubmit(submit)

                    Button {
                        revealsSecret.toggle()
                    } label: {
                        Image(systemName: revealsSecret ? "eye.slash" : "eye")
                            .foregroundStyle(MSColor.textMuted)
                            .frame(width: MSSize.minTouchTarget, height: MSSize.minTouchTarget)
                    }
                    .accessibilityLabel(revealsSecret ? "Hide secret" : "Show secret")
                }
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.xs) {
            Text(title)
                .font(MSFont.captionEmphasis)
                .foregroundStyle(MSColor.textSecondary)
            content()
                .padding(MSSpacing.md)
                .background(MSColor.surface, in: RoundedRectangle(cornerRadius: MSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: MSRadius.md)
                        .strokeBorder(MSColor.border, lineWidth: 1)
                )
        }
    }

    private func errorBanner(_ error: MultiSetError) -> some View {
        HStack(alignment: .top, spacing: MSSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MSColor.danger)
            Text(error.errorDescription ?? "")
                .font(MSFont.caption)
                .foregroundStyle(MSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSSpacing.md)
        .background(MSColor.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: MSRadius.md))
    }

    private var keychainNote: some View {
        Text("Stored in this device's keychain and sent only to MultiSet to authenticate the SDK.")
            .font(MSFont.caption)
            .foregroundStyle(MSColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var portalLink: some View {
        Button {
            openURL(ExternalLink.credentials)
        } label: {
            HStack(spacing: MSSpacing.xs) {
                Text("Get your credentials")
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
            }
            .font(MSFont.bodyEmphasis)
            .foregroundStyle(MSColor.accent)
            .frame(minHeight: MSSize.minTouchTarget)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        error = nil
        isValidating = true
        Task {
            defer { isValidating = false }
            let credentials = M2MCredentials(clientId: trimmedId, clientSecret: trimmedSecret)
            do {
                // Exchanging the pair for a token is the only real validation: it
                // proves the credentials work before an AR session depends on them.
                _ = try await model.auth.activateMachineCredentials(credentials)
                onStored(credentials)
                dismiss()
            } catch let failure {
                error = failure.asMultiSetError
            }
        }
    }
}

/// Scans a credential pair off the developer portal, so nobody types forty
/// characters of secret on glass.
struct CredentialScannerSheet: View {
    let onPair: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rejection: String?

    var body: some View {
        NavigationStack {
            QRScannerSheet { payload in
                guard let pair = M2MCredentials.parse(scannedPayload: payload) else {
                    rejection = "That code doesn't carry a client ID and secret."
                    return
                }
                onPair(pair.clientId, pair.clientSecret)
            }
            .overlay(alignment: .bottom) {
                if let rejection {
                    Text(rejection)
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.AR.bad)
                        .padding(MSSpacing.md)
                        .background(MSColor.AR.panel, in: Capsule())
                        .padding(.bottom, MSSpacing.xxl)
                }
            }
        }
    }

}

#Preview {
    SDKCredentialsSheet { _ in }
        .environmentObject(AppModel.preview())
}
