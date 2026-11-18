import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            NavigationStack { SetupView() }
                .tabItem { Label("Setup", systemImage: "gearshape") }
            NavigationStack { SignalsView() }
                .tabItem { Label("Found", systemImage: "dot.radiowaves.left.and.right") }
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                Task { await SyncCoordinator.shared.syncAll(reason: "App opened") }
            }
        }
    }
}
