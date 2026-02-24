import Foundation
import os

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [GitProfile] = []

    private var _activeProfileId: UUID?
    var activeProfileId: UUID? {
        get { _activeProfileId }
        set {
            _activeProfileId = newValue
            saveActiveId()
        }
    }

    var activeProfile: GitProfile? {
        profiles.first(where: { $0.id == activeProfileId })
    }

    private let profilesURL: URL
    private let activeIdURL: URL

    init(storageDirectory: String = "\(NSHomeDirectory())/.config/git-profile-switcher") {
        let dir = URL(fileURLWithPath: storageDirectory)
        profilesURL = dir.appendingPathComponent("profiles.json")
        activeIdURL = dir.appendingPathComponent("active.txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            os_log(.error, "ProfileStore: failed to create storage directory: %{public}@", error.localizedDescription)
        }
        load()
    }

    func add(_ profile: GitProfile) {
        profiles.append(profile)
        save()
    }

    func update(_ profile: GitProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func delete(_ profile: GitProfile) {
        profiles.removeAll { $0.id == profile.id }
        if _activeProfileId == profile.id {
            _activeProfileId = nil
            saveActiveId()
        }
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: profilesURL) {
            profiles = (try? JSONDecoder().decode([GitProfile].self, from: data)) ?? []
        }
        if let raw = try? String(contentsOf: activeIdURL),
           let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            _activeProfileId = id
        }
        // Clear orphaned activeProfileId
        if let id = _activeProfileId, !profiles.contains(where: { $0.id == id }) {
            _activeProfileId = nil
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesURL, options: .atomic)
        } catch {
            os_log(.error, "ProfileStore: failed to save profiles: %{public}@", error.localizedDescription)
        }
    }

    private func saveActiveId() {
        let raw = _activeProfileId?.uuidString ?? ""
        do {
            try raw.write(to: activeIdURL, atomically: true, encoding: .utf8)
        } catch {
            os_log(.error, "ProfileStore: failed to save activeProfileId: %{public}@", error.localizedDescription)
        }
    }
}
