import Foundation
import MultiSetKit
import simd

/// Supplies camera frames to the localization engine.
///
/// A protocol rather than a concrete ARKit type so the engine's logic — retry
/// cadence, thermal throttling, state transitions — is testable without a
/// camera, a device, or an ARSession.
public protocol FrameSource: AnyObject, Sendable {
    var isReadyToCapture: Bool { get }
    var trackingStateDescription: String { get }
    var currentCameraTransform: simd_float4x4? { get }

    func captureFrames(count: Int, interval: Duration, quality: Double) async throws -> [CapturedFrame]
}
