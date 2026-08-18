import Foundation
import MultiSetKit
import simd

/// Everything the UI needs to render, in one value.
///
/// `.searching` carries elapsed time so the interface can never look like a
/// hang, which is the most common way an AR session reads as broken.
public enum ARExperienceState: Sendable, Equatable {
    case idle
    case initializing
    case searching(hint: String, elapsed: Duration, attempts: Int)
    case localized(result: LocalizationResult)
    case lost(since: Duration)
    case navigating(remaining: Double, nextTurn: String?, destination: String)
    case arrived(destination: String)
    case tracking(objectCode: String, confidence: Double?)
    case failed(MultiSetError)

    public var isRunning: Bool {
        switch self {
        case .idle, .failed: false
        default: true
        }
    }

    /// True while the session has no fix, so overlays know to show coaching.
    public var needsCoaching: Bool {
        switch self {
        case .initializing, .searching, .lost: true
        default: false
        }
    }
}

/// Coaching text for the search overlay. Most localization failures are aim
/// failures, so the guidance escalates from generic to specific rather than
/// repeating one line while the user does the wrong thing.
public enum SearchCoaching {
    public static func hint(elapsed: Duration, attempts: Int) -> String {
        let seconds = elapsed.components.seconds
        // Time-based, not attempt-based: the first attempt begins the moment the
        // camera opens, and telling someone to aim better before they have
        // finished raising the phone is guidance they cannot act on.
        if seconds < 3, attempts <= 1 {
            return "Hold steady while we read the space"
        }
        if seconds < 10 {
            return "Point your camera at the room, not the floor"
        }
        if seconds < 20 {
            return "Walk a few steps and aim at walls, signage, or fixed equipment"
        }
        if seconds < 35 {
            return "Try a different part of the space — large blank surfaces are hard to place"
        }
        return "Still looking. Check you're inside the mapped area."
    }
}

/// Live counters for the pose HUD.
public struct ARDiagnostics: Sendable, Equatable {
    public var framesSubmitted: Int = 0
    public var queryCount: Int = 0
    public var successCount: Int = 0
    public var lastLatency: Duration?
    public var lastConfidence: Double?
    public var trackingState: String = "unavailable"
    public var providerName: String = "—"
    public var thermalState: String = "nominal"

    public init() {}

    public var successRate: Double? {
        guard queryCount > 0 else { return nil }
        return Double(successCount) / Double(queryCount)
    }
}
