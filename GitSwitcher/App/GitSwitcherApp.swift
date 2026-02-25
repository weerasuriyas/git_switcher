import SwiftUI

@main
struct GitSwitcherApp: App {
    @StateObject private var service = GHCLIService()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(service)
        } label: {
            Label(
                service.activeAccount?.login ?? "Git",
                systemImage: "person.crop.circle"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
