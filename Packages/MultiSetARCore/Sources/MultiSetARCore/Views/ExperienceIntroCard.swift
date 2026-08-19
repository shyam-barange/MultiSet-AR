import MultiSetKit
import MultiSetUI
import SwiftUI

/// Shown before the camera opens, in both the app and the Clip.
///
/// This is where camera permission gets asked for with context rather than cold,
/// and where the report link required for third-party hosted content lives.
public struct ExperienceIntroCard: View {
    public let manifest: ExperienceManifest
    public let onStart: () -> Void
    public let onCancel: () -> Void

    public init(
        manifest: ExperienceManifest,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.manifest = manifest
        self.onStart = onStart
        self.onCancel = onCancel
    }

    @Environment(\.openURL) private var openURL

    private var accent: Color {
        manifest.branding.accentHex.map { Color(hex: $0) } ?? MSColor.accent
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: MSSpacing.xl)

            VStack(spacing: MSSpacing.xl) {
                badge
                VStack(spacing: MSSpacing.sm) {
                    Text(manifest.branding.title)
                        .font(MSFont.display)
                        .foregroundStyle(MSColor.textPrimary)
                        .multilineTextAlignment(.center)
                    if let subtitle = manifest.branding.subtitle {
                        Text(subtitle)
                            .font(MSFont.body)
                            .foregroundStyle(MSColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                MSCard {
                    VStack(alignment: .leading, spacing: MSSpacing.md) {
                        Label(manifest.mode.displayName, systemImage: manifest.mode.symbolName)
                            .font(MSFont.captionEmphasis)
                            .foregroundStyle(accent)
                        Text(manifest.expectation)
                            .font(MSFont.callout)
                            .foregroundStyle(MSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().overlay(MSColor.borderSubtle)
                        Label(
                            "The camera is used to work out where you are. Nothing is recorded.",
                            systemImage: "camera"
                        )
                        .font(MSFont.caption)
                        .foregroundStyle(MSColor.textMuted)
                    }
                }
            }
            .padding(.horizontal, MSSpacing.lg)

            Spacer(minLength: MSSpacing.xl)

            VStack(spacing: MSSpacing.md) {
                Button(manifest.mode.primaryActionTitle, action: onStart)
                    .msButton()
                HStack(spacing: MSSpacing.lg) {
                    Button("Not now", action: onCancel)
                        .font(MSFont.callout)
                        .foregroundStyle(MSColor.textSecondary)
                        .frame(minHeight: MSSize.minTouchTarget)
                    Spacer(minLength: 0)
                    reportButton
                }
            }
            .padding(.horizontal, MSSpacing.lg)
            .padding(.bottom, MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 108, height: 108)
            Image(systemName: manifest.mode.symbolName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(accent)
        }
        .accessibilityHidden(true)
    }

    /// Required for hosted third-party content: a report path on every
    /// experience, with reachable contact details.
    private var reportButton: some View {
        Button {
            openURL(Self.reportURL(spaceCode: manifest.spaceCode))
        } label: {
            HStack(spacing: MSSpacing.xs) {
                Image(systemName: "flag")
                Text("Report")
            }
            .font(MSFont.caption)
            .foregroundStyle(MSColor.textMuted)
            .frame(minHeight: MSSize.minTouchTarget)
        }
        .accessibilityLabel("Report this experience")
        .accessibilityHint("Opens an email to MultiSet support")
    }

    public static func reportURL(spaceCode: String) -> URL {
        var components = URLComponents(string: "mailto:\(CompanyInfo.contactEmail)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report a MultiSet AR experience: \(spaceCode)"),
            URLQueryItem(
                name: "body",
                value: """
                Experience code: \(spaceCode)

                Please describe the problem:
                """
            )
        ]
        return components.url ?? ExternalLink.contactEmail
    }
}

#Preview("Navigate") {
    ExperienceIntroCard(
        manifest: ExperienceManifest(
            spaceCode: "k7m2p9xq",
            mode: .navigate,
            target: .map(code: "MAP_7UVHMW2TJMOA"),
            branding: ExperienceBranding(
                title: "Northfield DC",
                subtitle: "Follow the line to Dispatch"
            ),
            pointsOfInterest: [
                PointOfInterest(id: "poi_dispatch", title: "Dispatch office", position: Position(x: 11.8, y: 0, z: -7.2))
            ],
            destinationPOIID: "poi_dispatch",
            token: AuthToken(token: "t", expiresOn: Date().addingTimeInterval(900))
        ),
        onStart: {},
        onCancel: {}
    )
}
