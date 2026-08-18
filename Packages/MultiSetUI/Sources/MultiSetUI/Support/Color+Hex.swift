import SwiftUI

extension Color {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` string. Invalid input yields magenta
    /// so a bad token is visible in review rather than silently transparent.
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt64(raw, radix: 16), raw.count == 6 || raw.count == 8 else {
            self = .init(red: 1, green: 0, blue: 1)
            return
        }
        let shift = raw.count == 8 ? 8 : 0
        let alpha = raw.count == 8 ? Double(value & 0xFF) / 255 : 1
        self.init(
            .sRGB,
            red: Double((value >> (16 + shift)) & 0xFF) / 255,
            green: Double((value >> (8 + shift)) & 0xFF) / 255,
            blue: Double((value >> shift) & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Resolves to `light` or `dark` from the rendering trait collection.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
