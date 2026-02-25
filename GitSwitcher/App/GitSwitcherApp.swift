import SwiftUI

@main
struct GitSwitcherApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Label(store.activeProfile?.name ?? "Git", systemImage: "person.crop.circle")
        }
        .menuBarExtraStyle(.menu)

        Window("Git Profiles", id: "profiles") {
            ProfileSettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
