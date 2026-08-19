import MultiSetKit
import MultiSetUI
import SwiftUI

@main
struct MultiSetARApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(MSColor.accent)
                .task { await model.restoreSession() }
                // The parent app handles the same URLs as the Clip. Apple requires
                // it, and it is how a developer verifies a QR without a second device.
                .onOpenURL { model.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        model.handle(url: url)
                    }
                }
        }
    }
}
