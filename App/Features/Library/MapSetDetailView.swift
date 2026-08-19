import MultiSetKit
import MultiSetUI
import SwiftUI

/// A map set's cockpit. Localizing against a set rather than a single map is the
/// point of one: the server decides which constituent map you are standing in and
/// answers with that map's code, and the SDK then loads that map's mesh with its
/// relative pose applied — so a whole building shares one coordinate system.
struct MapSetDetailView: View {
    let mapSet: MapSet

    @EnvironmentObject private var model: AppModel
    @State private var runningMode: SDKRunner.Mode?
    @State private var toast: MSToast?

    private var code: String? {
        mapSet.mapSetCode?.isEmpty == false ? mapSet.mapSetCode : nil
    }

    private var readyMaps: [MapSetEntry] {
        (mapSet.mapSetData ?? []).filter { $0.map?.status.isReady ?? false }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSSpacing.xl) {
                header
                testLocalization
                maps
                actions
            }
            .padding(MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
        .navigationTitle(mapSet.name)
        .navigationBarTitleDisplayMode(.inline)
        .msToast($toast)
        .fullScreenCover(item: $runningMode) { mode in
            SDKRunner(mode: mode) { runningMode = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            HStack(spacing: MSSpacing.sm) {
                MSStatusPill(
                    (mapSet.status ?? .unknown).displayName,
                    tone: mapSet.status == .active ? .positive : .caution
                )
                MSStatusPill("\(mapSet.mapCount) maps", tone: .neutral, systemImage: "square.stack.3d.up")
                if readyMaps.count < mapSet.mapCount {
                    MSStatusPill("\(readyMaps.count) ready", tone: .caution)
                }
            }
            Text(code ?? "No map set code")
                .font(MSFont.monoLarge)
                .foregroundStyle(code == nil ? MSColor.textMuted : MSColor.textPrimary)
                .textSelection(.enabled)
        }
    }

    private var testLocalization: some View {
        MSCard {
            VStack(alignment: .leading, spacing: MSSpacing.md) {
                Text("Test localization")
                    .font(MSFont.headline)
                    .foregroundStyle(MSColor.textPrimary)
                Text(canLocalize
                    ? "Stand anywhere in this set. MultiSet works out which map you're in and answers with that map's code, then loads its mesh in the set's shared coordinate frame."
                    : unavailableReason)
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let code {
                    HStack(spacing: MSSpacing.sm) {
                        Button("Single frame") {
                            runningMode = .localize(target: .mapSet(code: code, mode: .singleFrame))
                        }
                        .msButton(.secondary, fullWidth: false)
                        .disabled(!canLocalize)

                        Button("Multi frame") {
                            runningMode = .localize(target: .mapSet(code: code, mode: .multiFrame))
                        }
                        .msButton(.primary, fullWidth: false)
                        .disabled(!canLocalize)
                    }
                    if canLocalize {
                        Text("Multi frame is worth preferring across a set — more viewpoints make it likelier the right map is picked.")
                            .font(MSFont.monoSmall)
                            .foregroundStyle(MSColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var canLocalize: Bool {
        code != nil && !readyMaps.isEmpty
    }

    private var unavailableReason: String {
        if code == nil {
            return "This set has no map set code yet, so there's nothing to localize against."
        }
        return "None of the maps in this set have finished processing yet."
    }

    private var maps: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader(
                "Maps in this set",
                subtitle: "Each carries a pose relative to the set's origin."
            )
            ForEach(mapSet.mapSetData ?? []) { entry in
                MSCard(padding: MSSpacing.md) {
                    VStack(alignment: .leading, spacing: MSSpacing.sm) {
                        HStack(spacing: MSSpacing.sm) {
                            Text("#\(entry.order ?? 0)")
                                .font(MSFont.monoSmall)
                                .foregroundStyle(MSColor.textMuted)
                            Text(entry.map?.mapName ?? "Unnamed map")
                                .font(MSFont.bodyEmphasis)
                                .foregroundStyle(MSColor.textPrimary)
                            Spacer(minLength: 0)
                            if let status = entry.map?.status {
                                MSStatusPill(
                                    status.displayName,
                                    tone: status == .active ? .positive : .caution
                                )
                            }
                        }
                        if let mapCode = entry.map?.mapCode {
                            MSMonoValue("CODE", mapCode)
                        }
                        if let pose = entry.relativePose {
                            MSMonoValue("POS", String(
                                format: "%+.3f %+.3f %+.3f",
                                pose.position.x, pose.position.y, pose.position.z
                            ))
                            MSMonoValue("ROT", String(
                                format: "%+.3f %+.3f %+.3f %+.3f",
                                pose.rotation.x, pose.rotation.y, pose.rotation.z, pose.rotation.w
                            ))
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: MSSpacing.sm) {
            if let code {
                Button {
                    UIPasteboard.general.string = code
                    toast = MSToast(message: "Copied \(code)", tone: .success)
                } label: {
                    Label("Copy map set code", systemImage: "doc.on.doc")
                }
                .msButton(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MapSetDetailView(mapSet: Fixtures.mapSets[0])
            .environmentObject(AppModel.preview())
    }
}
