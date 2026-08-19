import MultiSetARCore
import MultiSetKit
import MultiSetUI
import SwiftUI

struct ObjectDetailView: View {
    let object: TrackedObject

    @EnvironmentObject private var model: AppModel
    @State private var runningMode: SDKRunner.Mode?
    @State private var toast: MSToast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MSSpacing.xl) {
                header
                testTracking
                overview
                actions
            }
            .padding(MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
        .navigationTitle(object.objectName)
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
                    object.status.displayName,
                    tone: object.status == .active ? .positive : .caution
                )
                if let type = object.trackingType {
                    MSStatusPill(type.uppercased(), tone: .neutral)
                }
            }
            Text(object.objectCode)
                .font(MSFont.monoLarge)
                .foregroundStyle(MSColor.textPrimary)
                .textSelection(.enabled)
        }
    }

    private var testTracking: some View {
        MSCard {
            VStack(alignment: .leading, spacing: MSSpacing.md) {
                Text("Test tracking")
                    .font(MSFont.headline)
                    .foregroundStyle(MSColor.textPrimary)
                Text("Point the camera at the object. On a match its mesh downloads and traces the real object's outline, holding position as you move around it.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start tracking") {
                    runningMode = .trackObjects(codes: [object.objectCode])
                }
                .msButton(.primary, fullWidth: false)
                .disabled(!object.status.isReady)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Overview")
            MSCard(padding: MSSpacing.md) {
                VStack(spacing: MSSpacing.sm) {
                    MSMonoValue("TYPE", object.trackingType?.uppercased() ?? "—")
                    MSMonoValue("SOURCE", object.source?.captureKind ?? "—")
                    if let storage = object.storage {
                        MSMonoValue("STORAGE", ByteCountFormatter.string(
                            fromByteCount: Int64(storage * 1024),
                            countStyle: .file
                        ))
                    }
                    if let created = object.createdAt {
                        MSMonoValue("CREATED", created.formatted(date: .abbreviated, time: .shortened))
                    }
                    MSMonoValue("ID", object.id)
                }
            }
        }
    }

    private var actions: some View {
        Button {
            UIPasteboard.general.string = object.objectCode
            toast = MSToast(message: "Copied \(object.objectCode)", tone: .success)
        } label: {
            Label("Copy object code", systemImage: "doc.on.doc")
        }
        .msButton(.secondary)
    }
}

#Preview {
    NavigationStack {
        ObjectDetailView(object: Fixtures.objects[0])
            .environmentObject(AppModel.preview())
    }
}
