import MultiSetKit
import MultiSetUI
import SwiftUI

/// Sign-in uses the same credentials as the MultiSet dashboard.
///
/// Not the SDK's clientId/clientSecret pair: those authorise only code-addressed
/// endpoints, so the Maps and Objects library — which needs the list endpoints —
/// could not work. After signing in, the app mints M2M credentials for the SDK
/// itself, so nobody types a forty-character secret on glass.
struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var password = ""
    @State private var revealsPassword = false
    @State private var isSubmitting = false
    @State private var error: MultiSetError?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case email, password }

    private var canSubmit: Bool {
        !isSubmitting
            && email.contains("@")
            && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSSpacing.xl) {
                    header
                    form
                    if let error {
                        errorBanner(error)
                    }
                    Button("Sign in", action: submit)
                        .msButton()
                        .disabled(!canSubmit)
                        .overlay {
                            if isSubmitting {
                                ProgressView().tint(MSColor.onAccent)
                            }
                        }
                    keychainNote
                    credentialsLink
                }
                .padding(MSSpacing.lg)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { focus = .email }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MSSpacing.sm) {
            Text("Use your MultiSet account")
                .font(MSFont.title)
                .foregroundStyle(MSColor.textPrimary)
            Text("The same email and password as the developer portal.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: MSSpacing.lg) {
            field(title: "Email") {
                TextField("you@company.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }

            field(title: "Password") {
                HStack(spacing: MSSpacing.sm) {
                    Group {
                        if revealsPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)

                    Button {
                        revealsPassword.toggle()
                    } label: {
                        Image(systemName: revealsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(MSColor.textMuted)
                            .frame(width: MSSize.minTouchTarget, height: MSSize.minTouchTarget)
                    }
                    .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                }
            }
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.xs) {
            Text(title)
                .font(MSFont.captionEmphasis)
                .foregroundStyle(MSColor.textSecondary)
            content()
                .font(MSFont.body)
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
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MSColor.danger)
            Text(error.errorDescription ?? "")
                .font(MSFont.caption)
                .foregroundStyle(MSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(MSSpacing.md)
        .background(MSColor.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: MSRadius.md))
        .accessibilityElement(children: .combine)
    }

    private var keychainNote: some View {
        Text("Your credentials are stored in this device's keychain and used only to reach your own MultiSet account. They never leave the device except to sign in.")
            .font(MSFont.caption)
            .foregroundStyle(MSColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var credentialsLink: some View {
        Button {
            openURL(ExternalLink.credentials)
        } label: {
            HStack(spacing: MSSpacing.xs) {
                Text("Get your credentials")
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(MSFont.bodyEmphasis)
            .foregroundStyle(MSColor.accent)
            .frame(minHeight: MSSize.minTouchTarget)
        }
        .accessibilityHint("Opens the MultiSet developer portal")
    }

    private func submit() {
        guard canSubmit else { return }
        error = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await model.signIn(email: email, password: password)
                dismiss()
            } catch let failure {
                error = failure.asMultiSetError
            }
        }
    }
}

#Preview {
    SignInView().environmentObject(AppModel.preview(session: .signedOut))
}
