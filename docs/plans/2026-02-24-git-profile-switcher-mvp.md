# Git Profile Switcher MVP — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS 13+ menu bar app that switches your global Git identity (name, email, optional SSH key) with a single click.

**Architecture:** SwiftUI `MenuBarExtra` app (no Dock icon). Profiles stored as JSON at `~/.config/git-profile-switcher/profiles.json`. Git config applied by shelling out to `git config --global`. Project scaffolded via `xcodegen` so it can be generated without opening Xcode GUI.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, xcodegen (via Homebrew), XCTest

---

## Pre-flight checks (run once before starting)

```bash
# Verify macOS version
sw_vers -productVersion   # must be 13.0+

# Install xcodegen if missing
brew install xcodegen

# Confirm git exists
git --version
```

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `GitSwitcher/App/GitSwitcherApp.swift`
- Create: `GitSwitcher/App/Info.plist`
- Create: `GitSwitcherTests/Placeholder.swift`

---

**Step 1: Write `project.yml`**

```yaml
# project.yml
name: GitSwitcher
options:
  bundleIdPrefix: com.gitswitch
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15"
settings:
  SWIFT_VERSION: "5.9"

targets:
  GitSwitcher:
    type: application
    platform: macOS
    sources:
      - GitSwitcher
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.gitswitch.GitSwitcher
      INFOPLIST_FILE: GitSwitcher/App/Info.plist
      CODE_SIGN_IDENTITY: ""
      CODE_SIGNING_REQUIRED: "NO"
    entitlements:
      path: GitSwitcher/App/GitSwitcher.entitlements
      properties:
        com.apple.security.app-sandbox: false

  GitSwitcherTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - GitSwitcherTests
    dependencies:
      - target: GitSwitcher
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.gitswitch.GitSwitcherTests
```

**Step 2: Write `GitSwitcher/App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
```

> `LSUIElement = true` hides the Dock icon — this is the key for a menu bar app.

**Step 3: Write `GitSwitcher/App/GitSwitcherApp.swift`**

```swift
import SwiftUI

@main
struct GitSwitcherApp: App {
    @StateObject private var store = ProfileStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            Label(store.activeProfile?.name ?? "No Profile", systemImage: "person.crop.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 4: Write `GitSwitcher/App/GitSwitcher.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

**Step 5: Write `GitSwitcherTests/Placeholder.swift`**

```swift
// Placeholder to satisfy xcodegen target requirement
import XCTest
```

**Step 6: Create source directory structure**

```bash
mkdir -p GitSwitcher/App
mkdir -p GitSwitcher/Models
mkdir -p GitSwitcher/Services
mkdir -p GitSwitcher/Views
mkdir -p GitSwitcherTests
```

**Step 7: Generate the Xcode project**

```bash
xcodegen generate
```

Expected output: `✅ Done` and a new `GitSwitcher.xcodeproj` directory.

**Step 8: Verify it builds (empty app)**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 9: Commit**

```bash
git add project.yml GitSwitcher/ GitSwitcherTests/ GitSwitcher.xcodeproj
git commit -m "feat: scaffold xcodegen project for macOS menu bar app"
```

---

### Task 2: GitProfile Model

**Files:**
- Create: `GitSwitcher/Models/GitProfile.swift`
- Create: `GitSwitcherTests/GitProfileTests.swift`

---

**Step 1: Write the failing test**

```swift
// GitSwitcherTests/GitProfileTests.swift
import XCTest
@testable import GitSwitcher

final class GitProfileTests: XCTestCase {
    func test_encode_decode_roundtrip() throws {
        let profile = GitProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Work",
            gitName: "Jane Doe",
            gitEmail: "jane@corp.com",
            sshKeyPath: "/Users/jane/.ssh/id_work",
            signingKey: nil,
            signingFormat: nil
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded.id, profile.id)
        XCTAssertEqual(decoded.name, profile.name)
        XCTAssertEqual(decoded.gitName, profile.gitName)
        XCTAssertEqual(decoded.gitEmail, profile.gitEmail)
        XCTAssertEqual(decoded.sshKeyPath, profile.sshKeyPath)
        XCTAssertNil(decoded.signingKey)
    }

    func test_default_values() {
        let profile = GitProfile(name: "Personal", gitName: "Jane", gitEmail: "jane@home.com")
        XCTAssertNotNil(profile.id)
        XCTAssertNil(profile.sshKeyPath)
        XCTAssertNil(profile.signingKey)
        XCTAssertNil(profile.signingFormat)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: error — `GitProfile` not defined.

**Step 3: Write `GitSwitcher/Models/GitProfile.swift`**

```swift
import Foundation

struct GitProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String        // Display label, e.g. "Work"
    var gitName: String     // git user.name
    var gitEmail: String    // git user.email
    var sshKeyPath: String? // path to SSH private key, e.g. ~/.ssh/id_work
    var signingKey: String? // GPG key ID or SSH public key path
    var signingFormat: String? // "gpg" or "ssh"

    init(
        id: UUID = UUID(),
        name: String,
        gitName: String,
        gitEmail: String,
        sshKeyPath: String? = nil,
        signingKey: String? = nil,
        signingFormat: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gitName = gitName
        self.gitEmail = gitEmail
        self.sshKeyPath = sshKeyPath
        self.signingKey = signingKey
        self.signingFormat = signingFormat
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test.*passed|FAILED|error:"
```

Expected: `Test Case '-[GitSwitcherTests.GitProfileTests test_encode_decode_roundtrip]' passed`

**Step 5: Commit**

```bash
git add GitSwitcher/Models/GitProfile.swift GitSwitcherTests/GitProfileTests.swift
git commit -m "feat: add GitProfile model with Codable support"
```

---

### Task 3: GitConfigManager

Handles all shell interaction with `git config` and `~/.gitconfig`.

**Files:**
- Create: `GitSwitcher/Services/GitConfigManager.swift`
- Create: `GitSwitcherTests/GitConfigManagerTests.swift`

---

**Step 1: Write the failing tests**

```swift
// GitSwitcherTests/GitConfigManagerTests.swift
import XCTest
@testable import GitSwitcher

final class GitConfigManagerTests: XCTestCase {

    // We write to a temp gitconfig so we don't pollute the real one
    var tempConfigURL: URL!

    override func setUp() {
        super.setUp()
        tempConfigURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("test_gitconfig_\(UUID().uuidString)")
        // Create empty file
        FileManager.default.createFile(atPath: tempConfigURL.path, contents: nil)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempConfigURL)
        super.tearDown()
    }

    func test_apply_profile_writes_name_and_email() throws {
        let manager = GitConfigManager(configPath: tempConfigURL.path)
        let profile = GitProfile(name: "Work", gitName: "Test User", gitEmail: "test@example.com")

        try manager.apply(profile)

        let name = try manager.read(key: "user.name")
        let email = try manager.read(key: "user.email")
        XCTAssertEqual(name, "Test User")
        XCTAssertEqual(email, "test@example.com")
    }

    func test_read_current_profile_returns_name_email() throws {
        let manager = GitConfigManager(configPath: tempConfigURL.path)
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")
        try manager.apply(profile)

        let (name, email) = try manager.readCurrentNameEmail()
        XCTAssertEqual(name, "Alice")
        XCTAssertEqual(email, "alice@home.io")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|FAILED"
```

Expected: `error: cannot find type 'GitConfigManager'`

**Step 3: Write `GitSwitcher/Services/GitConfigManager.swift`**

```swift
import Foundation

struct GitConfigManager {
    /// Path to the git config file. Defaults to ~/.gitconfig.
    let configPath: String

    init(configPath: String = "\(NSHomeDirectory())/.gitconfig") {
        self.configPath = configPath
    }

    /// Write all fields from profile into the config file.
    func apply(_ profile: GitProfile) throws {
        try run("git", "config", "--file", configPath, "user.name", profile.gitName)
        try run("git", "config", "--file", configPath, "user.email", profile.gitEmail)

        if let sshKey = profile.sshKeyPath, !sshKey.isEmpty {
            let sshCommand = "ssh -i \(sshKey) -o IdentitiesOnly=yes"
            try run("git", "config", "--file", configPath, "core.sshCommand", sshCommand)
        }

        if let signingKey = profile.signingKey, !signingKey.isEmpty {
            try run("git", "config", "--file", configPath, "user.signingkey", signingKey)
            if let format = profile.signingFormat {
                try run("git", "config", "--file", configPath, "gpg.format", format)
            }
        }
    }

    /// Read a single key from the config file.
    func read(key: String) throws -> String {
        let output = try runOutput("git", "config", "--file", configPath, key)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convenience: return (user.name, user.email) from config.
    func readCurrentNameEmail() throws -> (String, String) {
        let name = try read(key: "user.name")
        let email = try read(key: "user.email")
        return (name, email)
    }

    // MARK: - Private helpers

    @discardableResult
    private func run(_ args: String...) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitConfigError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        return process.terminationStatus
    }

    private func runOutput(_ args: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitConfigError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum GitConfigError: LocalizedError {
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code):
            return "Command `\(cmd)` failed with exit code \(code)"
        }
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "passed|FAILED|error:"
```

Expected: both `GitConfigManagerTests` tests pass.

**Step 5: Commit**

```bash
git add GitSwitcher/Services/GitConfigManager.swift GitSwitcherTests/GitConfigManagerTests.swift
git commit -m "feat: add GitConfigManager for reading/writing git config"
```

---

### Task 4: ProfileStore

Handles loading/saving profiles from disk and tracking the active profile.

**Files:**
- Create: `GitSwitcher/Services/ProfileStore.swift`
- Create: `GitSwitcherTests/ProfileStoreTests.swift`

---

**Step 1: Write the failing tests**

```swift
// GitSwitcherTests/ProfileStoreTests.swift
import XCTest
@testable import GitSwitcher

final class ProfileStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_add_profile_persists_to_disk() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")

        store.add(profile)

        // Read it back from a fresh store (simulates app relaunch)
        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.profiles.count, 1)
        XCTAssertEqual(store2.profiles[0].gitEmail, "bob@work.com")
    }

    func test_delete_profile_removes_from_disk() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        store.add(profile)

        store.delete(profile)

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertTrue(store2.profiles.isEmpty)
    }

    func test_active_profile_id_persists() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        let profile = GitProfile(name: "Personal", gitName: "Alice", gitEmail: "alice@home.io")
        store.add(profile)
        store.activeProfileId = profile.id

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.activeProfileId, profile.id)
    }

    func test_update_profile_replaces_in_place() throws {
        let store = ProfileStore(storageDirectory: tempDir.path)
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        store.add(profile)

        profile.gitEmail = "bob@newwork.com"
        store.update(profile)

        let store2 = ProfileStore(storageDirectory: tempDir.path)
        XCTAssertEqual(store2.profiles[0].gitEmail, "bob@newwork.com")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|FAILED"
```

Expected: `error: cannot find type 'ProfileStore'`

**Step 3: Write `GitSwitcher/Services/ProfileStore.swift`**

```swift
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

        // Ensure directory exists
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

    // MARK: - Private

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
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "passed|FAILED|error:"
```

Expected: all 4 `ProfileStoreTests` pass.

**Step 5: Commit**

```bash
git add GitSwitcher/Services/ProfileStore.swift GitSwitcherTests/ProfileStoreTests.swift
git commit -m "feat: add ProfileStore with JSON persistence"
```

---

### Task 5: Menu Bar Content View (Profile List + Switch)

**Files:**
- Create: `GitSwitcher/Views/ContentView.swift`

No unit test here — this is pure SwiftUI view code. Build verification is the test.

---

**Step 1: Write `GitSwitcher/Views/ContentView.swift`**

```swift
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

        // Error display
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
```

**Step 2: Build to verify it compiles**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add GitSwitcher/Views/ContentView.swift
git commit -m "feat: add menu bar content view with profile switching"
```

---

### Task 6: Profile Settings View (CRUD)

Add/edit/delete profiles in a sheet.

**Files:**
- Create: `GitSwitcher/Views/ProfileSettingsView.swift`

---

**Step 1: Write `GitSwitcher/Views/ProfileSettingsView.swift`**

```swift
import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss
    @State private var editingProfile: GitProfile?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Git Profiles")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            List {
                ForEach(store.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.name).bold()
                            Text("\(profile.gitName) <\(profile.gitEmail)>")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingProfile = profile }
                            .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    indexSet.forEach { store.delete(store.profiles[$0]) }
                }
            }

            Divider()

            HStack {
                Button("+ Add Profile") { showingAddSheet = true }
                    .padding()
                Spacer()
            }
        }
        .frame(width: 480, height: 360)
        .sheet(isPresented: $showingAddSheet) {
            ProfileFormView(profile: nil)
                .environmentObject(store)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileFormView(profile: profile)
                .environmentObject(store)
        }
    }
}

struct ProfileFormView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) var dismiss

    let existingProfile: GitProfile?

    @State private var name: String
    @State private var gitName: String
    @State private var gitEmail: String
    @State private var sshKeyPath: String

    init(profile: GitProfile?) {
        self.existingProfile = profile
        _name = State(initialValue: profile?.name ?? "")
        _gitName = State(initialValue: profile?.gitName ?? "")
        _gitEmail = State(initialValue: profile?.gitEmail ?? "")
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
    }

    private var isValid: Bool {
        !name.isEmpty && !gitName.isEmpty && !gitEmail.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingProfile == nil ? "Add Profile" : "Edit Profile")
                .font(.title2.bold())

            Form {
                TextField("Profile label (e.g. Work)", text: $name)
                TextField("Full name", text: $gitName)
                TextField("Email", text: $gitEmail)
                TextField("SSH key path (optional)", text: $sshKeyPath)
                    .font(.system(.body, design: .monospaced))
            }

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
        .frame(width: 400)
    }

    private func save() {
        if var existing = existingProfile {
            existing.name = name
            existing.gitName = gitName
            existing.gitEmail = gitEmail
            existing.sshKeyPath = sshKeyPath.isEmpty ? nil : sshKeyPath
            store.update(existing)
        } else {
            let profile = GitProfile(
                name: name,
                gitName: gitName,
                gitEmail: gitEmail,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath
            )
            store.add(profile)
        }
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add GitSwitcher/Views/ProfileSettingsView.swift
git commit -m "feat: add profile settings view with add/edit/delete"
```

---

### Task 7: Launch at Login

Register the app to launch automatically at login using `SMAppService`.

**Files:**
- Modify: `GitSwitcher/Views/ProfileSettingsView.swift` (add toggle)
- Modify: `GitSwitcher/Services/LaunchAtLoginManager.swift` (new file)

---

**Step 1: Write `GitSwitcher/Services/LaunchAtLoginManager.swift`**

```swift
import Foundation
import ServiceManagement

final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = false

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
                isEnabled = false
            } else {
                try SMAppService.mainApp.register()
                isEnabled = true
            }
        } catch {
            // Log silently — launch at login is non-critical
            print("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
```

**Step 2: Wire it into `ProfileSettingsView.swift`**

Add `@StateObject private var launchManager = LaunchAtLoginManager()` to `ProfileSettingsView` and append this to the bottom of the `VStack`, above `Divider()` before the Done button:

```swift
Divider()
Toggle("Launch at login", isOn: Binding(
    get: { launchManager.isEnabled },
    set: { _ in launchManager.toggle() }
))
.padding([.horizontal, .bottom])
```

**Step 3: Build to verify**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add GitSwitcher/Services/LaunchAtLoginManager.swift GitSwitcher/Views/ProfileSettingsView.swift
git commit -m "feat: add launch at login toggle via SMAppService"
```

---

### Task 8: Run All Tests + Smoke Test

**Step 1: Run full test suite**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: all tests pass, 0 failures.

**Step 2: Build release archive**

```bash
xcodebuild archive \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -archivePath build/GitSwitcher.xcarchive \
  2>&1 | tail -5
```

Expected: `** ARCHIVE SUCCEEDED **`

**Step 3: Smoke test by running the app**

```bash
open build/GitSwitcher.xcarchive/Products/Applications/GitSwitcher.app
```

Verify:
- Menu bar icon appears with person icon
- Clicking shows "No profiles yet" if empty
- Can add a profile via "Manage Profiles…"
- Switching a profile writes to `~/.gitconfig` — verify with `git config --global user.email`

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: verify all tests pass and app builds cleanly"
```

---

## Summary

| Task | What it builds | Tests |
|------|---------------|-------|
| 1 | Xcode project scaffold | Build check |
| 2 | `GitProfile` model | 2 unit tests |
| 3 | `GitConfigManager` (shell integration) | 2 unit tests |
| 4 | `ProfileStore` (JSON persistence) | 4 unit tests |
| 5 | Menu bar UI + profile switching | Build check |
| 6 | Profile CRUD settings sheet | Build check |
| 7 | Launch at login | Build check |
| 8 | Full test run + smoke test | All tests |

**Total unit tests: 8**
**Estimated implement time: 10–15 hours (for a human); much less for subagents.**
