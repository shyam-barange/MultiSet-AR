import MultiSetKit
import MultiSetUI
import SwiftUI

/// A list that loads once, reloads on search, and shows failures with a way to
/// retry rather than an empty screen.
@MainActor
final class ResourceListModel<Item: Identifiable & Sendable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var error: MultiSetError?
    @Published var searchText = ""

    private var loadTask: Task<Void, Never>?
    /// Rebindable because the API arrives from the environment, which a
    /// `StateObject` initialiser cannot reach.
    private var loader: (String) async throws -> [Item]

    init(load: @escaping (String) async throws -> [Item] = { _ in [] }) {
        self.loader = load
    }

    func rebind(_ load: @escaping (String) async throws -> [Item]) {
        loader = load
    }

    var isEmptyAfterLoading: Bool {
        items.isEmpty && !isLoading && error == nil
    }

    func reload() {
        loadTask?.cancel()
        let query = searchText
        loadTask = Task {
            isLoading = true
            error = nil
            defer { isLoading = false }
            do {
                items = try await loader(query)
            } catch is CancellationError {
                return
            } catch {
                self.error = error.asMultiSetError
            }
        }
    }

    /// Debounces typing so a four-character search does not fire four requests.
    func searchChanged() {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            reload()
        }
    }
}

struct MapListView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var list: ResourceListModel<VPSMap>

    init() {
        _list = StateObject(wrappedValue: ResourceListModel())
    }

    var body: some View {
        ResourceList(
            list: list,
            emptyIllustration: .noMaps,
            emptyTitle: "No maps yet",
            emptyMessage: "Scan a space with the MultiSet app, or upload a point cloud in the developer portal."
        ) { map in
            NavigationLink {
                MapDetailView(mapCode: map.mapCode)
            } label: {
                MapRow(map: map)
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $list.searchText, prompt: "Search maps or codes")
        .onChange(of: list.searchText) { _ in list.searchChanged() }
        .task {
            guard list.items.isEmpty else { return }
            let api = model.api
            list.rebind { query in
                try await api.maps(page: .first, search: query.isEmpty ? nil : query, status: nil).maps
            }
            list.reload()
        }
    }
}

struct MapRow: View {
    let map: VPSMap

    var body: some View {
        MSCard(padding: MSSpacing.md) {
            HStack(spacing: MSSpacing.md) {
                thumbnail
                VStack(alignment: .leading, spacing: MSSpacing.xs) {
                    Text(map.mapName)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                        .lineLimit(2)
                    Text(map.mapCode)
                        .font(MSFont.monoSmall)
                        .foregroundStyle(MSColor.textMuted)
                    badges
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MSColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(map.mapName), code \(map.mapCode), \(map.status.displayName)")
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: MSRadius.sm)
            .fill(MSColor.accentSoft)
            .frame(width: MSSize.thumbnail, height: MSSize.thumbnail)
            .overlay {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(MSColor.accent)
            }
    }

    private var badges: some View {
        HStack(spacing: MSSpacing.xs) {
            MSStatusPill(map.status.displayName, tone: statusTone)
            if map.isGeoreferenced {
                MSStatusPill("Geo", tone: .accent, systemImage: "globe")
            }
            if map.hasOfflineBundle {
                MSStatusPill("Offline", tone: .neutral, systemImage: "arrow.down.circle")
            }
        }
    }

    private var statusTone: MSStatusTone {
        switch map.status {
        case .active: .positive
        case .processing, .pending: .caution
        case .failed: .negative
        case .archived, .unknown: .neutral
        }
    }
}

/// Shared list chrome: loading, empty, and error states in one place so every
/// list in the app behaves the same way.
struct ResourceList<Item: Identifiable & Sendable, Row: View>: View {
    @ObservedObject var list: ResourceListModel<Item>
    let emptyIllustration: MSIllustration
    let emptyTitle: String
    let emptyMessage: String
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(spacing: MSSpacing.sm) {
                if let error = list.error {
                    errorState(error)
                } else if list.isEmptyAfterLoading {
                    MSEmptyState(emptyIllustration, title: emptyTitle, message: emptyMessage)
                        .padding(.top, MSSpacing.xxl)
                } else {
                    ForEach(list.items) { item in
                        row(item)
                    }
                }
            }
            .padding(.horizontal, MSSpacing.lg)
            .padding(.bottom, MSSpacing.xl)
        }
        .overlay {
            if list.isLoading && list.items.isEmpty {
                ProgressView()
            }
        }
        .refreshable { list.reload() }
    }

    private func errorState(_ error: MultiSetError) -> some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(.invalidated)
            Text(error.errorDescription ?? "")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button("Try again") { list.reload() }
                    .msButton(.primary, fullWidth: false)
            }
        }
        .padding(MSSpacing.xl)
        .padding(.top, MSSpacing.xl)
    }
}

#Preview {
    NavigationStack {
        MapListView().environmentObject(AppModel.preview())
    }
}
