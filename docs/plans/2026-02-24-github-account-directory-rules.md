# GitHub Account Import + Directory Rules Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users import Git profiles from GitHub (via `gh` CLI or username lookup) and assign profiles to folders/repos so git auto-applies the right identity without the app running.

**Architecture:** Extend `GitProfile` with `directoryRules` + `repoOverrides` arrays. New `GitHubImporter` fetches name/email from GitHub. New `GitConfigRulesManager` owns the `includeIf` section of `~/.gitconfig` (bracketed by marker comments) and writes per-profile companion `.gitconfig` files. `ProfileStore` calls the rules manager on every save/update/delete. `ProfileFormView` gains a GitHub import button and folder/repo pickers.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation (URLSession, Process), XCTest, xcodegen

**Work in:** `/Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp`

---

### Context for all tasks

Existing files you'll be working with:
- `GitSwitcher/Models/GitProfile.swift` — data model
- `GitSwitcher/Services/GitConfigManager.swift` — Process helper (reuse `run`/`runOutput` patterns)
- `GitSwitcher/Services/ProfileStore.swift` — @MainActor ObservableObject
- `GitSwitcher/Views/ProfileSettingsView.swift` — profile CRUD UI
- `GitSwitcherTests/` — existing tests, all must continue to pass

After writing any new `.swift` file, run `xcodegen generate` in the worktree to pick it up before building/testing.

---

### Task 1: Extend GitProfile Model

**Files:**
- Modify: `GitSwitcher/Models/GitProfile.swift`
- Modify: `GitSwitcherTests/GitProfileTests.swift`

---

**Step 1: Write failing test for new fields**

Add to `GitSwitcherTests/GitProfileTests.swift`:

```swift
func test_new_fields_default_to_empty() {
    let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
    XCTAssertNil(profile.githubLogin)
    XCTAssertTrue(profile.directoryRules.isEmpty)
    XCTAssertTrue(profile.repoOverrides.isEmpty)
}

func test_new_fields_roundtrip() throws {
    var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
    profile.githubLogin = "bobwork"
    profile.directoryRules = ["/Users/bob/work"]
    profile.repoOverrides = ["/Users/bob/personal/dotfiles"]
    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
    XCTAssertEqual(decoded, profile)
    XCTAssertEqual(decoded.directoryRules, ["/Users/bob/work"])
    XCTAssertEqual(decoded.repoOverrides, ["/Users/bob/personal/dotfiles"])
}

func test_old_json_without_new_fields_still_decodes() throws {
    // Profiles saved by v1 of the app have no directoryRules/repoOverrides
    let json = """
    {"id":"00000000-0000-0000-0000-000000000003","name":"Work","gitName":"Bob","gitEmail":"bob@work.com"}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(GitProfile.self, from: json)
    XCTAssertTrue(decoded.directoryRules.isEmpty)
    XCTAssertTrue(decoded.repoOverrides.isEmpty)
    XCTAssertNil(decoded.githubLogin)
}
```

**Step 2: Run to confirm failure**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED" | head -5
```

Expected: `error: value of type 'GitProfile' has no member 'githubLogin'`

**Step 3: Update `GitSwitcher/Models/GitProfile.swift`**

Replace the entire file:

```swift
import Foundation

struct GitProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gitName: String
    var gitEmail: String
    var sshKeyPath: String?
    var signingKey: String?
    var signingFormat: String?
    var githubLogin: String?
    var directoryRules: [String]
    var repoOverrides: [String]

    init(
        id: UUID = UUID(),
        name: String,
        gitName: String,
        gitEmail: String,
        sshKeyPath: String? = nil,
        signingKey: String? = nil,
        signingFormat: String? = nil,
        githubLogin: String? = nil,
        directoryRules: [String] = [],
        repoOverrides: [String] = []
    ) {
        self.id = id
        self.name = name
        self.gitName = gitName
        self.gitEmail = gitEmail
        self.sshKeyPath = sshKeyPath
        self.signingKey = signingKey
        self.signingFormat = signingFormat
        self.githubLogin = githubLogin
        self.directoryRules = directoryRules
        self.repoOverrides = repoOverrides
    }
}
```

**Step 4: Run all tests**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed" | tail -5
```

Expected: all tests pass (existing 11 + 3 new = 14 total).

**Step 5: Commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add GitSwitcher/Models/GitProfile.swift GitSwitcherTests/GitProfileTests.swift
git commit -m "feat: add githubLogin, directoryRules, repoOverrides to GitProfile"
```

---

### Task 2: GitHubImporter Service

Fetches name/email/login from GitHub. Pure parsing functions tested in isolation; I/O strategies tested with real subprocess output.

**Files:**
- Create: `GitSwitcher/Services/GitHubImporter.swift`
- Create: `GitSwitcherTests/GitHubImporterTests.swift`

---

**Step 1: Write failing tests**

Create `GitSwitcherTests/GitHubImporterTests.swift`:

```swift
import XCTest
@testable import GitSwitcher

final class GitHubImporterTests: XCTestCase {

    // MARK: - JSON parsing (pure, no I/O)

    func test_parse_gh_output_extracts_name_email_login() throws {
        let json = """
        {"login":"shanew","name":"Shane W","email":"shane@example.com","id":12345}
        """
        let result = try GitHubImporter.parseUserJSON(json)
        XCTAssertEqual(result.login, "shanew")
        XCTAssertEqual(result.name, "Shane W")
        XCTAssertEqual(result.email, "shane@example.com")
    }

    func test_parse_gh_output_nil_email_when_missing() throws {
        let json = """
        {"login":"shanew","name":"Shane W","email":null,"id":12345}
        """
        let result = try GitHubImporter.parseUserJSON(json)
        XCTAssertNil(result.email)
    }

    func test_parse_gh_output_throws_on_invalid_json() {
        XCTAssertThrowsError(try GitHubImporter.parseUserJSON("not json")) { error in
            XCTAssertTrue(error is DecodingError || error is GitHubImportError)
        }
    }

    func test_parse_gh_output_throws_on_missing_login() {
        let json = """{"name":"Shane W"}"""
        XCTAssertThrowsError(try GitHubImporter.parseUserJSON(json))
    }

    // MARK: - gh CLI detection

    func test_gh_not_available_returns_false() {
        // Point to a nonexistent path to simulate gh not installed
        let importer = GitHubImporter(ghPath: "/nonexistent/gh")
        XCTAssertFalse(importer.isGHAvailable())
    }
}
```

**Step 2: Run to confirm failure**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED" | head -5
```

Expected: `error: cannot find 'GitHubImporter' in scope`

**Step 3: Implement `GitSwitcher/Services/GitHubImporter.swift`**

```swift
import Foundation

struct GitHubUserInfo {
    let login: String
    let name: String
    let email: String?
}

enum GitHubImportError: LocalizedError {
    case ghNotAvailable
    case commandFailed(String)
    case userNotFound(String)
    case networkError(Error)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .ghNotAvailable:
            return "GitHub CLI (gh) is not installed. Install it with: brew install gh"
        case .commandFailed(let msg):
            return "GitHub CLI failed: \(msg)"
        case .userNotFound(let username):
            return "GitHub user '\(username)' not found"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .parseError(let msg):
            return "Could not parse GitHub response: \(msg)"
        }
    }
}

struct GitHubImporter {
    let ghPath: String

    init(ghPath: String? = nil) {
        // Locate gh in common install paths
        if let path = ghPath {
            self.ghPath = path
        } else {
            let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            self.ghPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/gh"
        }
    }

    // MARK: - Pure parsing (static, testable without I/O)

    static func parseUserJSON(_ jsonString: String) throws -> GitHubUserInfo {
        guard let data = jsonString.data(using: .utf8) else {
            throw GitHubImportError.parseError("Invalid string encoding")
        }
        struct Response: Decodable {
            let login: String
            let name: String?
            let email: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return GitHubUserInfo(
            login: response.login,
            name: response.name ?? response.login,
            email: response.email
        )
    }

    // MARK: - Strategy A: gh CLI

    func isGHAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: ghPath)
    }

    func importViaGHCLI() throws -> GitHubUserInfo {
        guard isGHAvailable() else { throw GitHubImportError.ghNotAvailable }

        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = ["api", "user"]
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitHubImportError.commandFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return try Self.parseUserJSON(output)
    }

    // MARK: - Strategy B: Public GitHub API (unauthenticated)

    func importViaUsername(_ username: String) async throws -> GitHubUserInfo {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubImportError.userNotFound(username)
        }

        let url = URL(string: "https://api.github.com/users/\(trimmed)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitSwitcher/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubImportError.networkError(URLError(.badServerResponse))
        }
        guard http.statusCode == 200 else {
            throw GitHubImportError.userNotFound(trimmed)
        }

        let json = String(data: data, encoding: .utf8) ?? ""
        return try Self.parseUserJSON(json)
    }
}
```

**Step 4: Run all tests**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodegen generate && xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed" | tail -5
```

Expected: all 19 tests pass (14 + 5 new).

**Step 5: Commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add GitSwitcher/Services/GitHubImporter.swift GitSwitcherTests/GitHubImporterTests.swift
git commit -m "feat: add GitHubImporter with gh CLI and public API strategies"
```

---

### Task 3: GitConfigRulesManager

Owns the `includeIf` section of `~/.gitconfig` (bracketed by marker comments) and writes per-profile companion `.gitconfig` files. Also handles per-repo overrides.

**Files:**
- Create: `GitSwitcher/Services/GitConfigRulesManager.swift`
- Create: `GitSwitcherTests/GitConfigRulesManagerTests.swift`

---

**Step 1: Write failing tests**

Create `GitSwitcherTests/GitConfigRulesManagerTests.swift`:

```swift
import XCTest
@testable import GitSwitcher

final class GitConfigRulesManagerTests: XCTestCase {
    var tempDir: URL!
    var globalConfigURL: URL!
    var storageDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        globalConfigURL = tempDir.appendingPathComponent("gitconfig")
        storageDir = tempDir.appendingPathComponent("storage")
        try! FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        // Create empty global config
        FileManager.default.createFile(atPath: globalConfigURL.path, contents: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func makeManager() -> GitConfigRulesManager {
        GitConfigRulesManager(globalConfigPath: globalConfigURL.path, storageDirectory: storageDir.path)
    }

    // MARK: - Companion config

    func test_write_companion_config_creates_file() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]

        try manager.writeCompanionConfig(for: profile)

        let companionURL = storageDir.appendingPathComponent("\(profile.id.uuidString).gitconfig")
        XCTAssertTrue(FileManager.default.fileExists(atPath: companionURL.path))
        let content = try String(contentsOf: companionURL)
        XCTAssertTrue(content.contains("name = Bob"))
        XCTAssertTrue(content.contains("email = bob@work.com"))
    }

    func test_remove_companion_config_deletes_file() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.writeCompanionConfig(for: profile)

        try manager.removeCompanionConfig(for: profile)

        let companionURL = storageDir.appendingPathComponent("\(profile.id.uuidString).gitconfig")
        XCTAssertFalse(FileManager.default.fileExists(atPath: companionURL.path))
    }

    // MARK: - includeIf rules in global config

    func test_apply_writes_includif_block_for_directory_rule() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]

        try manager.apply(profiles: [profile])

        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("includeIf"))
        XCTAssertTrue(content.contains("/Users/bob/work/"))
        XCTAssertTrue(content.contains("\(profile.id.uuidString).gitconfig"))
    }

    func test_apply_with_no_rules_leaves_config_empty_of_managed_section() throws {
        let manager = makeManager()
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        // No directoryRules

        try manager.apply(profiles: [profile])

        let content = try String(contentsOf: globalConfigURL)
        XCTAssertFalse(content.contains("includeIf"))
    }

    func test_apply_replaces_existing_managed_section() throws {
        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.apply(profiles: [profile])

        // Now update to a different directory
        profile.directoryRules = ["/Users/bob/newwork"]
        try manager.apply(profiles: [profile])

        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("/Users/bob/newwork/"))
        XCTAssertFalse(content.contains("/Users/bob/work/"))
    }

    func test_apply_preserves_existing_non_managed_content() throws {
        // Pre-populate the global config with user content
        let existing = "[user]\n\tname = Alice\n\temail = alice@example.com\n"
        try existing.write(to: globalConfigURL, atomically: true, encoding: .utf8)

        let manager = makeManager()
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.directoryRules = ["/Users/bob/work"]
        try manager.apply(profiles: [profile])

        let content = try String(contentsOf: globalConfigURL)
        XCTAssertTrue(content.contains("name = Alice"))    // preserved
        XCTAssertTrue(content.contains("includeIf"))       // added
    }

    // MARK: - Repo overrides

    func test_write_repo_override_writes_to_git_config() throws {
        // Create a fake repo dir with a .git folder
        let repoDir = tempDir.appendingPathComponent("myrepo")
        let gitDir = repoDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let gitConfigFile = gitDir.appendingPathComponent("config")
        FileManager.default.createFile(atPath: gitConfigFile.path, contents: nil)

        let manager = makeManager()
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")

        try manager.writeRepoOverride(repoPath: repoDir.path, profile: profile)

        let content = try String(contentsOf: gitConfigFile)
        XCTAssertTrue(content.contains("name = Alice"))
        XCTAssertTrue(content.contains("email = alice@home.io"))
    }

    func test_write_repo_override_throws_if_not_a_git_repo() {
        let notARepo = tempDir.appendingPathComponent("notarepo")
        try! FileManager.default.createDirectory(at: notARepo, withIntermediateDirectories: true)
        let manager = makeManager()
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")

        XCTAssertThrowsError(try manager.writeRepoOverride(repoPath: notARepo.path, profile: profile))
    }
}
```

**Step 2: Run to confirm failure**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED" | head -5
```

Expected: `error: cannot find type 'GitConfigRulesManager'`

**Step 3: Implement `GitSwitcher/Services/GitConfigRulesManager.swift`**

```swift
import Foundation
import os

enum GitConfigRulesError: LocalizedError {
    case notAGitRepo(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let path):
            return "Not a git repository: \(path)"
        case .writeFailed(let msg):
            return "Failed to write git config: \(msg)"
        }
    }
}

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
        let url = companionURL(for: profile)
        var content = "[user]\n"
        content += "\tname = \(profile.gitName)\n"
        content += "\temail = \(profile.gitEmail)\n"
        if let sshKey = profile.sshKeyPath, !sshKey.isEmpty {
            let sshCommand = "ssh -i '\(sshKey.replacingOccurrences(of: "'", with: "'\\''"))' -o IdentitiesOnly=yes"
            content += "[core]\n\tsshCommand = \(sshCommand)\n"
        }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
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
        // Build managed section
        var managedLines: [String] = []
        for profile in profiles {
            for rule in profile.directoryRules {
                // Ensure trailing slash (git requires it for gitdir matching)
                let path = rule.hasSuffix("/") ? rule : rule + "/"
                let companionPath = companionURL(for: profile).path
                managedLines.append("[includeIf \"gitdir/i:\(path)\"]")
                managedLines.append("\tpath = \(companionPath)")
            }
        }

        // Write companion configs for profiles that have rules
        for profile in profiles where !profile.directoryRules.isEmpty {
            try writeCompanionConfig(for: profile)
        }
        // Remove companion configs for profiles with no rules
        for profile in profiles where profile.directoryRules.isEmpty {
            try? removeCompanionConfig(for: profile)
        }

        // Read existing global config
        let configURL = URL(fileURLWithPath: globalConfigPath)
        let existing = (try? String(contentsOf: configURL)) ?? ""

        // Replace managed section or append it
        let newContent: String
        if existing.contains(markerBegin) {
            // Replace between markers
            let pattern = "\(markerBegin)[\\s\\S]*?\(markerEnd)\n?"
            if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(markerBegin) + "[\\s\\S]*?" + NSRegularExpression.escapedPattern(markerEnd) + "\n?") {
                let range = NSRange(existing.startIndex..., in: existing)
                if managedLines.isEmpty {
                    newContent = regex.stringByReplacingMatches(in: existing, range: range, withTemplate: "")
                } else {
                    let replacement = buildManagedSection(lines: managedLines)
                    newContent = regex.stringByReplacingMatches(in: existing, range: range, withTemplate: NSRegularExpression.escapedTemplate(replacement))
                }
            } else {
                newContent = existing
            }
        } else if managedLines.isEmpty {
            newContent = existing
        } else {
            let managed = buildManagedSection(lines: managedLines)
            newContent = existing.hasSuffix("\n") ? existing + managed : existing + "\n" + managed
        }

        do {
            try newContent.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            throw GitConfigRulesError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Repo overrides

    func writeRepoOverride(repoPath: String, profile: GitProfile) throws {
        let gitConfigPath = "\(repoPath)/.git/config"
        guard FileManager.default.fileExists(atPath: "\(repoPath)/.git") else {
            throw GitConfigRulesError.notAGitRepo(repoPath)
        }

        // Use git config --file to write safely
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "config", "--file", gitConfigPath, "user.name", profile.gitName]
        try process.run(); process.waitUntilExit()

        let process2 = Process()
        process2.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process2.arguments = ["git", "config", "--file", gitConfigPath, "user.email", profile.gitEmail]
        try process2.run(); process2.waitUntilExit()
    }

    func removeRepoOverride(repoPath: String) throws {
        let gitConfigPath = "\(repoPath)/.git/config"
        guard FileManager.default.fileExists(atPath: "\(repoPath)/.git") else { return }
        // Remove user section from repo's .git/config
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "config", "--file", gitConfigPath, "--remove-section", "user"]
        try process.run(); process.waitUntilExit()
        // Ignore exit code — section may not exist
    }

    // MARK: - Private helpers

    private func companionURL(for profile: GitProfile) -> URL {
        URL(fileURLWithPath: storageDirectory)
            .appendingPathComponent("\(profile.id.uuidString).gitconfig")
    }

    private func buildManagedSection(lines: [String]) -> String {
        ([markerBegin] + lines + [markerEnd]).joined(separator: "\n") + "\n"
    }
}
```

**Step 4: Run all tests**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodegen generate && xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed" | tail -5
```

Expected: all tests pass (19 existing + 8 new = 27 total).

**Step 5: Commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add GitSwitcher/Services/GitConfigRulesManager.swift GitSwitcherTests/GitConfigRulesManagerTests.swift
git commit -m "feat: add GitConfigRulesManager for includeIf and repo override management"
```

---

### Task 4: Wire ProfileStore to GitConfigRulesManager

Every time profiles change, regenerate the `includeIf` rules.

**Files:**
- Modify: `GitSwitcher/Services/ProfileStore.swift`

---

**Step 1: Add a `rulesManager` property and call `apply` on mutations**

In `ProfileStore.swift`, add at the top of the class (after the `activeIdURL` declaration):

```swift
private let rulesManager = GitConfigRulesManager()
```

Then update `add`, `update`, and `delete` to call `applyRules()` after `save()`:

```swift
func add(_ profile: GitProfile) {
    profiles.append(profile)
    save()
    applyRules()
}

func update(_ profile: GitProfile) {
    guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    profiles[idx] = profile
    save()
    applyRules()
}

func delete(_ profile: GitProfile) {
    // Remove companion config before deleting
    try? rulesManager.removeCompanionConfig(for: profile)
    profiles.removeAll { $0.id == profile.id }
    if _activeProfileId == profile.id {
        _activeProfileId = nil
        saveActiveId()
    }
    save()
    applyRules()
}

private func applyRules() {
    do {
        try rulesManager.apply(profiles: profiles)
    } catch {
        os_log(.error, "ProfileStore: failed to apply rules: %{public}@", error.localizedDescription)
    }
}
```

**Step 2: Build and run all tests**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed" | tail -5
```

Expected: all 27 tests still pass.

**Step 3: Commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add GitSwitcher/Services/ProfileStore.swift
git commit -m "feat: wire ProfileStore to apply GitConfigRulesManager on every mutation"
```

---

### Task 5: Profile Form UI — GitHub Import + Folder/Repo Pickers

**Files:**
- Modify: `GitSwitcher/Views/ProfileSettingsView.swift`

---

**Step 1: Replace `ProfileFormView` in `ProfileSettingsView.swift`**

Replace the entire `ProfileFormView` struct with this expanded version:

```swift
struct ProfileFormView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss

    let existingProfile: GitProfile?

    @State private var name: String
    @State private var gitName: String
    @State private var gitEmail: String
    @State private var sshKeyPath: String
    @State private var directoryRules: [String]
    @State private var repoOverrides: [String]
    @State private var githubLogin: String

    // GitHub import state
    @State private var isImporting = false
    @State private var importStatus: ImportStatus = .idle
    @State private var usernameInput = ""
    @State private var showUsernameField = false

    enum ImportStatus: Equatable {
        case idle
        case success(String)  // login
        case error(String)
    }

    init(profile: GitProfile?) {
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _gitName = State(initialValue: profile?.gitName ?? "")
        _gitEmail = State(initialValue: profile?.gitEmail ?? "")
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
        _directoryRules = State(initialValue: profile?.directoryRules ?? [])
        _repoOverrides = State(initialValue: profile?.repoOverrides ?? [])
        _githubLogin = State(initialValue: profile?.githubLogin ?? "")
    }

    private var isValid: Bool {
        !name.isEmpty && !gitName.isEmpty && !gitEmail.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingProfile == nil ? "Add Profile" : "Edit Profile")
                .font(.title2.bold())

            // GitHub import
            githubImportSection

            Divider()

            // Core fields
            Form {
                TextField("Profile label (e.g. Work)", text: $name)
                TextField("Full name", text: $gitName)
                TextField("Email", text: $gitEmail)
                TextField("SSH key path (optional)", text: $sshKeyPath)
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            // Directory rules
            folderRulesSection

            Divider()

            // Repo overrides
            repoOverridesSection

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button(existingProfile == nil ? "Add" : "Save") {
                    save()
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 480)
    }

    // MARK: - GitHub import section

    private var githubImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: startGitHubImport) {
                    HStack(spacing: 6) {
                        if isImporting {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "person.badge.plus")
                        }
                        Text("Connect via GitHub")
                    }
                }
                .disabled(isImporting)

                if case .success(let login) = importStatus {
                    Label("Connected as @\(login)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if showUsernameField {
                HStack {
                    TextField("GitHub username", text: $usernameInput)
                        .frame(width: 200)
                    Button("Fetch") {
                        Task { await fetchByUsername() }
                    }
                    .disabled(usernameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if case .error(let msg) = importStatus {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Folder rules section

    private var folderRulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Folders (applies to all repos inside)")
                .font(.headline)

            ForEach(directoryRules, id: \.self) { path in
                HStack {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        directoryRules.removeAll { $0 == path }
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }
            }

            Button("+ Add Folder") {
                pickFolder { url in
                    let path = url.path
                    if !directoryRules.contains(path) {
                        directoryRules.append(path)
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Repo overrides section

    private var repoOverridesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Specific Repos (override for one repo)")
                .font(.headline)

            ForEach(repoOverrides, id: \.self) { path in
                HStack {
                    Text(path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        repoOverrides.removeAll { $0 == path }
                        // Remove the override from the repo's .git/config
                        try? GitConfigRulesManager().removeRepoOverride(repoPath: path)
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }
            }

            Button("+ Add Repo") {
                pickFolder { url in
                    let path = url.path
                    guard !repoOverrides.contains(path) else { return }
                    guard FileManager.default.fileExists(atPath: "\(path)/.git") else {
                        // Not a git repo — show nothing (NSOpenPanel already filtered)
                        return
                    }
                    repoOverrides.append(path)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Actions

    private func startGitHubImport() {
        isImporting = true
        importStatus = .idle
        let importer = GitHubImporter()

        if importer.isGHAvailable() {
            do {
                let info = try importer.importViaGHCLI()
                applyImport(info)
            } catch {
                // gh failed or not authenticated — fall back to username input
                showUsernameField = true
                importStatus = .error("gh CLI failed. Enter your GitHub username below.")
            }
        } else {
            showUsernameField = true
            importStatus = .error("GitHub CLI not found. Enter your GitHub username below.")
        }
        isImporting = false
    }

    private func fetchByUsername() async {
        isImporting = true
        importStatus = .idle
        let importer = GitHubImporter()
        do {
            let info = try await importer.importViaUsername(usernameInput)
            await MainActor.run {
                applyImport(info)
                showUsernameField = false
            }
        } catch {
            await MainActor.run {
                importStatus = .error(error.localizedDescription)
            }
        }
        isImporting = false
    }

    private func applyImport(_ info: GitHubUserInfo) {
        if gitName.isEmpty { gitName = info.name }
        if gitEmail.isEmpty { gitEmail = info.email ?? "" }
        if name.isEmpty { name = info.login }
        githubLogin = info.login
        importStatus = .success(info.login)
    }

    private func pickFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func save() {
        let rulesManager = GitConfigRulesManager()
        if var existing = existingProfile {
            existing.name = name
            existing.gitName = gitName
            existing.gitEmail = gitEmail
            existing.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
            existing.githubLogin = githubLogin.isEmpty ? nil : githubLogin
            existing.directoryRules = directoryRules
            existing.repoOverrides = repoOverrides
            // Write repo overrides to their .git/config files
            for path in repoOverrides {
                try? rulesManager.writeRepoOverride(repoPath: path, profile: existing)
            }
            store.update(existing)
        } else {
            var profile = GitProfile(
                name: name,
                gitName: gitName,
                gitEmail: gitEmail,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
                githubLogin: githubLogin.isEmpty ? nil : githubLogin,
                directoryRules: directoryRules,
                repoOverrides: repoOverrides
            )
            for path in repoOverrides {
                try? rulesManager.writeRepoOverride(repoPath: path, profile: profile)
            }
            store.add(profile)
        }
    }
}
```

**Step 2: Build to verify**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild build -project GitSwitcher.xcodeproj -scheme GitSwitcher -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Run all tests to confirm nothing broken**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "passed|failed" | tail -5
```

Expected: all 27 tests pass.

**Step 4: Commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add GitSwitcher/Views/ProfileSettingsView.swift
git commit -m "feat: add GitHub import button and folder/repo pickers to ProfileFormView"
```

---

### Task 6: Final verification

**Step 1: Run full test suite**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild test -project GitSwitcher.xcodeproj -scheme GitSwitcherTests -destination 'platform=macOS' 2>&1 | grep -E "Test Suite|passed|failed"
```

Expected: all 27 tests pass, 0 failures.

**Step 2: Build release**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
xcodebuild build -project GitSwitcher.xcodeproj -scheme GitSwitcher -configuration Release -destination 'platform=macOS' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Smoke test**

```bash
pkill -x GitSwitcher 2>/dev/null; sleep 1
open /Users/shanew/Library/Developer/Xcode/DerivedData/GitSwitcher-*/Build/Products/Release/GitSwitcher.app
```

Verify manually:
- Open Manage Profiles → Edit a profile
- "Connect via GitHub" button is visible
- "+ Add Folder" opens a folder picker
- "+ Add Repo" opens a folder picker
- After saving a profile with a folder rule, check `~/.gitconfig` contains an `includeIf` block:
  ```bash
  cat ~/.gitconfig | grep -A2 includeIf
  ```

**Step 4: Final commit**

```bash
cd /Users/shanew/Documents/stuff/git_switcher/.worktrees/mvp
git add -A
git commit -m "chore: v2 complete — GitHub import, directory rules, repo overrides"
```

---

## Summary

| Task | What it builds | New tests |
|---|---|---|
| 1 | GitProfile + 3 new fields | 3 |
| 2 | GitHubImporter (gh CLI + public API) | 5 |
| 3 | GitConfigRulesManager (includeIf + repo overrides) | 8 |
| 4 | ProfileStore wired to rules manager | 0 (existing tests cover) |
| 5 | ProfileFormView with GitHub import + pickers | Build check |
| 6 | Full test run + smoke test | All 27 |
