import Foundation

/// Decides how often to query as the device heats up.
///
/// Sustained VPS use is thermally expensive: camera, Metal, and repeated JPEG
/// encoding at once. The rule is to drop *query frequency* before dropping frame
/// rate — a slower re-localization interval is barely noticeable, whereas a
/// stuttering camera feed makes the whole app feel broken.
public struct ThermalGovernor: Sendable {
    public enum Level: String, Sendable, CaseIterable {
        case nominal, fair, serious, critical

        public init(processInfoState: ProcessInfo.ThermalState) {
            switch processInfoState {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .fair
            }
        }
    }

    public var level: Level

    public init(level: Level) {
        self.level = level
    }

    /// Reads the live thermal state. A separate factory rather than a defaulted
    /// initialiser, so `ThermalGovernor()` can never silently mean "nominal"
    /// when the caller meant "whatever the device is doing right now".
    public static func current(processInfo: ProcessInfo = .processInfo) -> ThermalGovernor {
        ThermalGovernor(level: Level(processInfoState: processInfo.thermalState))
    }

    /// How long to wait between background re-localizations.
    public var relocalizationInterval: Duration {
        switch level {
        case .nominal: .seconds(30)
        case .fair: .seconds(45)
        case .serious: .seconds(90)
        case .critical: .seconds(180)
        }
    }

    /// How many frames a multi-frame query should submit. Fewer frames means a
    /// less reliable fix, so this is reduced only once throttling the interval
    /// is no longer enough.
    public func frameCount(requested: Int) -> Int {
        switch level {
        case .nominal, .fair: max(1, requested)
        case .serious: max(1, min(requested, 3))
        case .critical: 1
        }
    }

    /// JPEG quality for uploaded frames. Dropping this reduces both encode cost
    /// and upload time.
    public var imageQuality: Double {
        switch level {
        case .nominal: 0.9
        case .fair: 0.85
        case .serious: 0.75
        case .critical: 0.6
        }
    }

    /// True when the interface should tell the user the device is hot, rather
    /// than letting the session quietly degrade.
    public var shouldWarnUser: Bool {
        level == .critical
    }
}
