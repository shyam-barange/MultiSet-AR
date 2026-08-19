import MultiSetUI
import SwiftUI

/// Fetches the Learn tab's imagery on demand.
///
/// The Learn imagery is roughly two thirds of the app's compiled asset catalog and
/// nothing on first launch needs it, so it is tagged rather than shipped in the
/// initial download. Onboarding and the state art stay in the bundle: both are
/// needed immediately, possibly before there is a network.
///
/// An ODR request can fail — offline, or the tag not yet hosted — so failure is a
/// first-class state. The Learn cards fall back to text-only layout rather than
/// showing a spinner forever or an empty frame.
@MainActor
final class OnDemandResourceLoader: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(fraction: Double)
        case available
        /// Carries the reason so the UI can say what happened, not just that it did.
        case unavailable(String)

        var isAvailable: Bool { self == .available }
    }

    @Published private(set) var state: State = .idle

    private let tag: String
    private var request: NSBundleResourceRequest?
    private var progressObservation: NSKeyValueObservation?

    init(tag: String = LearnImage.onDemandResourceTag) {
        self.tag = tag
    }

    /// Requests the tag, or resolves immediately if the pack is already on disk.
    ///
    /// Availability is decided by `conditionallyBeginAccessingResources()` rather
    /// than by asking whether the images load. A tagged asset leaves a small stub
    /// in the main catalog, so `UIImage(named:)` can return non-nil before the pack
    /// has been fetched — which would report success and then render nothing.
    func load() async {
        guard state == .idle else { return }

        let request = NSBundleResourceRequest(tags: [tag])
        self.request = request
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent

        if await request.conditionallyBeginAccessingResources() {
            state = .available
            return
        }

        state = .loading(fraction: 0)
        observeProgress(of: request)

        do {
            try await request.beginAccessingResources()
            state = .available
        } catch {
            // A build without the tags configured lands here even though the
            // images are in the bundle, so the assets get the final say.
            state = LearnImage.allCases.allSatisfy(\.isFullyLoaded)
                ? .available
                : .unavailable(error.localizedDescription)
        }
        progressObservation = nil
    }

    /// Lets the system reclaim the space once the tab is no longer on screen.
    func release() {
        request?.endAccessingResources()
        request = nil
        progressObservation = nil
        state = .idle
    }

    func retry() async {
        release()
        await load()
    }

    private func observeProgress(of request: NSBundleResourceRequest) {
        progressObservation = request.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                guard case .loading = self?.state else { return }
                self?.state = .loading(fraction: progress.fractionCompleted)
            }
        }
    }
}
