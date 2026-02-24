import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.openWindow) private var openWindow
    @State private var errorMessage: String?
    @State private var isSwitching = false

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
                    if isSwitching {
                        ProgressView().scaleEffect(0.5)
                    } else if profile.id == store.activeProfileId {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(isSwitching)
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
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "profiles")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @MainActor
    private func switchTo(_ profile: GitProfile) {
        guard !isSwitching else { return }
        isSwitching = true
        errorMessage = nil
        let manager = GitConfigManager()
        Task {
            do {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try manager.apply(profile)
                            cont.resume()
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }
                }
                store.activeProfileId = profile.id
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isSwitching = false
        }
    }
}
