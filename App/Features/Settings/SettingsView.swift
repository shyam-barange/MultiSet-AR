import AVFoundation
import CoreLocation
import MultiSetARCore
import MultiSetKit
import MultiSetSDK
import MultiSetUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var showsSignIn = false
    @State private var showsSignOutConfirmation = false
    @State private var plan: PlanDetails?
    @State private var sdkCredentials: M2MCredentials?
    @State private var showsCredentialEntry = false
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            List {
                accountSection
                if model.isSignedIn {
                    sdkCredentialsSection
                }
                if let warning = model.secretStorageWarning {
                    warningSection(warning)
                }
                if plan != nil {
                    planSection
                }
                permissionsSection
                if isDebugBuild {
                    environmentSection
                }
                aboutSection
                legalSection
                footerSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(isPresented: $showsSignIn) { SignInView() }
            .confirmationDialog(
                "Sign out?",
                isPresented: $showsSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your credentials are removed from this device's keychain, along with everything cached from your account.")
            }
            .sheet(isPresented: $showsCredentialEntry) {
                SDKCredentialsSheet { credentials in
                    sdkCredentials = credentials
                }
            }
            .task {
                await loadPlan()
                sdkCredentials = await model.auth.storedMachineCredentials
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if let profile = model.session.profile {
                VStack(alignment: .leading, spacing: MSSpacing.xxs) {
                    Text(profile.displayName)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                    if let email = profile.email {
                        Text(email)
                            .font(MSFont.caption)
                            .foregroundStyle(MSColor.textSecondary)
                    }
                    if let company = profile.companyName {
                        Text(company)
                            .font(MSFont.caption)
                            .foregroundStyle(MSColor.textMuted)
                    }
                }
                .padding(.vertical, MSSpacing.xxs)

                Button("Sign out", role: .destructive) { showsSignOutConfirmation = true }
            } else {
                Button("Sign in") { showsSignIn = true }
                Text("You can browse demos and open hosted experiences without an account.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textMuted)
            }
        }
    }

    /// The AR test screens run the MultiSet SDK, which authenticates with its own
    /// client ID and secret rather than the signed-in user's token. Showing the state
    /// here means it can be fixed before a session fails rather than during one.
    @ViewBuilder
    private var sdkCredentialsSection: some View {
        Section {
            if let sdkCredentials {
                MSMonoValue("CLIENT ID", Self.masked(sdkCredentials.clientId))
                MSStatusPill("Ready", tone: .positive, systemImage: "checkmark.circle.fill")
                Button("Replace credentials") { showsCredentialEntry = true }
            } else {
                Text("Not set up yet")
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                Button("Create automatically") {
                    Task {
                        let failure = await model.ensureSDKCredentials()
                        sdkCredentials = await model.auth.storedMachineCredentials
                        if let failure {
                            model.toast = MSToast(
                                message: failure.errorDescription ?? "Couldn't create credentials.",
                                tone: .failure
                            )
                        }
                    }
                }
                Button("Enter manually") { showsCredentialEntry = true }
            }
        } header: {
            Text("SDK credentials")
        } footer: {
            Text("Testing localization and object tracking runs the MultiSet SDK, which needs its own client ID and secret. The app creates one for you; enter a pair from the developer portal if that isn't possible on your account.")
        }
    }

    /// Enough to recognise which pair is in use without printing it in full.
    static func masked(_ value: String) -> String {
        guard value.count > 10 else { return value }
        return "\(value.prefix(8))…\(value.suffix(4))"
    }

    private func warningSection(_ warning: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: MSSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MSColor.warning)
                Text(warning)
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Credential storage")
        }
    }

    @ViewBuilder
    private var planSection: some View {
        Section("Plan") {
            if let plan {
                if let calls = plan.apiCalls {
                    MSMonoValue("API CALLS", "\(calls)")
                }
                if let storage = plan.storage {
                    MSMonoValue("STORAGE", "\(Int(storage)) MB")
                }
                if let maps = plan.mapsCount {
                    MSMonoValue("MAP LIMIT", "\(maps)")
                }
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            HStack {
                Text("Camera")
                Spacer()
                MSStatusPill(
                    cameraStatusLabel,
                    tone: cameraStatus == .authorized ? .positive : .caution
                )
            }
            Button("Open system settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Localization needs the camera. Location is optional and only narrows which mapped area you're in.")
        }
    }

    private var environmentSection: some View {
        Section {
            Picker("Environment", selection: Binding(
                get: { model.environment },
                set: { environment in Task { await model.switch_(to: environment) } }
            )) {
                ForEach(APIEnvironment.all) { environment in
                    Text(environment.displayName).tag(environment)
                }
            }
            MSMonoValue("BASE URL", model.environment.baseURL.absoluteString)
        } header: {
            Text("Environment")
        } footer: {
            Text("Debug builds only. Switching signs you out.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            MSMonoValue("APP", "\(Self.appVersion) (\(Self.buildNumber))")
            MSMonoValue("SDK", MultiSet.version)
            Button("Documentation") { openURL(ExternalLink.docs) }
            Button("Service status") { openURL(ExternalLink.status) }
            Button("Contact \(CompanyInfo.contactEmail)") { openURL(ExternalLink.contactEmail) }
        }
    }

    private var legalSection: some View {
        Section {
            Button("Privacy policy") { openURL(ExternalLink.privacyPolicy) }
            Button("Terms of use") { openURL(ExternalLink.termsOfUse) }
            Button("Report a hosted experience") {
                openURL(ExperienceIntroCard.reportURL(spaceCode: "—"))
            }
        } header: {
            Text("Legal")
        } footer: {
            Text("Experiences opened in this app are published by third parties. Report anything that shouldn't be there and it can be disabled server-side.")
        }
    }

    private var footerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MSSpacing.xs) {
                Text(CompanyInfo.copyright)
                Text(CompanyInfo.address)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(MSFont.monoSmall)
            .foregroundStyle(MSColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Values

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private var cameraStatusLabel: String {
        switch cameraStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked"
        @unknown default: "Unknown"
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private func loadPlan() async {
        guard model.isSignedIn else { return }
        plan = try? await model.api.planDetails()
    }
}

#Preview("Signed in") {
    SettingsView().environmentObject(AppModel.preview())
}

#Preview("Signed out") {
    SettingsView().environmentObject(AppModel.preview(session: .signedOut))
}
