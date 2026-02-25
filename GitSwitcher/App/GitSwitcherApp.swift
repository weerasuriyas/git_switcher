import SwiftUI

@main
struct GitSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("Git", systemImage: "person.crop.circle") {
            ContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}
