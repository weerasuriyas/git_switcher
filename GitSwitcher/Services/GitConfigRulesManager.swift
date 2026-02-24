import Foundation
import os

enum GitConfigRulesError: LocalizedError {
    case notAGitRepo(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let path): return "Not a git repository: \(path)"
        case .writeFailed(let msg): return "Failed to write git config: \(msg)"
        }
    }
}

@MainActor
struct GitConfigRulesManager {
    private let globalConfigPath: String
    private let storageDirectory: String

    private let markerBegin = "# >>> git-profile-switcher managed — do not edit manually <<<"
    private let markerEnd   = "# <<< git-profile-switcher managed >>>"

    init(
        globalConfigPath: String = "\(NSHomeDirectory())/.gitconfig",
        storageDirectory: String = "\(NSHomeDirectory())/.config/git-profile-switcher"
    ) {
        self.globalConfigPath = globalConfigPath
        self.storageDirectory = storageDirectory
    }

    // MARK: - Companion configs

    func writeCompanionConfig(for profile: GitProfile) throws {
        var content = "[user]\n\tname = \(profile.gitName)\n\temail = \(profile.gitEmail)\n"
        if let sshKey = profile.sshKeyPath, !sshKey.isEmpty {
            let quoted = "'" + sshKey.replacingOccurrences(of: "'", with: "'\\''") + "'"
            content += "[core]\n\tsshCommand = ssh -i \(quoted) -o IdentitiesOnly=yes\n"
        }
        do {
            try content.write(to: companionURL(for: profile), atomically: true, encoding: .utf8)
        } catch {
            throw GitConfigRulesError.writeFailed(error.localizedDescription)
        }
    }

    func removeCompanionConfig(for profile: GitProfile) throws {
        let url = companionURL(for: profile)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - includeIf management

    func apply(profiles: [GitProfile]) throws {
        // Build managed lines
        var lines: [String] = []
        for profile in profiles {
            for rule in profile.directoryRules {
                let path = rule.hasSuffix("/") ? rule : rule + "/"
                lines.append("[includeIf \"gitdir/i:\(path)\"]")
                lines.append("\tpath = \(companionURL(for: profile).path)")
            }
        }

        // Write/remove companion configs (before modifying global config)
        for profile in profiles {
            if profile.directoryRules.isEmpty {
                try? removeCompanionConfig(for: profile)
            } else {
                try writeCompanionConfig(for: profile)
            }
        }

        // Read existing global config
        let configURL = URL(fileURLWithPath: globalConfigPath)
        let existing = (try? String(contentsOf: configURL)) ?? ""

        let newContent: String
        let managedSection = lines.isEmpty ? "" : buildManagedSection(lines: lines)

        if existing.contains(markerBegin) {
            // Replace managed section between markers using safe string range replacement
            guard let startRange = existing.range(of: markerBegin),
                  let endRange = existing.range(of: markerEnd) else {
                // Markers corrupted — append fresh or clear
                newContent = existing + managedSection
                // Fall through to write
                try write(newContent, to: configURL)
                return
            }
            var sectionEnd = endRange.upperBound
            if sectionEnd < existing.endIndex && existing[sectionEnd] == "\n" {
                sectionEnd = existing.index(after: sectionEnd)
            }
            newContent = existing.replacingCharacters(in: startRange.lowerBound..<sectionEnd, with: managedSection)
        } else if managedSection.isEmpty {
            newContent = existing
        } else {
            let separator = (existing.isEmpty || existing.hasSuffix("\n")) ? "" : "\n"
            newContent = existing + separator + managedSection
        }

        try write(newContent, to: configURL)
    }

    // MARK: - Repo overrides

    func writeRepoOverride(repoPath: String, profile: GitProfile) throws {
        guard FileManager.default.fileExists(atPath: "\(repoPath)/.git") else {
            throw GitConfigRulesError.notAGitRepo(repoPath)
        }
        let gitConfigPath = "\(repoPath)/.git/config"
        try runGit("git", "config", "--file", gitConfigPath, "user.name", profile.gitName)
        try runGit("git", "config", "--file", gitConfigPath, "user.email", profile.gitEmail)
    }

    func removeRepoOverride(repoPath: String) throws {
        guard FileManager.default.fileExists(atPath: "\(repoPath)/.git") else { return }
        let gitConfigPath = "\(repoPath)/.git/config"
        // --remove-section exits 5 if section doesn't exist — ignore that
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "config", "--file", gitConfigPath, "--remove-section", "user"]
        try? p.run(); p.waitUntilExit()
    }

    // MARK: - Private

    private func companionURL(for profile: GitProfile) -> URL {
        URL(fileURLWithPath: storageDirectory).appendingPathComponent("\(profile.id.uuidString).gitconfig")
    }

    private func buildManagedSection(lines: [String]) -> String {
        ([markerBegin] + lines + [markerEnd]).joined(separator: "\n") + "\n"
    }

    private func write(_ content: String, to url: URL) throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw GitConfigRulesError.writeFailed(error.localizedDescription)
        }
    }

    private func runGit(_ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let errPipe = Pipe()
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitConfigRulesError.writeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
