import MultiSetKit
import MultiSetUI
import SwiftUI

/// A short form, not a wizard. Everything needed to host an experience fits on
/// one screen.
struct PublishFormView: View {
    let onPublished: (ContentSpace) -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cardTitle = ""
    @State private var cardSubtitle = ""
    @State private var mode: ExperienceMode = .localize
    @State private var maps: [VPSMap] = []
    @State private var objects: [TrackedObject] = []
    @State private var selectedMapCode: String?
    @State private var selectedObjectCode: String?
    @State private var isSubmitting = false
    @State private var error: MultiSetError?

    private let titleLimit = 30
    private let subtitleLimit = 50

    private var readyMaps: [VPSMap] {
        maps.filter(\.status.isReady)
    }

    private var canPublish: Bool {
        guard !isSubmitting, !name.isEmpty, !cardTitle.isEmpty, selectedMapCode != nil else { return false }
        if mode == .track { return selectedObjectCode != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Experience") {
                    TextField("Internal name", text: $name)
                    Picker("Mode", selection: $mode) {
                        ForEach(ExperienceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Map", selection: $selectedMapCode) {
                        Text("Choose a map").tag(String?.none)
                        ForEach(readyMaps) { map in
                            Text(map.mapName).tag(Optional(map.mapCode))
                        }
                    }
                    if mode == .track {
                        Picker("Tracked object", selection: $selectedObjectCode) {
                            Text("Choose an object").tag(String?.none)
                            ForEach(objects.filter(\.status.isReady)) { object in
                                Text(object.objectName).tag(Optional(object.objectCode))
                            }
                        }
                    }
                } header: {
                    Text("Content")
                } footer: {
                    if readyMaps.isEmpty && !maps.isEmpty {
                        Text("None of your maps have finished processing yet.")
                    } else if mode == .navigate {
                        Text("Navigation also needs points of interest and a route on the map. Add those in the experience once it's created.")
                    }
                }

                Section {
                    limitedField("Card title", text: $cardTitle, limit: titleLimit)
                    limitedField("Card subtitle", text: $cardSubtitle, limit: subtitleLimit)
                } header: {
                    Text("What people see")
                } footer: {
                    Text("This is what a stranger reads on the App Clip card before anything installs.")
                }

                if let error {
                    Section {
                        Text(error.errorDescription ?? "")
                            .font(MSFont.caption)
                            .foregroundStyle(MSColor.danger)
                    }
                }
            }
            .navigationTitle("Publish experience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish", action: publish)
                        .disabled(!canPublish)
                }
            }
            .overlay { if isSubmitting { ProgressView() } }
            .task { await loadPickerData() }
        }
    }

    private func limitedField(_ title: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: MSSpacing.xxs) {
            TextField(title, text: text)
            HStack {
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(MSFont.monoSmall)
                    .foregroundStyle(text.wrappedValue.count > limit ? MSColor.danger : MSColor.textMuted)
            }
        }
    }

    private func loadPickerData() async {
        async let mapList = try? model.api.maps(page: .first, search: nil, status: nil)
        async let objectList = try? model.api.trackedObjects(page: .first, search: nil)
        maps = (await mapList)?.maps ?? []
        objects = (await objectList)?.objects ?? []
    }

    private func publish() {
        guard let mapCode = selectedMapCode else { return }
        isSubmitting = true
        error = nil
        Task {
            defer { isSubmitting = false }
            do {
                let space = try await model.api.createContentSpace(
                    ContentSpaceDraft(
                        name: name,
                        description: cardSubtitle.isEmpty ? nil : cardSubtitle,
                        target: .map(code: mapCode)
                    )
                )
                try await model.api.publishContentSpace(id: space.id)
                try await model.api.setContentSpacePublic(id: space.id, isPublic: true)
                onPublished(space)
            } catch let failure {
                error = failure.asMultiSetError
            }
        }
    }
}

#Preview {
    PublishFormView { _ in }.environmentObject(AppModel.preview())
}
