import SwiftUI

/// Semantic color tokens. Values are extracted from the MultiSet dashboard
/// (`multiset-dashboard/src/app/globals.css`), not approximated.
public enum MSColor {
    private enum Brand {
        static let violet600 = Color(hex: "#7C3AED")
        static let violet500 = Color(hex: "#8B5CF6")
        static let violet400 = Color(hex: "#A78BFA")
        static let violet200 = Color(hex: "#DDD6FE")
        static let violet50 = Color(hex: "#F5F3FF")

        static let ink = Color(hex: "#111028")
        static let inkSecondary = Color(hex: "#4A4564")
        static let inkMuted = Color(hex: "#7D7896")

        static let night = Color(hex: "#1E1B2E")
        static let nightRaised = Color(hex: "#2A2640")
        static let nightBorder = Color(hex: "#2E2A45")
        static let nightText = Color(hex: "#A8A3C0")

        static let surface = Color(hex: "#F5F5F9")
        static let borderDefault = Color(hex: "#E0DEE8")
        static let borderLight = Color(hex: "#ECEAF2")

        static let red = Color(hex: "#EF4444")
        static let amber = Color(hex: "#F59E0B")
        static let green = Color(hex: "#10B981")
        static let blue = Color(hex: "#3B82F6")
    }

    public static let accent = Color.adaptive(light: Brand.violet600, dark: Brand.violet400)
    public static let accentPressed = Color.adaptive(light: Brand.violet500, dark: Brand.violet200)
    public static let onAccent = Color.adaptive(light: .white, dark: Brand.night)
    public static let accentSoft = Color.adaptive(light: Brand.violet50, dark: Brand.nightRaised)

    public static let background = Color.adaptive(light: Brand.surface, dark: Color(hex: "#141220"))
    public static let surface = Color.adaptive(light: .white, dark: Brand.night)
    public static let surfaceRaised = Color.adaptive(light: .white, dark: Brand.nightRaised)
    public static let surfaceSunken = Color.adaptive(light: Brand.surface, dark: Color(hex: "#100E1A"))

    public static let textPrimary = Color.adaptive(light: Brand.ink, dark: Color(hex: "#F4F2FA"))
    public static let textSecondary = Color.adaptive(light: Brand.inkSecondary, dark: Brand.nightText)
    public static let textMuted = Color.adaptive(light: Brand.inkMuted, dark: Color(hex: "#7E7898"))

    public static let border = Color.adaptive(light: Brand.borderDefault, dark: Brand.nightBorder)
    public static let borderSubtle = Color.adaptive(light: Brand.borderLight, dark: Color(hex: "#26223A"))

    public static let danger = Color.adaptive(light: Brand.red, dark: Color(hex: "#F87171"))
    public static let warning = Color.adaptive(light: Brand.amber, dark: Color(hex: "#FBBF24"))
    public static let success = Color.adaptive(light: Brand.green, dark: Color(hex: "#34D399"))
    public static let info = Color.adaptive(light: Brand.blue, dark: Color(hex: "#60A5FA"))

    /// AR overlays render against arbitrary camera feeds, so they use fixed
    /// high-contrast values rather than adapting to the interface style.
    public enum AR {
        public static let scrim = Color.black.opacity(0.55)
        public static let panel = Color.black.opacity(0.72)
        public static let panelBorder = Color.white.opacity(0.16)
        public static let text = Color.white
        public static let textDim = Color.white.opacity(0.66)
        public static let accent = Brand.violet400
        public static let good = Color(hex: "#34D399")
        public static let poor = Color(hex: "#FBBF24")
        public static let bad = Color(hex: "#F87171")
    }
}
