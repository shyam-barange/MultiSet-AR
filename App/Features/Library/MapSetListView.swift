import MultiSetKit
import MultiSetUI
import SwiftUI

struct MapSetListView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var list = ResourceListModel<MapSet>()

    var body: some View {
        ResourceList(
            list: list,
            emptyIllustration: .noMaps,
            emptyTitle: "No map sets yet",
            emptyMessage: "A map set stitches several maps into one coordinate system, so a whole building shares an origin."
        ) { mapSet in
            MapSetRow(mapSet: mapSet)
        }
        .searchable(text: $list.searchText, prompt: "Search map sets")
        .onChange(of: list.searchText) { _ in list.searchChanged() }
        .task {
            guard list.items.isEmpty else { return }
            let api = model.api
            list.rebind { query in
                try await api.mapSets(page: .first, search: query.isEmpty ? nil : query).mapSets
            }
            list.reload()
        }
    }
}

struct MapSetRow: View {
    let mapSet: MapSet

    var body: some View {
        MSCard(padding: MSSpacing.md) {
            VStack(alignment: .leading, spacing: MSSpacing.sm) {
                HStack(spacing: MSSpacing.md) {
                    RoundedRectangle(cornerRadius: MSRadius.sm)
                        .fill(MSColor.accentSoft)
                        .frame(width: MSSize.thumbnail, height: MSSize.thumbnail)
                        .overlay {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(MSColor.accent)
                        }
                    VStack(alignment: .leading, spacing: MSSpacing.xs) {
                        Text(mapSet.name)
                            .font(MSFont.bodyEmphasis)
                            .foregroundStyle(MSColor.textPrimary)
                        if let code = mapSet.mapSetCode {
                            Text(code)
                                .font(MSFont.monoSmall)
                                .foregroundStyle(MSColor.textMuted)
                        }
                        MSStatusPill("\(mapSet.mapCount) maps", tone: .neutral)
                    }
                    Spacer(minLength: 0)
                }

                if let entries = mapSet.mapSetData, !entries.isEmpty {
                    Divider().overlay(MSColor.borderSubtle)
                    ForEach(entries) { entry in
                        HStack(spacing: MSSpacing.sm) {
                            Text("#\(entry.order ?? 0)")
                                .font(MSFont.monoSmall)
                                .foregroundStyle(MSColor.textMuted)
                                .frame(width: 24, alignment: .leading)
                            Text(entry.map?.mapName ?? "Unnamed map")
                                .font(MSFont.caption)
                                .foregroundStyle(MSColor.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let pose = entry.relativePose {
                                Text(String(
                                    format: "%+.1f %+.1f %+.1f",
                                    pose.position.x, pose.position.y, pose.position.z
                                ))
                                .font(MSFont.monoSmall)
                                .foregroundStyle(MSColor.textMuted)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mapSet.name), \(mapSet.mapCount) maps")
    }
}

#Preview {
    NavigationStack {
        MapSetListView().environmentObject(AppModel.preview())
    }
}
