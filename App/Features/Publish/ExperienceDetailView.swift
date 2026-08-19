import MultiSetKit
import MultiSetUI
import SwiftUI

/// The QR result screen. Venue staff print from here and tape it to a wall, so
/// export fidelity matters more than anything else on the screen.
struct ExperienceDetailView: View {
    let space: ContentSpace
    let onChange: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var isPublished: Bool
    @State private var toast: MSToast?
    @State private var pdfURL: URL?
    @State private var pngURL: URL?
    @State private var paper: PrintableSheet.PaperSize = .a4
    @State private var testingManifest: ExperienceManifest?
    @State private var showsRevokeConfirmation = false

    init(space: ContentSpace, onChange: @escaping () -> Void) {
        self.space = space
        self.onChange = onChange
        _isPublished = State(initialValue: space.isPublished)
    }

    private var shareURL: String {
        space.shareURL?.absoluteString ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MSSpacing.xl) {
                qrBlock
                urlBlock
                exportBlock
                actionsBlock
                clipCardNote
            }
            .padding(MSSpacing.lg)
        }
        .background(MSColor.background.ignoresSafeArea())
        .navigationTitle(space.name)
        .navigationBarTitleDisplayMode(.inline)
        .msToast($toast)
        .fullScreenCover(item: $testingManifest) { manifest in
            ExperienceRunner(manifest: manifest) { testingManifest = nil }
        }
        .confirmationDialog(
            "Revoke this experience?",
            isPresented: $showsRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) { Task { await setPublished(false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone scanning the printed code will be told the experience has ended. The code itself stays valid, so you can publish again without reprinting.")
        }
    }

    private var qrBlock: some View {
        VStack(spacing: MSSpacing.md) {
            if let image = QRCode.image(for: shareURL, side: 1024) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .padding(MSSpacing.lg)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: MSRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: MSRadius.lg)
                            .strokeBorder(MSColor.borderSubtle, lineWidth: 1)
                    )
                    .accessibilityLabel("QR code for \(space.name)")
            }
            MSStatusPill(
                isPublished ? "Live" : "Revoked",
                tone: isPublished ? .positive : .neutral,
                systemImage: isPublished ? "checkmark.circle.fill" : "pause.circle.fill"
            )
        }
    }

    private var urlBlock: some View {
        Button {
            UIPasteboard.general.string = shareURL
            toast = MSToast(message: "Link copied", tone: .success)
        } label: {
            MSCard(padding: MSSpacing.md) {
                HStack(spacing: MSSpacing.sm) {
                    Text(shareURL)
                        .font(MSFont.mono)
                        .foregroundStyle(MSColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(MSColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy link \(shareURL)")
    }

    private var exportBlock: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Print it", subtitle: "Quiet-zone margins are preserved so it scans at two metres.")

            Picker("Paper", selection: $paper) {
                Text("A4").tag(PrintableSheet.PaperSize.a4)
                Text("US Letter").tag(PrintableSheet.PaperSize.usLetter)
            }
            .pickerStyle(.segmented)

            VStack(spacing: MSSpacing.sm) {
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share the PDF", systemImage: "square.and.arrow.up")
                    }
                    .msButton(.primary)
                } else {
                    Button("Export as PDF") { exportPDF() }
                        .msButton(.primary)
                }

                if let pngURL {
                    ShareLink(item: pngURL) {
                        Label("Share the PNG", systemImage: "square.and.arrow.up")
                    }
                    .msButton(.secondary)
                } else {
                    Button("Export as PNG") { exportPNG() }
                        .msButton(.secondary)
                }
            }
        }
        .onChange(of: paper) { _ in pdfURL = nil }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: MSSpacing.md) {
            MSSectionHeader("Manage")
            VStack(spacing: MSSpacing.sm) {
                Button("Test on this device") { Task { await test() } }
                    .msButton(.secondary)
                    .disabled(!isPublished)

                if isPublished {
                    Button("Revoke") { showsRevokeConfirmation = true }
                        .msButton(.destructive)
                } else {
                    Button("Publish again") { Task { await setPublished(true) } }
                        .msButton(.primary)
                }
            }
        }
    }

    private var clipCardNote: some View {
        MSCard(padding: MSSpacing.md) {
            VStack(alignment: .leading, spacing: MSSpacing.sm) {
                Label("About the App Clip card", systemImage: "info.circle")
                    .font(MSFont.captionEmphasis)
                    .foregroundStyle(MSColor.textSecondary)
                Text("The image and text shown before the Clip downloads are configured per experience in App Store Connect, not here.")
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Read Apple's guide") { openURL(ExternalLink.appClipDocs) }
                    .font(MSFont.caption)
                    .foregroundStyle(MSColor.accent)
            }
        }
    }

    // MARK: - Actions

    private func exportPDF() {
        guard let data = PrintableSheet.pdfData(
            url: shareURL,
            title: space.name,
            subtitle: space.description,
            paper: paper
        ) else {
            toast = MSToast(message: "Couldn't build the PDF.", tone: .failure)
            return
        }
        pdfURL = PrintableSheet.write(
            data: data,
            filename: "MultiSet-\(space.spaceCode)-\(paper.displayName).pdf"
        )
        if pdfURL == nil {
            toast = MSToast(message: "Couldn't save the PDF.", tone: .failure)
        }
    }

    private func exportPNG() {
        guard let image = QRCode.image(for: shareURL, side: 2048),
              let data = image.pngData()
        else {
            toast = MSToast(message: "Couldn't build the PNG.", tone: .failure)
            return
        }
        pngURL = PrintableSheet.write(data: data, filename: "MultiSet-\(space.spaceCode).png")
        if pngURL == nil {
            toast = MSToast(message: "Couldn't save the PNG.", tone: .failure)
        }
    }

    private func test() async {
        do {
            testingManifest = try await model.api.resolveExperience(spaceCode: space.spaceCode)
        } catch {
            toast = MSToast(
                message: error.asMultiSetError.errorDescription ?? "Couldn't open it.",
                tone: .failure
            )
        }
    }

    private func setPublished(_ published: Bool) async {
        do {
            if published {
                try await model.api.publishContentSpace(id: space.id)
            } else {
                try await model.api.unpublishContentSpace(id: space.id)
            }
            isPublished = published
            onChange()
            toast = MSToast(message: published ? "Published" : "Revoked", tone: .success)
        } catch {
            toast = MSToast(
                message: error.asMultiSetError.errorDescription ?? "Couldn't change it.",
                tone: .failure
            )
        }
    }
}

#Preview {
    NavigationStack {
        ExperienceDetailView(space: Fixtures.contentSpaces[0]) {}
            .environmentObject(AppModel.preview())
    }
}
