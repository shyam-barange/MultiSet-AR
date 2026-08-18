import SwiftUI

public struct MSCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = MSSpacing.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MSColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: MSRadius.lg)
                    .strokeBorder(MSColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
    }
}

public struct MSSectionHeader: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MSSpacing.xxs) {
            Text(title)
                .font(MSFont.headline)
                .foregroundStyle(MSColor.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
