import SwiftUI

public enum MSButtonKind: Sendable {
    case primary, secondary, tertiary, destructive
}

public struct MSButtonStyle: ButtonStyle {
    private let kind: MSButtonKind
    private let fullWidth: Bool

    public init(kind: MSButtonKind = .primary, fullWidth: Bool = true) {
        self.kind = kind
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MSFont.bodyEmphasis)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: MSSize.minTouchTarget)
            .padding(.horizontal, MSSpacing.lg)
            .background(background(pressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: MSRadius.md)
                    .strokeBorder(border, lineWidth: kind == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: MSRadius.md))
            .contentShape(Rectangle())
            .opacity(isEnabled(configuration) ? 1 : 0.45)
    }

    private func isEnabled(_ configuration: Configuration) -> Bool { true }

    private var foreground: Color {
        switch kind {
        case .primary: MSColor.onAccent
        case .secondary, .tertiary: MSColor.textPrimary
        case .destructive: .white
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? MSColor.accentPressed : MSColor.accent
        case .secondary: pressed ? MSColor.surfaceSunken : .clear
        case .tertiary: pressed ? MSColor.surfaceSunken : .clear
        case .destructive: MSColor.danger.opacity(pressed ? 0.8 : 1)
        }
    }

    private var border: Color {
        kind == .secondary ? MSColor.border : .clear
    }
}

public extension View {
    func msButton(_ kind: MSButtonKind = .primary, fullWidth: Bool = true) -> some View {
        buttonStyle(MSButtonStyle(kind: kind, fullWidth: fullWidth))
    }
}
