import Combine
import Foundation
import MultiSetKit
import simd

/// Drives all three modes.
///
/// One engine rather than three classes: the modes differ only in what they do
/// *after* a fix, and splitting them would mean three copies of the retry,
/// thermal, and lifecycle logic — the exact places behaviour drifts.
@MainActor
public final class LocalizationEngine: ARExperience {
    @Published public private(set) var state: ARExperienceState = .idle
    @Published public private(set) var diagnostics = ARDiagnostics()
    @Published public private(set) var worldFromMap: simd_float4x4?
    @Published public private(set) var guidance: NavGuidance?
    @Published public private(set) var route: AStar.Route?

    private let configuration: ExperienceConfiguration
    private let provider: any PoseProvider
    private let objectProvider: (any ObjectTrackingProvider)?
    private let frames: any FrameSource
    private let clock: @Sendable () -> ContinuousClock.Instant

    private var searchStartedAt: ContinuousClock.Instant?
    private var lastFixAt: ContinuousClock.Instant?
    private var localizeTask: Task<Void, Never>?
    private var relocalizeTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var attempts = 0
    private var isPaused = false

    public init(
        configuration: ExperienceConfiguration,
        provider: any PoseProvider,
        objectProvider: (any ObjectTrackingProvider)? = nil,
        frames: any FrameSource,
        clock: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.configuration = configuration
        self.provider = provider
        self.objectProvider = objectProvider
        self.frames = frames
        self.clock = clock
        self.diagnostics.providerName = provider.providerName
    }

    // MARK: - Lifecycle

    public func start() async {
        state = .initializing
        do {
            try await provider.prepare(target: configuration.target)
            if configuration.mode == .track, let objectProvider {
                try await objectProvider.prepare(objectCodes: configuration.objectCodes)
            }
        } catch {
            state = .failed(error.asMultiSetError)
            return
        }
        startTicking()
        await requestLocalization()
    }

    public func requestLocalization() async {
        guard localizeTask == nil else { return }
        searchStartedAt = searchStartedAt ?? clock()
        let task = Task<Void, Never> { [weak self] in
            await self?.runLocalizationLoop()
        }
        localizeTask = task
        await task.value
        localizeTask = nil
    }

    public func pause() {
        isPaused = true
        localizeTask?.cancel()
        localizeTask = nil
        relocalizeTask?.cancel()
        relocalizeTask = nil
        tickTask?.cancel()
        tickTask = nil
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        startTicking()
        // A fix taken before backgrounding is stale: ARKit's world origin does
        // not survive a session interruption, so the old transform would anchor
        // content in the wrong place. Discard it and look again.
        worldFromMap = nil
        searchStartedAt = clock()
        Task { await requestLocalization() }
    }

    public func teardown() {
        pause()
        Task { [provider, objectProvider] in
            await provider.teardown()
            await objectProvider?.teardown()
        }
        state = .idle
        worldFromMap = nil
        guidance = nil
        route = nil
    }

    // MARK: - Localization

    private func runLocalizationLoop() async {
        repeat {
            guard !isPaused else { return }
            let governor = ThermalGovernor.current()
            diagnostics.thermalState = governor.level.rawValue
            diagnostics.trackingState = frames.trackingStateDescription
            updateSearchingState()

            do {
                let captured = try await frames.captureFrames(
                    count: governor.frameCount(requested: configuration.frameCount),
                    interval: configuration.frameInterval,
                    quality: governor.imageQuality
                )
                diagnostics.framesSubmitted += captured.count
                diagnostics.queryCount += 1
                attempts += 1

                let result = try await provider.locate(frames: captured, geoHint: configuration.geoHint)
                if let threshold = configuration.confidenceThreshold,
                   let confidence = result.confidence,
                   confidence < threshold {
                    throw MultiSetError.notLocalized(
                        message: "Position found but confidence was low. Try aiming somewhere more distinctive."
                    )
                }
                apply(result: result, liveTransform: captured.last?.cameraTransform)
                return
            } catch is CancellationError {
                return
            } catch {
                let failure = error.asMultiSetError
                diagnostics.lastConfidence = nil

                guard shouldKeepRetrying(after: failure) else {
                    state = .failed(failure)
                    return
                }
                updateSearchingState()
                try? await Task.sleep(for: .milliseconds(900))
            }
        } while !Task.isCancelled
    }

    /// Retries only failures that another attempt could plausibly fix. A revoked
    /// experience or a denied camera will never succeed by trying again, and
    /// looping on those would look like a hang.
    private func shouldKeepRetrying(after error: MultiSetError) -> Bool {
        guard configuration.retryFirstLocalizationUntilSuccess else { return false }
        switch error {
        case .notLocalized: return true
        case .offline, .rateLimited: return true
        case .server(let status, _): return status >= 500
        default: return false
        }
    }

    private func apply(result: LocalizationResult, liveTransform: simd_float4x4?) {
        let live = result.trackingPose == nil
            ? (liveTransform ?? frames.currentCameraTransform ?? matrix_identity_float4x4)
            : matrix_identity_float4x4
        worldFromMap = PoseTransform.worldFromMap(result: result, liveCameraTransform: live)

        diagnostics.successCount += 1
        diagnostics.lastLatency = result.latency
        diagnostics.lastConfidence = result.confidence
        lastFixAt = clock()
        searchStartedAt = nil

        switch configuration.mode {
        case .localize:
            state = .localized(result: result)
        case .navigate:
            state = .localized(result: result)
            planRoute(from: result.pose.position)
        case .track:
            state = .localized(result: result)
            startObjectTracking()
        }

        if configuration.backgroundRelocalization {
            scheduleRelocalization()
        }
    }

    // MARK: - Navigation

    private func planRoute(from position: Position) {
        guard let graph = configuration.navGraph,
              let destinationID = destinationNodeID(in: graph)
        else {
            // Without a graph there is nothing to follow, so stay in the
            // localized state rather than promising navigation we cannot give.
            return
        }
        route = AStar.route(in: graph, fromPosition: position, to: destinationID)
        updateGuidance(userPosition: position)
    }

    private func destinationNodeID(in graph: NavGraph) -> String? {
        if let poiID = configuration.destinationPOIID,
           let node = graph.nodes.first(where: { $0.poiID == poiID }) {
            return node.id
        }
        if let poiID = configuration.destinationPOIID, graph.node(id: poiID) != nil {
            return poiID
        }
        return graph.nodes.last?.id
    }

    private func updateGuidance(userPosition: Position) {
        guard let route, !route.isEmpty else { return }
        let destinationName = configuration.pointsOfInterest
            .first { $0.id == configuration.destinationPOIID }?.title
            ?? "your destination"
        let heading = frames.currentCameraTransform?.forward ?? SIMD3<Float>(0, 0, -1)

        let next = NavPathPlanner.guidance(
            route: route,
            userPosition: userPosition,
            heading: heading,
            destinationName: destinationName
        )
        guidance = next
        state = next.hasArrived
            ? .arrived(destination: destinationName)
            : .navigating(
                remaining: next.remainingDistance,
                nextTurn: next.turn.instruction,
                destination: destinationName
            )
    }

    // MARK: - Object tracking

    private func startObjectTracking() {
        guard let objectProvider, let code = configuration.objectCodes.first else { return }
        relocalizeTask?.cancel()
        relocalizeTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isPaused else { return }
                let governor = ThermalGovernor.current()
                do {
                    let captured = try await self.frames.captureFrames(
                        count: 1,
                        interval: .zero,
                        quality: governor.imageQuality
                    )
                    guard let frame = captured.first else { continue }
                    let result = try await objectProvider.track(frame: frame)
                    await MainActor.run {
                        self.diagnostics.queryCount += 1
                        self.diagnostics.framesSubmitted += 1
                        self.diagnostics.successCount += 1
                        self.diagnostics.lastConfidence = result.confidence
                        self.diagnostics.lastLatency = result.latency
                        self.worldFromMap = PoseTransform.matrix(result.pose)
                        self.state = .tracking(objectCode: code, confidence: result.confidence)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run { self.diagnostics.queryCount += 1 }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Background re-localization

    private func scheduleRelocalization() {
        guard configuration.mode != .track else { return }
        relocalizeTask?.cancel()
        relocalizeTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = ThermalGovernor.current().relocalizationInterval
                try? await Task.sleep(for: interval)
                guard let self, !self.isPaused, !Task.isCancelled else { return }
                await self.requestLocalization()
            }
        }
    }

    /// Keeps the elapsed-time readout moving so a long search never looks frozen.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.isPaused else { return }
                self.diagnostics.trackingState = self.frames.trackingStateDescription
                if self.state.needsCoaching {
                    self.updateSearchingState()
                } else if let lastFixAt = self.lastFixAt,
                          case .localized = self.state,
                          self.clock() - lastFixAt > .seconds(60) {
                    self.state = .lost(since: self.clock() - lastFixAt)
                }
            }
        }
    }

    private func updateSearchingState() {
        let elapsed = searchStartedAt.map { clock() - $0 } ?? .zero
        state = .searching(
            hint: SearchCoaching.hint(elapsed: elapsed, attempts: attempts),
            elapsed: elapsed,
            attempts: attempts
        )
    }
}

extension Error {
    var asMultiSetError: MultiSetError {
        if let known = self as? MultiSetError { return known }
        if let urlError = self as? URLError { return .network(code: urlError.code, description: urlError.localizedDescription) }
        return .server(status: -1, message: localizedDescription)
    }
}
