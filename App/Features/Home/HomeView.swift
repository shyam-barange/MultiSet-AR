import MultiSetKit
import MultiSetUI
import SwiftUI

/// Useful with no account. Gating demo content behind sign-in is a Guideline
/// 5.1.1 problem, and it also makes the app pointless to a first-time visitor.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsScanner = false
    @State private var showsCodeEntry = false
    @State private var showsSignIn = false
    @State private var manifest: ExperienceManifest?
    @State private var resolving = false
    @State private var resolveError: MultiSetError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSSpacing.xl) {
                    header
                    primaryActions
                    demoSection
                    if !model.isSignedIn {
                        signInPrompt
                    }
                    footer
                }
                .padding(MSSpacing.lg)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("MultiSet AR")
            .sheet(isPresented: $showsScanner) {
                QRScannerSheet { code in
                    showsScanner = false
                    Task { await resolve(spaceCode: code) }
                }
            }
            .sheet(isPresented: $showsCodeEntry) {
                CodeEntrySheet { code in
                    showsCodeEntry = false
                    Task { await resolve(spaceCode: code) }
                }
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
            .fullScreenCover(item: $manifest) { manifest in
                ExperienceRunner(manifest: manifest) { self.manifest = nil }
            }
            .alert(
                "Couldn't open that experience",
                isPresented: .init(
                    get: { resolveError != nil },
                    set: { if !$0 { resolveError = nil } }
                )
            ) {
                Button("OK") { resolveError = nil }
            } message: {
                Text(resolveError?.errorDescription ?? "")
            }
            .onChange(of: model.pendingDestination) { _ in handlePendingDestination() }
            .task { handlePendingDestination() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MSSpacing.sm) {
            Text("Spatial ground truth, in your hand")
                .font(MSFont.display)
                .foregroundStyle(MSColor.textPrimary)
            Text("Open a hosted experience, or try one of the demos — no account needed.")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: MSSpacing.md) {
            actionCard(
                symbol: "qrcode.viewfinder",
                title: "Scan a code",
                subtitle: "Open any hosted MultiSet experience"
            ) { showsScanner = true }

            actionCard(
                symbol: "keyboard",
                title: "Enter a code",
                subtitle: "When the camera can't reach the printed code"
            ) { showsCodeEntry = true }
        }
        .overlay {
            if resolving {
                ProgressView()
                    .padding(MSSpacing.lg)
                    .background(MSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MSRadius.md))
            }
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader(
                "Try it here",
                subtitle: "These run without a mapped site or a network connection."
            )
            ForEach(DemoKind.allCases) { demo in
                NavigationLink {
                    DemoRunnerView(demo: demo)
                } label: {
                    demoRow(demo)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func demoRow(_ demo: DemoKind) -> some View {
        MSCard {
            HStack(spacing: MSSpacing.md) {
                Image(systemName: demo.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MSColor.accent)
                    .frame(width: MSSize.iconLg)
                VStack(alignment: .leading, spacing: 2) {
                    Text(demo.title)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                    Text(demo.subtitle)
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSColor.textMuted)
            }
        }
    }

    private var signInPrompt: some View {
        MSCard {
            VStack(alignment: .leading, spacing: MSSpacing.md) {
                Text("Have a MultiSet account?")
                    .font(MSFont.headline)
                    .foregroundStyle(MSColor.textPrimary)
                Text("Sign in to browse your maps and tracked objects, test localization on site, and publish experiences.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in") { showsSignIn = true }
                    .msButton(.primary, fullWidth: false)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: MSSpacing.xs) {
            Text(CompanyInfo.copyright)
                .font(MSFont.monoSmall)
                .foregroundStyle(MSColor.textMuted)
        }
        .padding(.top, MSSpacing.lg)
    }

    private func actionCard(
        symbol: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MSCard {
                HStack(spacing: MSSpacing.md) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(MSColor.accent)
                        .frame(width: MSSize.iconLg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(MSFont.headline)
                            .foregroundStyle(MSColor.textPrimary)
                        Text(subtitle)
                            .font(MSFont.caption)
                            .foregroundStyle(MSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    // MARK: - Actions

    private func handlePendingDestination() {
        guard let destination = model.pendingDestination else { return }
        switch destination {
        case .experience(let spaceCode, _):
            _ = model.consumePendingDestination()
            Task { await resolve(spaceCode: spaceCode) }
        case .signIn:
            _ = model.consumePendingDestination()
            showsSignIn = true
        default:
            break
        }
    }

    private func resolve(spaceCode: String) async {
        resolving = true
        defer { resolving = false }
        do {
            manifest = try await model.api.resolveExperience(spaceCode: spaceCode)
        } catch {
            resolveError = error.asMultiSetError
        }
    }
}

extension Error {
    var asMultiSetError: MultiSetError {
        if let known = self as? MultiSetError { return known }
        if let urlError = self as? URLError {
            return .network(code: urlError.code, description: urlError.localizedDescription)
        }
        return .server(status: -1, message: localizedDescription)
    }
}

#Preview("Signed out") {
    HomeView().environmentObject(AppModel.preview(session: .signedOut))
}

#Preview("Signed in") {
    HomeView().environmentObject(AppModel.preview())
}
