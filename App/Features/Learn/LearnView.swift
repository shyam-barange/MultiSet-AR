import MultiSetKit
import MultiSetUI
import SwiftUI

/// Native content, not a web view. A `WKWebView` shell is a Guideline 4.2 risk
/// and reads as filler.
struct LearnView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MSSpacing.xxl) {
                    intro
                    capabilities
                    recognition
                    sdks
                    community
                    footer
                }
                .padding(MSSpacing.lg)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Learn")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: MSSpacing.sm) {
            Text("The independent spatial layer")
                .font(MSFont.display)
                .foregroundStyle(MSColor.textPrimary)
            Text("MultiSet gives any camera-equipped device centimetre-accurate knowledge of where it is, and keeps that knowledge as the physical world changes.")
                .font(MSFont.body)
                .foregroundStyle(MSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Technology")
            ForEach(Capability.all) { capability in
                capabilityCard(capability)
            }
        }
    }

    private func capabilityCard(_ capability: Capability) -> some View {
        MSCard {
            VStack(alignment: .leading, spacing: MSSpacing.md) {
                if let image = UIImage(named: capability.imageName) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(16 / 10, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: MSRadius.md))
                        .accessibilityHidden(true)
                }
                HStack(spacing: MSSpacing.md) {
                    Image(systemName: capability.symbolName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(MSColor.accent)
                        .frame(width: MSSize.iconLg)
                    Text(capability.title)
                        .font(MSFont.headline)
                        .foregroundStyle(MSColor.textPrimary)
                    Spacer(minLength: 0)
                }
                Text(capability.explainer)
                    .font(MSFont.callout)
                    .foregroundStyle(MSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !capability.facts.isEmpty {
                    Divider().overlay(MSColor.borderSubtle)
                    VStack(spacing: MSSpacing.sm) {
                        ForEach(capability.facts, id: \.0) { fact in
                            MSMonoValue(fact.0, fact.1)
                        }
                    }
                }
                Button {
                    openURL(capability.link)
                } label: {
                    HStack(spacing: MSSpacing.xs) {
                        Text("Read more")
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(MSFont.captionEmphasis)
                    .foregroundStyle(MSColor.accent)
                    .frame(minHeight: MSSize.minTouchTarget, alignment: .leading)
                }
            }
        }
    }

    private var recognition: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Recognition")
            MSCard {
                VStack(alignment: .leading, spacing: MSSpacing.lg) {
                    award(
                        emoji: "🏆",
                        title: "Best Developer Tool",
                        detail: "Auggie Awards, AWE USA 2026",
                        link: ExternalLink.auggieAward
                    )
                    Divider().overlay(MSColor.borderSubtle)
                    award(
                        emoji: "📊",
                        title: "Most Robust VPS",
                        detail: "AREA 2025 Enterprise Visual Positioning System Report",
                        link: ExternalLink.areaReport
                    )
                }
            }
        }
    }

    private func award(emoji: String, title: String, detail: String, link: URL) -> some View {
        Button {
            openURL(link)
        } label: {
            HStack(alignment: .top, spacing: MSSpacing.md) {
                Text(emoji).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                    Text(detail)
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MSColor.textMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }

    private var sdks: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("SDKs", subtitle: "One platform, six runtimes.")
            ForEach(SDKEntry.all) { sdk in
                Button {
                    openURL(sdk.url)
                } label: {
                    MSCard(padding: MSSpacing.md) {
                        HStack(spacing: MSSpacing.md) {
                            Image(systemName: sdk.symbolName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(MSColor.accent)
                                .frame(width: MSSize.iconMd)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sdk.name)
                                    .font(MSFont.bodyEmphasis)
                                    .foregroundStyle(MSColor.textPrimary)
                                Text(sdk.summary)
                                    .font(MSFont.caption)
                                    .foregroundStyle(MSColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MSColor.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var community: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Community")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: MSSpacing.sm)], spacing: MSSpacing.sm) {
                ForEach(CommunityLink.all) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        VStack(spacing: MSSpacing.xs) {
                            Image(systemName: link.symbolName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(MSColor.accent)
                            Text(link.name)
                                .font(MSFont.caption)
                                .foregroundStyle(MSColor.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(MSColor.surface, in: RoundedRectangle(cornerRadius: MSRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: MSRadius.md)
                                .strokeBorder(MSColor.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(link.name)")
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: MSSpacing.xs) {
            Button("Read the blog") { openURL(ExternalLink.blog) }
                .font(MSFont.bodyEmphasis)
                .foregroundStyle(MSColor.accent)
                .frame(minHeight: MSSize.minTouchTarget)
            Text(CompanyInfo.copyright)
                .font(MSFont.monoSmall)
                .foregroundStyle(MSColor.textMuted)
            Text(CompanyInfo.address)
                .font(MSFont.monoSmall)
                .foregroundStyle(MSColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Capability: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let imageName: String
    let explainer: String
    let facts: [(String, String)]
    let link: URL

    static let all: [Capability] = [
        Capability(
            id: "vps",
            title: "Visual Positioning System",
            symbolName: "scope",
            imageName: "LearnVPS",
            explainer: "Instant 6-DoF relocalization against a prebuilt map, holding accuracy through low light, glare, occlusion, and fast motion.",
            facts: [("ACCURACY", "≤ 5 cm"), ("RELOCK", "< 100 ms"), ("DRIFT", "< 0.1 % / min")],
            link: ExternalLink.vps
        ),
        Capability(
            id: "object",
            title: "Object tracking",
            symbolName: "cube.transparent",
            imageName: "LearnObjectTracking",
            explainer: "Recognises and tracks a specific physical object from any angle, so AR content can attach to equipment rather than to a room.",
            facts: [],
            link: ExternalLink.objectTracking
        ),
        Capability(
            id: "mapping",
            title: "Mapping",
            symbolName: "square.stack.3d.down.right",
            imageName: "LearnMapping",
            explainer: "Scan-agnostic: LiDAR, point clouds, textured meshes, Gaussian splats, 360° video, or an iPhone scan. Changing capture tool never means re-scanning.",
            facts: [],
            link: ExternalLink.mapping
        ),
        Capability(
            id: "e57",
            title: "E57 → VPS",
            symbolName: "point.3.connected.trianglepath.dotted",
            imageName: "LearnE57",
            explainer: "Turn an existing survey-grade E57 point cloud into a localizable map, without capturing the site again.",
            facts: [],
            link: ExternalLink.e57ToVPS
        ),
        Capability(
            id: "3dgs",
            title: "3DGS → VPS",
            symbolName: "sparkles",
            imageName: "Learn3DGS",
            explainer: "Use a Gaussian splat reconstruction as the basis for localization, keeping its visual fidelity.",
            facts: [],
            link: ExternalLink.gaussianSplatToVPS
        ),
        Capability(
            id: "360",
            title: "360 → VPS",
            symbolName: "pano",
            imageName: "Learn360",
            explainer: "Build a map from 360° imagery — the fastest way to cover a large interior.",
            facts: [],
            link: ExternalLink.panoramaToVPS
        )
    ]
}

struct SDKEntry: Identifiable {
    let id: String
    let name: String
    let summary: String
    let symbolName: String
    let url: URL

    static let all: [SDKEntry] = [
        SDKEntry(
            id: "ios",
            name: "iOS",
            summary: "Swift and ARKit. The framework this app is built on.",
            symbolName: "iphone",
            url: URL(string: "https://github.com/MultiSet-AI/multiset-ios-sdk")!
        ),
        SDKEntry(
            id: "android",
            name: "Android",
            summary: "Kotlin and ARCore.",
            symbolName: "candybarphone",
            url: URL(string: "https://github.com/MultiSet-AI/multiset-android-sdk")!
        ),
        SDKEntry(
            id: "unity",
            name: "Unity",
            summary: "Cross-platform AR Foundation integration.",
            symbolName: "cube",
            url: URL(string: "https://github.com/MultiSet-AI/multiset-unity-sdk")!
        ),
        SDKEntry(
            id: "quest",
            name: "Meta Quest",
            summary: "OpenXR passthrough on standalone headsets.",
            symbolName: "visionpro",
            url: URL(string: "https://github.com/MultiSet-AI/multiset-quest-sdk")!
        ),
        SDKEntry(
            id: "wearables",
            name: "Wearables",
            summary: "Sample VPS integrations for smart glasses.",
            symbolName: "eyeglasses",
            url: URL(string: "https://github.com/MultiSet-AI/wearable-vps-samples")!
        ),
        SDKEntry(
            id: "unity-library",
            name: "Unity as a library",
            summary: "Embed a Unity AR scene inside a native app.",
            symbolName: "square.stack",
            url: URL(string: "https://github.com/MultiSet-AI/unitysdk-as-library")!
        )
    ]
}

struct CommunityLink: Identifiable {
    let id: String
    let name: String
    let symbolName: String
    let url: URL

    static let all: [CommunityLink] = [
        CommunityLink(id: "discord", name: "Discord", symbolName: "bubble.left.and.bubble.right", url: ExternalLink.discord),
        CommunityLink(id: "youtube", name: "YouTube", symbolName: "play.rectangle", url: ExternalLink.youTube),
        CommunityLink(id: "github", name: "GitHub", symbolName: "chevron.left.forwardslash.chevron.right", url: ExternalLink.github),
        CommunityLink(id: "linkedin", name: "LinkedIn", symbolName: "briefcase", url: ExternalLink.linkedIn),
        CommunityLink(id: "x", name: "X", symbolName: "at", url: ExternalLink.x),
        CommunityLink(id: "instagram", name: "Instagram", symbolName: "camera", url: ExternalLink.instagram),
        CommunityLink(id: "docs", name: "Docs", symbolName: "book", url: ExternalLink.docs),
        CommunityLink(id: "status", name: "Status", symbolName: "waveform.path.ecg", url: ExternalLink.status)
    ]
}

#Preview {
    LearnView()
}
