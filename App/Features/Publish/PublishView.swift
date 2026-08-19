import MultiSetKit
import MultiSetUI
import SwiftUI

struct PublishView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var list = ResourceListModel<ContentSpace>()
    @State private var showsSignIn = false
    @State private var showsForm = false
    @State private var toast: MSToast?

    var body: some View {
        NavigationStack {
            Group {
                if model.isSignedIn {
                    content
                } else {
                    signedOut
                }
            }
            .background(MSColor.background.ignoresSafeArea())
            .navigationTitle("Publish")
            .toolbar {
                if model.isSignedIn {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsForm = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Publish a new experience")
                    }
                }
            }
            .sheet(isPresented: $showsSignIn) { SignInView() }
            .sheet(isPresented: $showsForm) {
                PublishFormView { _ in
                    showsForm = false
                    list.reload()
                    toast = MSToast(message: "Published", tone: .success)
                }
            }
            .msToast($toast)
            .task {
                guard list.items.isEmpty else { return }
                let api = model.api
                list.rebind { query in
                    try await api.contentSpaces(page: .first, search: query.isEmpty ? nil : query).spaces
                }
                list.reload()
            }
        }
    }

    private var content: some View {
        ResourceList(
            list: list,
            emptyIllustration: .noMaps,
            emptyTitle: "No experiences yet",
            emptyMessage: "Publish a map as an experience and you get a QR code anyone can scan — no install, no account."
        ) { space in
            NavigationLink {
                ExperienceDetailView(space: space) { list.reload() }
            } label: {
                ExperienceRow(space: space)
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $list.searchText, prompt: "Search experiences")
        .onChange(of: list.searchText) { _ in list.searchChanged() }
    }

    private var signedOut: some View {
        MSEmptyState(
            .noMaps,
            title: "Sign in to publish",
            message: "Publishing hosts one of your maps behind a QR code that works without an install."
        ) {
            Button("Sign in") { showsSignIn = true }
                .msButton(.primary, fullWidth: false)
        }
        .frame(maxHeight: .infinity)
    }
}

struct ExperienceRow: View {
    let space: ContentSpace

    var body: some View {
        MSCard(padding: MSSpacing.md) {
            HStack(spacing: MSSpacing.md) {
                if let url = space.shareURL?.absoluteString, let image = QRCode.image(for: url, side: 200) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: MSSize.thumbnail, height: MSSize.thumbnail)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: MSRadius.sm))
                }
                VStack(alignment: .leading, spacing: MSSpacing.xs) {
                    Text(space.name)
                        .font(MSFont.bodyEmphasis)
                        .foregroundStyle(MSColor.textPrimary)
                        .lineLimit(2)
                    Text(space.spaceCode)
                        .font(MSFont.monoSmall)
                        .foregroundStyle(MSColor.textMuted)
                    HStack(spacing: MSSpacing.xs) {
                        MSStatusPill(
                            space.isPublished ? "Live" : "Draft",
                            tone: space.isPublished ? .positive : .neutral
                        )
                        if space.isPublic == true {
                            MSStatusPill("Public", tone: .accent, systemImage: "globe")
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
        .accessibilityLabel("\(space.name), code \(space.spaceCode), \(space.isPublished ? "live" : "draft")")
    }
}

#Preview("Signed in") {
    PublishView().environmentObject(AppModel.preview())
}

#Preview("Signed out") {
    PublishView().environmentObject(AppModel.preview(session: .signedOut))
}
