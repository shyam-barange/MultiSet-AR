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
                LazyVStack(alignment: .leading, spacing: MSSpacing.xxl) {
                    hero
                    startSection
                    demoSection
                    if model.isSignedIn {
                        workspaceSection
                    } else {
                        signInPrompt
                    }
                    footer
                }
                .padding(.horizontal, MSSpacing.lg)
                .padding(.top, MSSpacing.sm)
                .padding(.bottom, MSSpacing.xxl)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
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

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroArtwork

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.18), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: MSSpacing.md) {
                Label("SPATIAL INTELLIGENCE", systemImage: "scope")
                    .font(MSFont.monoSmall.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, MSSpacing.sm)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                Spacer(minLength: MSSpacing.xxl)

                Text("Know exactly\nwhere you are.")
                    .font(MSFont.display)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Open a mapped space and let MultiSet turn the camera into precise, persistent position.")
                    .font(MSFont.callout)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MSSpacing.sm) {
                    heroFact("5 cm", label: "precision")
                    heroFact("3", label: "offline demos")
                }
            }
            .padding(MSSpacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 390, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.xl)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: MSColor.accent.opacity(0.16), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        if let image = HomeImage.spatialHero.image {
            GeometryReader { proxy in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [MSColor.accent, Color.black],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    private func heroFact(_ value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(value).font(MSFont.monoSmall.weight(.bold))
            Text(label).font(MSFont.caption)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, MSSpacing.sm)
        .padding(.vertical, 7)
        .background(.black.opacity(0.3), in: Capsule())
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader(
                "Start an experience",
                subtitle: "Scan the code at a venue or enter its space code."
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: MSSpacing.md) { startActions }
                VStack(spacing: MSSpacing.md) { startActions }
            }
            .buttonStyle(.plain)
            .disabled(resolving)
            .overlay {
                if resolving {
                    ProgressView("Opening")
                        .font(MSFont.captionEmphasis)
                        .padding(.horizontal, MSSpacing.lg)
                        .padding(.vertical, MSSpacing.md)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 12)
                }
            }
        }
    }

    @ViewBuilder
    private var startActions: some View {
        Button { showsScanner = true } label: {
            actionLabel(
                symbol: "qrcode.viewfinder",
                title: "Scan code",
                subtitle: "Use camera",
                artwork: .scanCode,
                primary: true
            )
        }

        Button { showsCodeEntry = true } label: {
            actionLabel(
                symbol: "keyboard",
                title: "Enter code",
                subtitle: "Type instead",
                artwork: .enterCode,
                primary: false
            )
        }
    }

    private func actionLabel(
        symbol: String,
        title: String,
        subtitle: String,
        artwork: HomeImage,
        primary: Bool
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            cardArtwork(artwork, fallback: primary ? MSColor.accent : MSColor.surfaceSunken)

            LinearGradient(
                colors: [.black.opacity(0.82), .black.opacity(0.54), .black.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: MSSpacing.md) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.26), in: Circle())
                }

                Spacer(minLength: MSSpacing.sm)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MSFont.headline)
                    Text(subtitle).font(MSFont.caption).opacity(0.76)
                }
            }
            .padding(MSSpacing.lg)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.lg)
                .strokeBorder(
                    primary ? MSColor.accent.opacity(0.72) : Color.white.opacity(0.13),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
        .shadow(color: primary ? MSColor.accent.opacity(0.14) : .clear, radius: 14, y: 7)
        .contentShape(Rectangle())
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader(
                "Explore without a map",
                subtitle: "Real AR workflows that run offline, wherever you are."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: MSSpacing.md) {
                    ForEach(DemoKind.allCases) { demo in
                        NavigationLink {
                            DemoRunnerView(demo: demo)
                        } label: {
                            demoCard(demo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func demoCard(_ demo: DemoKind) -> some View {
        ZStack(alignment: .bottomLeading) {
            cardArtwork(demo.artwork, fallback: demo.tint)

            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.24), .black.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: MSSpacing.sm) {
                HStack {
                    Image(systemName: demo.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.25), in: Circle())
                }

                Spacer(minLength: MSSpacing.xl)

                Text(demo.eyebrow.uppercased())
                    .font(MSFont.monoSmall.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(demo.tint)

                Text(demo.title)
                    .font(MSFont.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(demo.shortSubtitle)
                    .font(MSFont.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                HStack {
                    Text("Try demo")
                        .font(MSFont.captionEmphasis)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.top, MSSpacing.xs)
            }
            .padding(MSSpacing.lg)
        }
        .frame(width: 236, height: 336)
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.lg)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
        .shadow(color: demo.tint.opacity(0.12), radius: 12, y: 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cardArtwork(_ artwork: HomeImage, fallback: Color) -> some View {
        if let image = artwork.image {
            GeometryReader { proxy in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [fallback, Color.black],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Your workspace", subtitle: "Pick up where you left off.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MSSpacing.md) { workspaceActions }
                VStack(spacing: MSSpacing.md) { workspaceActions }
            }
        }
    }

    @ViewBuilder
    private var workspaceActions: some View {
        workspaceButton(
            symbol: "square.stack.3d.up",
            title: "Library",
            subtitle: "Maps & objects",
            tab: .library
        )
        workspaceButton(
            symbol: "qrcode",
            title: "Publish",
            subtitle: "Share an experience",
            tab: .publish
        )
    }

    private func workspaceButton(
        symbol: String,
        title: String,
        subtitle: String,
        tab: RootTab
    ) -> some View {
        Button { model.selectedTab = tab } label: {
            VStack(alignment: .leading, spacing: MSSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(MSColor.accent)
                Text(title)
                    .font(MSFont.bodyEmphasis)
                    .foregroundStyle(MSColor.textPrimary)
                Text(subtitle)
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
                    .lineLimit(2)
            }
            .padding(MSSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            .background(MSColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: MSRadius.lg)
                    .strokeBorder(MSColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
        }
        .buttonStyle(.plain)
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            HStack(alignment: .top, spacing: MSSpacing.md) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(MSColor.accent)
                VStack(alignment: .leading, spacing: MSSpacing.xs) {
                    Text("Bring your workspace with you")
                        .font(MSFont.headline)
                        .foregroundStyle(MSColor.textPrimary)
                    Text("Sign in to browse maps, test localization on site, and publish experiences.")
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Sign in to MultiSet") { showsSignIn = true }
                .msButton(.primary, fullWidth: false)
        }
        .padding(MSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MSColor.accentSoft)
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.lg)
                .strokeBorder(MSColor.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
    }

    private var footer: some View {
        Text(CompanyInfo.copyright)
            .font(MSFont.monoSmall)
            .foregroundStyle(MSColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, MSSpacing.sm)
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

private extension DemoKind {
    var artwork: HomeImage {
        switch self {
        case .objectTracking: .objectTracking
        case .syntheticNavigation: .navigation
        case .simulatedLocalization: .localization
        }
    }

    var eyebrow: String {
        switch self {
        case .objectTracking: "Object tracking"
        case .syntheticNavigation: "Navigation"
        case .simulatedLocalization: "Localization"
        }
    }

    var shortSubtitle: String {
        switch self {
        case .objectTracking: "Lock a virtual object to a printed target."
        case .syntheticNavigation: "Follow a rendered path around the room."
        case .simulatedLocalization: "Replay a walk through the VPS pipeline."
        }
    }

    var tint: Color {
        switch self {
        case .objectTracking: MSColor.accent
        case .syntheticNavigation: MSColor.info
        case .simulatedLocalization: MSColor.success
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
