import MultiSetKit
import MultiSetUI
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .msToast($model.toast)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbolName)
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .library: LibraryView()
        case .publish: PublishView()
        case .learn: LearnView()
        case .settings: SettingsView()
        }
    }
}

#Preview("Signed in") {
    RootView().environmentObject(AppModel.preview())
}

#Preview("Signed out") {
    RootView().environmentObject(AppModel.preview(session: .signedOut))
}
