import MultiSetKit
import MultiSetUI
import SwiftUI

/// The App Clip.
///
/// A launcher with three screens: resolving, intro card, AR session. It links
/// `MultiSetKit` and `MultiSetARCore` only — never `MultiSetSDK`, which requires
/// a clientId and clientSecret. The Clip runs for anonymous strangers, so a
/// credential in this binary would bill the developer's account to whoever
/// scanned the code.
@main
struct MultiSetARClipApp: App {
    @StateObject private var model = ClipModel()

    var body: some Scene {
        WindowGroup {
            ClipShellView()
                .environmentObject(model)
                .tint(MSColor.accent)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else {
                        model.rejectMissingInvocation()
                        return
                    }
                    Task { await model.handle(url: url) }
                }
        }
    }
}
