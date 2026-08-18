import Foundation
import MultiSetKit

/// Localizes by calling the query endpoints directly.
///
/// Works under any `AuthPrincipal`, which is what makes the App Clip possible:
/// an anonymous experience token is enough, so no clientSecret ever reaches the
/// Clip. The parent app can use it too, for comparison against the SDK.
public final class RESTPoseProvider: PoseProvider, ObjectTrackingProvider {
    public let providerName = "REST"
    public let requiresCredentials = false

    private let api: any MultiSetAPI
    private let mode: LocalizationMode
    private let state = ProviderState()

    public init(api: any MultiSetAPI, mode: LocalizationMode = .multiFrame) {
        self.api = api
        self.mode = mode
    }

    public func prepare(target: MapTarget) async throws {
        await state.setTarget(target)
    }

    public func prepare(objectCodes: [String]) async throws {
        await state.setObjectCodes(objectCodes)
    }

    public func locate(frames: [CapturedFrame], geoHint: GeoCoordinates?) async throws -> LocalizationResult {
        guard let target = await state.target else {
            throw MultiSetError.notLocalized(message: "No map was selected for this session.")
        }
        guard let reference = frames.first else {
            throw MultiSetError.notLocalized(message: "No frames were captured.")
        }

        let query = LocalizationQuery(
            target: target,
            intrinsics: reference.intrinsics,
            resolution: reference.resolution,
            isRightHanded: Self.isRightHanded,
            geoHint: geoHint,
            convertToGeoCoordinates: geoHint != nil
        )

        switch mode {
        case .singleFrame:
            return try await api.localizeSingleFrame(query, frame: reference.queryFrame)
        case .multiFrame:
            return try await api.localizeMultiFrame(query, frames: frames.map(\.queryFrame))
        }
    }

    public func track(frame: CapturedFrame) async throws -> ObjectTrackingResult {
        let codes = await state.objectCodes
        guard !codes.isEmpty else {
            throw MultiSetError.notLocalized(message: "No object was selected for this session.")
        }
        return try await api.queryObject(
            ObjectQuery(
                objectCodes: codes,
                intrinsics: frame.intrinsics,
                resolution: frame.resolution,
                isRightHanded: Self.isRightHanded
            ),
            frame: frame.queryFrame
        )
    }

    public func teardown() async {
        await state.clear()
    }

    /// ARKit is right-handed, unlike Unity, which is the only client the SDK
    /// documentation shows. Whether the server honours the flag for native
    /// clients is unverified against a live map — see ARCHITECTURE.md.
    static let isRightHanded = true
}

private actor ProviderState {
    var target: MapTarget?
    var objectCodes: [String] = []

    func setTarget(_ target: MapTarget) { self.target = target }
    func setObjectCodes(_ codes: [String]) { objectCodes = codes }

    func clear() {
        target = nil
        objectCodes = []
    }
}
