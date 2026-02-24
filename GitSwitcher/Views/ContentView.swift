import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var showingSettings = false
    @State private var errorMessage: String?

    var body: some View {
        // Active profile header
        if let active = store.activeProfile {
            Text(active.gitName)
                .font(.headline)
            Text(active.gitEmail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
        }

        // Profile list
        ForEach(store.profiles) { profile in
            Button {
                switchTo(profile)
            } label: {
                HStack {
                    Text(profile.name)
                    Spacer()
                    if profile.id == store.activeProfileId {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        if store.profiles.isEmpty {
            Text("No profiles yet")
                .foregroundStyle(.secondary)
        }

        Divider()

        if let error = errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
            Divider()
        }

        Button("Manage Profiles…") {
            showingSettings = true
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        .sheet(isPresented: $showingSettings) {
            ProfileSettingsView()
                .environmentObject(store)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func switchTo(_ profile: GitProfile) {
        let manager = GitConfigManager()
        do {
            try manager.apply(profile)
            store.activeProfileId = profile.id
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
