import MultiSetARCore
import MultiSetKit
import MultiSetUI
import SwiftUI

struct DemoRunnerView: View {
    let demo: DemoKind

    @EnvironmentObject private var model: AppModel
    @State private var isRunning = false
    @State private var showsTargetSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSSpacing.xl) {
                VStack(alignment: .leading, spacing: MSSpacing.sm) {
                    MSStatusPill("Demo map", tone: .accent)
                    Text(demo.title)
                        .font(MSFont.display)
                        .foregroundStyle(MSColor.textPrimary)
                    Text(demo.subtitle)
                        .font(MSFont.body)
                        .foregroundStyle(MSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MSCard {
                    VStack(alignment: .leading, spacing: MSSpacing.md) {
                        Text("What happens")
                            .font(MSFont.headline)
                            .foregroundStyle(MSColor.textPrimary)
                        ForEach(steps, id: \.self) { step in
                            HStack(alignment: .top, spacing: MSSpacing.sm) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(MSColor.accent)
                                    .padding(.top, 6)
                                Text(step)
                                    .font(MSFont.callout)
                                    .foregroundStyle(MSColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                VStack(spacing: MSSpacing.sm) {
                    Button("Start demo") { isRunning = true }
                        .msButton()
                    if demo == .objectTracking {
                        Button("Get the printable target") { showsTargetSheet = true }
                            .msButton(.secondary)
                    }
                }

                Text("This demo runs entirely on the device. It doesn't need a mapped site, an account, or a network connection.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
        .navigationTitle("Demo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTargetSheet) { DemoTargetSheet() }
        .fullScreenCover(isPresented: $isRunning) {
            DemoSessionView(demo: demo) { isRunning = false }
        }
    }

    private var steps: [String] {
        switch demo {
        case .objectTracking:
            [
                "Print the target sheet, or open it on a laptop screen.",
                "Point the camera at it from about half a metre away.",
                "The outline traces the target as you move around it."
            ]
        case .syntheticNavigation:
            [
                "Point the camera at the floor until a surface is detected.",
                "A short route is placed in the room, scaled to about three metres.",
                "Walk it — the pathfinding, guidance, and rendering are the production ones."
            ]
        case .simulatedLocalization:
            [
                "A recorded frame sequence from a real mapped site is replayed.",
                "Each frame goes through the same localization pipeline as a live query.",
                "The pose readout shows a genuine VPS result, at a desk."
            ]
        }
    }
}

/// The demo AR session. Uses the mock API so it needs no credentials and no
/// network, while running the real engine, pathfinding, and rendering.
struct DemoSessionView: View {
    let demo: DemoKind
    let onExit: () -> Void

    var body: some View {
        ARExperienceScreen(
            configuration: configuration,
            providerFactory: { _ in
                let api = MockMultiSetAPI(behaviour: .init(latency: .milliseconds(700)))
                let provider = RESTPoseProvider(api: api)
                return (provider, demo == .objectTracking ? provider : nil)
            },
            onExit: onExit
        )
    }

    private var configuration: ExperienceConfiguration {
        switch demo {
        case .objectTracking:
            ExperienceConfiguration(
                mode: .track,
                target: .map(code: "OBJ_DEMO0TARGET1"),
                objectCodes: ["OBJ_DEMO0TARGET1"]
            )
        case .syntheticNavigation:
            ExperienceConfiguration(
                mode: .navigate,
                target: .map(code: "MAP_7UVHMW2TJMOA"),
                pointsOfInterest: DemoContent.pointsOfInterest,
                destinationPOIID: "demo_destination",
                navGraph: DemoContent.roomScaleGraph
            )
        case .simulatedLocalization:
            ExperienceConfiguration(
                mode: .localize,
                target: .map(code: "MAP_7UVHMW2TJMOA"),
                localizationMode: .multiFrame
            )
        }
    }
}

/// The printable object-tracking target. Generated as vector geometry so it
/// prints crisply at any size and costs no bundle bytes.
struct DemoTargetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MSSpacing.lg) {
                    Text("Print this at A4 or Letter, or display it full-screen on a laptop. Both work.")
                        .font(MSFont.callout)
                        .foregroundStyle(MSColor.textSecondary)
                        .multilineTextAlignment(.center)

                    DemoTargetArtwork()
                        .frame(width: 260, height: 260)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: MSRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: MSRadius.md)
                                .strokeBorder(MSColor.border, lineWidth: 1)
                        )

                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Share the PDF", systemImage: "square.and.arrow.up")
                        }
                        .msButton()
                    } else {
                        Button("Export as PDF") { exportedURL = PrintableTarget.writePDF() }
                            .msButton()
                    }
                }
                .padding(MSSpacing.lg)
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Printable target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DemoTargetArtwork: View {
    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.08
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)

            context.stroke(Path(rect), with: .color(.black), lineWidth: 3)

            // Asymmetric corner blocks: the asymmetry is what lets the tracker
            // resolve orientation rather than only position.
            let block = rect.width * 0.16
            let corners = [
                CGRect(x: rect.minX, y: rect.minY, width: block, height: block),
                CGRect(x: rect.maxX - block, y: rect.minY, width: block, height: block),
                CGRect(x: rect.minX, y: rect.maxY - block, width: block, height: block)
            ]
            for corner in corners {
                context.fill(Path(corner), with: .color(.black))
            }

            let centre = CGPoint(x: rect.midX, y: rect.midY)
            for ring in 1...4 {
                let radius = rect.width * 0.055 * CGFloat(ring)
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: centre.x - radius, y: centre.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(.black),
                    lineWidth: 2
                )
            }
            var cross = Path()
            let arm = rect.width * 0.3
            cross.move(to: CGPoint(x: centre.x - arm, y: centre.y))
            cross.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
            cross.move(to: CGPoint(x: centre.x, y: centre.y - arm))
            cross.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
            context.stroke(cross, with: .color(.black), lineWidth: 2)
        }
        .accessibilityLabel("Object tracking target: a square frame with corner blocks and concentric rings")
    }
}

#Preview {
    NavigationStack {
        DemoRunnerView(demo: .syntheticNavigation)
            .environmentObject(AppModel.preview())
    }
}
