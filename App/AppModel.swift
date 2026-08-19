import Combine
import MultiSetKit
import MultiSetUI
import SwiftUI

/// Root state: who is signed in, which API to talk to, and where a deep link
/// should land.
@MainActor
final class AppModel: ObservableObject {
    enum Session: Equatable {
        case unknown
        case signedOut
        case signedIn(UserProfile)

        var profile: UserProfile? {
            if case .signedIn(let profile) = self { return profile }
            return nil
        }
    }

    @Published var session: Session = .unknown
    @Published var environment: APIEnvironment
    @Published var toast: MSToast?
    @Published var hasCompletedOnboarding: Bool
    @Published var selectedTab: RootTab = .home
    @Published var pendingDestination: DeepLinkDestination?
    /// Set when credentials could not be written to the keychain. Surfaced in
    /// Settings rather than left silent, since the session will not survive a
    /// relaunch.
    @Published var secretStorageWarning: String?

    private(set) var auth: AuthStore
    private(set) var api: any MultiSetAPI
    private let router = DeepLinkRouter()
    private let defaults: UserDefaults

    init(
        environment: APIEnvironment = .production,
        api: (any MultiSetAPI)? = nil,
        auth: AuthStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.environment = environment
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)

        let store = auth ?? AuthStore(environment: environment)
        self.auth = store
        self.api = api ?? LiveMultiSetAPI(environment: environment, auth: store)

        #if DEBUG
        // Lets a UI check open straight onto a tab:
        //   xcrun simctl launch <device> com.multiset.sdk -MSStartTab learn
        // Debug only, so it cannot affect a shipping build.
        if let name = UserDefaults.standard.string(forKey: "MSStartTab"),
           let tab = RootTab(rawValue: name) {
            selectedTab = tab
        }
        #endif
    }

    private static let onboardingKey = "com.multiset.sdk.hasCompletedOnboarding"

    /// Previews and the demo modes run against fixtures with no network.
    static func preview(
        session: Session = .signedIn(Fixtures.profile),
        behaviour: MockMultiSetAPI.Behaviour = .instant
    ) -> AppModel {
        let model = AppModel(
            api: MockMultiSetAPI(behaviour: behaviour),
            auth: AuthStore(secrets: InMemorySecretStore()),
            defaults: UserDefaults(suiteName: "com.multiset.sdk.preview") ?? .standard
        )
        model.session = session
        model.hasCompletedOnboarding = true
        return model
    }

    var isSignedIn: Bool { session.profile != nil }

    // MARK: - Onboarding

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Self.onboardingKey)
    }

    // MARK: - Session

    func restoreSession() async {
        guard case .unknown = session else { return }
        do {
            guard try await auth.restoreSession() != nil else {
                session = .signedOut
                return
            }
            session = .signedIn(try await api.userProfile())
        } catch {
            // A failed restore is not worth interrupting launch over — the user
            // simply starts signed out and everything unauthenticated still works.
            session = .signedOut
        }
        await refreshSecretStorageWarning()
    }

    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(email: email, password: password)
        session = .signedIn(try await api.userProfile())
        await refreshSecretStorageWarning()
        await ensureSDKCredentials()
        toast = MSToast(message: "Signed in", tone: .success)
    }

    func signOut() async {
        await auth.signOut()
        session = .signedOut
        selectedTab = .home
        toast = MSToast(message: "Signed out", tone: .info)
    }

    /// Mints M2M credentials so the SDK can be initialised without the developer
    /// typing a client ID. Failure is non-fatal: the REST provider needs no
    /// credentials, so localization still works.
    func ensureSDKCredentials() async {
        if await auth.storedMachineCredentials != nil { return }
        do {
            let credentials = try await api.mintM2MCredentials(name: "MultiSet AR for iOS")
            _ = try await auth.activateMachineCredentials(credentials)
        } catch {
            secretStorageWarning = secretStorageWarning ?? """
            Couldn't create SDK credentials for this device. Localization still \
            works — it will use the REST provider instead of the SDK.
            """
        }
    }

    private func refreshSecretStorageWarning() async {
        guard let failure = await auth.secretStoreFailure else { return }
        secretStorageWarning = """
        Your credentials couldn't be saved to the device keychain, so you'll need \
        to sign in again next launch. \(failure.localizedDescription)
        """
    }

    // MARK: - Environment

    func switch_(to environment: APIEnvironment) async {
        guard environment != self.environment else { return }
        await auth.signOut()
        self.environment = environment
        let store = AuthStore(environment: environment)
        auth = store
        api = LiveMultiSetAPI(environment: environment, auth: store)
        session = .signedOut
        toast = MSToast(message: "Switched to \(environment.displayName)", tone: .info)
    }

    // MARK: - Deep links

    func handle(url: URL) {
        guard let destination = router.destination(for: url) else {
            toast = MSToast(message: "That link isn't a MultiSet experience.", tone: .failure)
            return
        }
        route(to: destination)
    }

    func route(to destination: DeepLinkDestination) {
        switch destination {
        case .experience:
            pendingDestination = destination
        case .map, .object:
            selectedTab = .library
            pendingDestination = destination
        case .demo:
            selectedTab = .home
            pendingDestination = destination
        case .signIn:
            pendingDestination = destination
        case .tab(let name):
            if let tab = RootTab(rawValue: name) {
                selectedTab = tab
            }
        }
    }

    func consumePendingDestination() -> DeepLinkDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
}

enum RootTab: String, Hashable, CaseIterable {
    case home, library, publish, learn, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .publish: "Publish"
        case .learn: "Learn"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house"
        case .library: "square.stack.3d.up"
        case .publish: "qrcode"
        case .learn: "book"
        case .settings: "gearshape"
        }
    }
}
