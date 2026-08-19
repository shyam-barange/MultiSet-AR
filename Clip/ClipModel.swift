import ARKit
import MultiSetARCore
import MultiSetKit
import SwiftUI

/// Resolves an invocation URL into a runnable experience.
@MainActor
final class ClipModel: ObservableObject {
    enum State: Equatable {
        case awaitingInvocation
        case resolving
        case ready(ExperienceManifest)
        case running(ExperienceManifest)
        case finished(ExperienceManifest)
        case failed(MultiSetError)
    }

    @Published private(set) var state: State = .awaitingInvocation

    private let router = DeepLinkRouter()
    private let auth: AuthStore
    private let api: any MultiSetAPI
    private var lastSpaceCode: String?
    private var modeOverride: ExperienceMode?

    init(environment: APIEnvironment = .production, api: (any MultiSetAPI)? = nil, auth: AuthStore? = nil) {
        let store = auth ?? AuthStore(environment: environment)
        self.auth = store
        self.api = api ?? LiveMultiSetAPI(environment: environment, auth: store)
    }

    static func preview(state: State) -> ClipModel {
        let model = ClipModel(api: MockMultiSetAPI(behaviour: .instant), auth: AuthStore(secrets: InMemorySecretStore()))
        model.state = state
        return model
    }

    var experienceAPI: any MultiSetAPI { api }

    func handle(url: URL) async {
        guard case .experience(let spaceCode, let override) = router.destination(for: url) else {
            state = .failed(.experienceUnavailable(.unknownCode))
            return
        }
        modeOverride = override
        await resolve(spaceCode: spaceCode)
    }

    func rejectMissingInvocation() {
        state = .failed(.experienceUnavailable(.unknownCode))
    }

    func resolve(spaceCode: String) async {
        lastSpaceCode = spaceCode
        state = .resolving
        guard ARSceneHostSupport.isARSupported else {
            state = .failed(.experienceUnavailable(.deviceUnsupported))
            return
        }
        do {
            state = .ready(try await api.resolveExperience(spaceCode: spaceCode))
        } catch {
            state = .failed(error.asClipError)
        }
    }

    func retry() async {
        guard let lastSpaceCode else {
            state = .failed(.experienceUnavailable(.unknownCode))
            return
        }
        await resolve(spaceCode: lastSpaceCode)
    }

    func start() {
        guard case .ready(let manifest) = state else { return }
        state = .running(manifest)
    }

    func finish() {
        if case .running(let manifest) = state {
            state = .finished(manifest)
        }
    }

    var configuration: ExperienceConfiguration? {
        guard case .running(let manifest) = state else { return nil }
        return ExperienceConfiguration(manifest: manifest, modeOverride: modeOverride)
    }
}

private extension Error {
    /// A session that expired mid-use should look like a retry, not a dead end.
    var asClipError: MultiSetError {
        if let known = self as? MultiSetError {
            if case .unauthorized = known {
                return .experienceUnavailable(.expired)
            }
            return known
        }
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            default:
                return .network(code: urlError.code, description: urlError.localizedDescription)
            }
        }
        return .server(status: -1, message: localizedDescription)
    }
}

enum ARSceneHostSupport {
    static var isARSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }
}
