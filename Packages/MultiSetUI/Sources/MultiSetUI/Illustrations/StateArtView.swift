import SwiftUI

/// Renders a `StateArt` vector, tinted, with the geometric `Canvas` family as the
/// fallback when the asset is missing.
public struct StateArtView: View {
    private let art: StateArt
    private let size: CGFloat
    private let tint: Color?

    public init(_ art: StateArt, size: CGFloat = 120, tint: Color? = nil) {
        self.art = art
        self.size = size
        self.tint = tint
    }

    public var body: some View {
        if let image = art.image {
            image
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(tint ?? MSColor.accent)
                .accessibilityHidden(true)
        } else {
            MSIllustrationView(art.fallbackIllustration, size: size)
        }
    }
}

public extension StateArt {
    /// The code-drawn equivalent, used when the vector asset cannot be loaded.
    var fallbackIllustration: MSIllustration {
        switch self {
        case .noMaps: .noMaps
        case .noObjects: .noObjects
        case .searching: .searching(progress: 0.5)
        case .experienceEnded: .invalidated
        }
    }
}

#Preview("State art") {
    VStack(spacing: MSSpacing.xl) {
        HStack(spacing: MSSpacing.xl) {
            StateArtView(.noMaps)
            StateArtView(.noObjects)
        }
        HStack(spacing: MSSpacing.xl) {
            StateArtView(.searching)
            StateArtView(.experienceEnded, tint: MSColor.textMuted)
        }
    }
    .padding()
}

#Preview("Scaled to 3x, checking vector sharpness") {
    HStack(spacing: MSSpacing.lg) {
        StateArtView(.noMaps, size: 360)
    }
    .padding()
}
