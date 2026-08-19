import MapKit
import MultiSetARCore
import MultiSetKit
import MultiSetUI
import SwiftUI

struct MapDetailView: View {
    let mapCode: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var map: VPSMap?
    @State private var heatmap: [HeatmapCell] = []
    @State private var loadError: MultiSetError?
    @State private var isLoading = true
    @State private var runningConfiguration: ExperienceConfiguration?
    @State private var toast: MSToast?

    var body: some View {
        ScrollView {
            if let map {
                VStack(alignment: .leading, spacing: MSSpacing.xl) {
                    header(map)
                    testLocalization(map)
                    if map.isGeoreferenced {
                        georeference(map)
                    }
                    heatmapSection(map)
                    overview(map)
                    actions(map)
                }
                .padding(MSSpacing.lg)
            } else if let loadError {
                errorState(loadError)
            }
        }
        .background(MSColor.background.ignoresSafeArea())
        .navigationTitle(map?.mapName ?? "Map")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } }
        .msToast($toast)
        .fullScreenCover(item: $runningConfiguration) { configuration in
            TestLocalizationRunner(configuration: configuration) {
                runningConfiguration = nil
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private func header(_ map: VPSMap) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            HStack(spacing: MSSpacing.sm) {
                MSStatusPill(
                    map.status.displayName,
                    tone: map.status == .active ? .positive : (map.status == .failed ? .negative : .caution)
                )
                if map.isGeoreferenced {
                    MSStatusPill("Georeferenced", tone: .accent, systemImage: "globe")
                }
                if map.hasOfflineBundle {
                    MSStatusPill("Offline bundle", tone: .neutral, systemImage: "arrow.down.circle")
                }
            }
            Text(map.mapCode)
                .font(MSFont.monoLarge)
                .foregroundStyle(MSColor.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func testLocalization(_ map: VPSMap) -> some View {
        MSCard {
            VStack(alignment: .leading, spacing: MSSpacing.md) {
                Text("Test localization")
                    .font(MSFont.headline)
                    .foregroundStyle(MSColor.textPrimary)
                Text(map.status.isReady
                    ? "Stand inside this map and check that VPS places you where it should, with live confidence and latency."
                    : "This map isn't ready to localize against yet.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MSSpacing.sm) {
                    ForEach(LocalizationMode.allCases) { mode in
                        Button(mode.displayName) {
                            runningConfiguration = ExperienceConfiguration(
                                mode: .localize,
                                target: .map(code: map.mapCode),
                                localizationMode: mode,
                                geoHint: map.geoPosition
                            )
                        }
                        .msButton(mode == .multiFrame ? .primary : .secondary, fullWidth: false)
                        .disabled(!map.status.isReady)
                    }
                }
            }
        }
    }

    private func georeference(_ map: VPSMap) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Where it is")
            if let geo = map.geoPosition {
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: geo.latitude, longitude: geo.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                )), interactionModes: [], annotationItems: [MapPin(coordinate: geo)]) { pin in
                    MapMarker(
                        coordinate: CLLocationCoordinate2D(
                            latitude: pin.coordinate.latitude,
                            longitude: pin.coordinate.longitude
                        ),
                        tint: .purple
                    )
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
                .allowsHitTesting(false)
                .accessibilityLabel("Map location")

                MSCard(padding: MSSpacing.md) {
                    VStack(spacing: MSSpacing.sm) {
                        MSMonoValue("LAT", String(format: "%.6f", geo.latitude))
                        MSMonoValue("LON", String(format: "%.6f", geo.longitude))
                        MSMonoValue("ALT", String(format: "%.2f m", geo.altitude))
                        if let heading = map.heading {
                            MSMonoValue("HEADING", String(format: "%.1f°", heading))
                        }
                    }
                }
            }
        }
    }

    private func heatmapSection(_ map: VPSMap) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader(
                "Where it localizes",
                subtitle: heatmap.isEmpty
                    ? "No queries recorded in the last 30 days."
                    : "Plan view of the last 30 days. Red marks failed attempts."
            )
            if !heatmap.isEmpty {
                LocalizationHeatmap(samples: heatmap.flatMap(Self.samples(from:)))
                    .frame(height: 240)
                HStack(spacing: MSSpacing.lg) {
                    legend(color: MSColor.accent, label: "Located")
                    legend(color: MSColor.danger, label: "Failed")
                    Spacer(minLength: 0)
                    Text("\(heatmap.reduce(0) { $0 + ($1.count ?? 0) }) queries")
                        .font(MSFont.monoSmall)
                        .foregroundStyle(MSColor.textMuted)
                }
            }
        }
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: MSSpacing.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(MSFont.caption)
                .foregroundStyle(MSColor.textSecondary)
        }
    }

    private func overview(_ map: VPSMap) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Overview")
            MSCard(padding: MSSpacing.md) {
                VStack(spacing: MSSpacing.sm) {
                    MSMonoValue("SOURCE", map.source?.captureKind ?? "—")
                    MSMonoValue("STORAGE", map.storageDisplay ?? "—")
                    if let resolution = map.cameraIntrinsics?.resolution ?? map.resolution {
                        MSMonoValue("RESOLUTION", "\(resolution.width) × \(resolution.height)")
                    }
                    if let intrinsics = map.cameraIntrinsics?.cameraIntrinsics {
                        MSMonoValue("FX FY", String(format: "%.2f  %.2f", intrinsics.fx, intrinsics.fy))
                        MSMonoValue("PX PY", String(format: "%.2f  %.2f", intrinsics.px, intrinsics.py))
                    }
                    if let created = map.createdAt {
                        MSMonoValue("CREATED", created.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let updated = map.updatedAt {
                        MSMonoValue("UPDATED", updated.formatted(date: .abbreviated, time: .shortened))
                    }
                    MSMonoValue("ID", map.id)
                }
            }
        }
    }

    private func actions(_ map: VPSMap) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Actions")
            VStack(spacing: MSSpacing.sm) {
                Button {
                    UIPasteboard.general.string = map.mapCode
                    toast = MSToast(message: "Copied \(map.mapCode)", tone: .success)
                } label: {
                    Label("Copy map code", systemImage: "doc.on.doc")
                }
                .msButton(.secondary)

                if let link = map.mapMesh?.texturedMesh?.meshLink ?? map.mapMesh?.rawMesh?.meshLink {
                    Button {
                        Task { await openMesh(key: link) }
                    } label: {
                        Label("Download mesh", systemImage: "arrow.down.circle")
                    }
                    .msButton(.secondary)
                }

                Button {
                    openURL(ExternalLink.developerPortal)
                } label: {
                    Label("Manage in developer portal", systemImage: "arrow.up.right.square")
                }
                .msButton(.secondary)
            }
        }
    }

    private func errorState(_ error: MultiSetError) -> some View {
        VStack(spacing: MSSpacing.lg) {
            MSIllustrationView(.invalidated)
            Text(error.errorDescription ?? "")
                .font(MSFont.callout)
                .foregroundStyle(MSColor.textSecondary)
                .multilineTextAlignment(.center)
            if error.isRetryable {
                Button("Try again") { Task { await load() } }
                    .msButton(.primary, fullWidth: false)
            }
        }
        .padding(MSSpacing.xl)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await model.api.map(code: mapCode)
            map = detail
            // The heatmap is supplementary, so a failure here must not take the
            // whole screen down with it.
            heatmap = (try? await model.api.heatmap(mapId: detail.id, range: .lastDays(30))) ?? []
        } catch {
            loadError = error.asMultiSetError
        }
    }

    private func openMesh(key: String) async {
        do {
            openURL(try await model.api.fileURL(key: key))
        } catch {
            toast = MSToast(message: error.asMultiSetError.errorDescription ?? "", tone: .failure)
        }
    }

    /// Expands a cell's counts into individual samples so the density plot
    /// reflects how often each spot was queried, not just where.
    static func samples(from cell: HeatmapCell) -> [HeatmapSample] {
        let successes = cell.successCount ?? cell.count ?? 0
        let failures = cell.failureCount ?? 0
        let total = max(successes + failures, 1)
        let weight = min(Double(total) / 12, 1)
        var result = [HeatmapSample]()
        if successes > 0 {
            result.append(HeatmapSample(x: cell.x, z: cell.z, weight: weight, succeeded: true))
        }
        if failures > 0 {
            result.append(HeatmapSample(x: cell.x, z: cell.z, weight: weight, succeeded: false))
        }
        return result
    }
}

private struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: GeoCoordinates
}

#Preview {
    NavigationStack {
        MapDetailView(mapCode: "MAP_7UVHMW2TJMOA")
            .environmentObject(AppModel.preview())
    }
}
