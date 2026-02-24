import Foundation
import Combine

final class ProfileStore: ObservableObject {
    @Published var profiles: [GitProfile] = []
    @Published var activeProfileId: UUID? {
        didSet { saveActiveId() }
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
        if activeProfileId == profile.id {
            activeProfileId = nil
        }
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: profilesURL) {
            profiles = (try? JSONDecoder().decode([GitProfile].self, from: data)) ?? []
        }
        if let raw = try? String(contentsOf: activeIdURL),
           let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            activeProfileId = id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: profilesURL)
        }
    }

    private func saveActiveId() {
        let raw = activeProfileId?.uuidString ?? ""
        try? raw.write(to: activeIdURL, atomically: true, encoding: .utf8)
    }
}
