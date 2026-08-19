import MultiSetKit
import MultiSetUI
import SwiftUI

struct ObjectListView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var list = ResourceListModel<TrackedObject>()

    var body: some View {
        ResourceList(
            list: list,
            emptyArt: .noObjects,
            emptyTitle: "No tracked objects yet",
            emptyMessage: "Upload a model in the developer portal and MultiSet will recognise the physical object from any angle."
        ) { object in
            NavigationLink {
                ObjectDetailView(object: object)
            } label: {
                ObjectRow(object: object)
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $list.searchText, prompt: "Search objects or codes")
        .onChange(of: list.searchText) { _ in list.searchChanged() }
        .task {
            guard list.items.isEmpty else { return }
            let api = model.api
            list.rebind { query in
                try await api.trackedObjects(page: .first, search: query.isEmpty ? nil : query).objects
            }
            list.reload()
        }
    }
}

struct ObjectRow: View {
    let object: TrackedObject

    var body: some View {
        MSCard(padding: MSSpacing.md) {
            HStack(spacing: MSSpacing.md) {
                RoundedRectangle(cornerRadius: MSRadius.sm)
                    .fill(MSColor.accentSoft)
                    .frame(width: MSSize.thumbnail, height: MSSize.thumbnail)
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(MSColor.accent)
                    }
                VStack(alignment: .leading, spacing: MSSpacing.xs) {
                    Text(object.objectName)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                        .lineLimit(2)
                    Text(object.objectCode)
                        .font(MSFont.monoSmall)
                        .foregroundStyle(MSColor.textMuted)
                    HStack(spacing: MSSpacing.xs) {
                        MSStatusPill(
                            object.status.displayName,
                            tone: object.status == .active ? .positive : .caution
                        )
                        if let type = object.trackingType {
                            MSStatusPill(type.uppercased(), tone: .neutral)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(object.objectName), code \(object.objectCode), \(object.status.displayName)")
    }
}

#Preview {
    NavigationStack {
        ObjectListView().environmentObject(AppModel.preview())
    }
}
