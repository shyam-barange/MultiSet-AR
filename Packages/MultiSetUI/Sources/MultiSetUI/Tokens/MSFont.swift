import SwiftUI

/// Named type roles. SF Pro and SF Mono only — the App Clip byte budget forbids
/// bundled faces, and per-target font divergence would make the App and Clip
/// look like different products.
public enum MSFont {
    public static let display = Font.system(.largeTitle, design: .default, weight: .bold)
    public static let title = Font.system(.title2, design: .default, weight: .semibold)
    public static let headline = Font.system(.headline, design: .default, weight: .semibold)
    public static let body = Font.system(.body, design: .default)
    public static let bodyEmphasis = Font.system(.body, design: .default, weight: .medium)
    public static let callout = Font.system(.callout, design: .default)
    public static let caption = Font.system(.caption, design: .default)
    public static let captionEmphasis = Font.system(.caption, design: .default, weight: .semibold)

    /// Engineering data — map codes, pose values, confidence, latency.
    public static let mono = Font.system(.footnote, design: .monospaced)
    public static let monoSmall = Font.system(.caption2, design: .monospaced)
    public static let monoLarge = Font.system(.title3, design: .monospaced, weight: .medium)
    public static let monoDisplay = Font.system(.largeTitle, design: .monospaced, weight: .semibold)
}
