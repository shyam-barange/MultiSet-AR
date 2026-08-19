import MultiSetKit
import MultiSetUI
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scope: Scope = .maps
    @State private var showsSignIn = false

    enum Scope: String, CaseIterable, Identifiable {
        case maps, mapSets, objects
        var id: String { rawValue }

        var title: String {
            switch self {
            case .maps: "Maps"
            case .mapSets: "Map sets"
            case .objects: "Objects"
            }
        }
    }

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
            .navigationTitle("Library")
            .sheet(isPresented: $showsSignIn) { SignInView() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MSSpacing.lg)
            .padding(.bottom, MSSpacing.sm)

            switch scope {
            case .maps: MapListView()
            case .mapSets: MapSetListView()
            case .objects: ObjectListView()
            }
        }
    }

    private var signedOut: some View {
        MSEmptyState(
            .noMaps,
            title: "Sign in to see your maps",
            message: "Your maps, map sets, and tracked objects live in your MultiSet account."
        ) {
            Button("Sign in") { showsSignIn = true }
                .msButton(.primary, fullWidth: false)
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview("Signed in") {
    LibraryView().environmentObject(AppModel.preview())
}

#Preview("Signed out") {
    LibraryView().environmentObject(AppModel.preview(session: .signedOut))
}
