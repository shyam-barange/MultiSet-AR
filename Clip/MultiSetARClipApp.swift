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
                .task {
                    #if DEBUG
                    // Xcode's `_XCAppClipURL` scheme variable is what normally drives
                    // an invocation in development, but only Xcode synthesises the
                    // user activity from it — `simctl` sets the variable and nothing
                    // reads it. This makes the same flow reachable from the command
                    // line, which is the only way to exercise the failure states
                    // without a device:
                    //   xcrun simctl launch <device> com.multiset.sdk.Clip \
                    //       -MSClipURL "https://api.multiset.ai/space/<code>"
                    // Debug only, so a shipping Clip can only ever be invoked for real.
                    if let override = UserDefaults.standard.string(forKey: "MSClipURL"),
                       let url = URL(string: override) {
                        await model.handle(url: url)
                    }
                    #endif
                }
        }
    }
}
