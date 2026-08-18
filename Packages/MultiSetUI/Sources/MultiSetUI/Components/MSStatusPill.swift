import SwiftUI

public enum MSStatusTone: Sendable {
    case neutral, positive, caution, negative, accent

    var color: Color {
        switch self {
        case .neutral: MSColor.textMuted
        case .positive: MSColor.success
        case .caution: MSColor.warning
        case .negative: MSColor.danger
        case .accent: MSColor.accent
        }
    }
}

public struct MSStatusPill: View {
    private let label: String
    private let tone: MSStatusTone
    private let systemImage: String?

    public init(_ label: String, tone: MSStatusTone = .neutral, systemImage: String? = nil) {
        self.label = label
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: MSSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(label)
        }
        .font(MSFont.captionEmphasis)
        .foregroundStyle(tone.color)
        .padding(.horizontal, MSSpacing.sm)
        .padding(.vertical, MSSpacing.xxs + 1)
        .background(tone.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tone.color.opacity(0.24), lineWidth: 1))
        .accessibilityLabel(label)
    }
}

/// A monospaced key/value row for engineering data. Long-press copies the value.
public struct MSMonoValue: View {
    private let label: String
    private let value: String
    private let tone: Color?

    public init(_ label: String, _ value: String, tone: Color? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MSSpacing.sm) {
            Text(label)
                .font(MSFont.monoSmall)
                .foregroundStyle(MSColor.textMuted)
            Spacer(minLength: MSSpacing.sm)
            Text(value)
                .font(MSFont.mono)
                .foregroundStyle(tone ?? MSColor.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}
