# GitSwitcher v3 — gh CLI Wrapper Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite GitSwitcher as a thin macOS menu bar UI wrapper around `gh auth` — listing, switching, adding, and removing GitHub accounts entirely via the `gh` CLI.

**Architecture:** Delete all v2 profile/config/import code. One new service (`GHCLIService`) shells out to `gh`. One rewritten `ContentView`. Menu auto-refreshes via `NSMenu.didBeginTrackingNotification`. No local storage.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, `gh` CLI (Homebrew), XCTest

---

## Pre-flight checks

```bash
# Confirm gh is installed
gh --version           # must succeed

# Confirm xcodegen is installed
xcodegen --version

# Confirm project builds before touching anything
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

---

### Task 1: Delete v2 files and clean up

**Files to delete:**
- `GitSwitcher/Models/GitProfile.swift`
- `GitSwitcher/Services/GitConfigManager.swift`
- `GitSwitcher/Services/GitConfigRulesManager.swift`
- `GitSwitcher/Services/GitHubImporter.swift`
- `GitSwitcher/Services/ProfileStore.swift`
- `GitSwitcher/Services/LaunchAtLoginManager.swift`
- `GitSwitcher/Views/ProfileSettingsView.swift`
- `GitSwitcherTests/GitProfileTests.swift`
- `GitSwitcherTests/GitConfigManagerTests.swift`
- `GitSwitcherTests/GitConfigRulesManagerTests.swift`
- `GitSwitcherTests/GitHubImporterTests.swift`
- `GitSwitcherTests/ProfileStoreTests.swift`

---

**Step 1: Delete all v2 source files**

```bash
rm GitSwitcher/Models/GitProfile.swift
rm GitSwitcher/Services/GitConfigManager.swift
rm GitSwitcher/Services/GitConfigRulesManager.swift
rm GitSwitcher/Services/GitHubImporter.swift
rm GitSwitcher/Services/ProfileStore.swift
rm GitSwitcher/Services/LaunchAtLoginManager.swift
rm GitSwitcher/Views/ProfileSettingsView.swift
```

**Step 2: Delete v2 test files**

```bash
rm GitSwitcherTests/GitProfileTests.swift
rm GitSwitcherTests/GitConfigManagerTests.swift
rm GitSwitcherTests/GitConfigRulesManagerTests.swift
rm GitSwitcherTests/GitHubImporterTests.swift
rm GitSwitcherTests/ProfileStoreTests.swift
```

**Step 3: Stub out ContentView so the project compiles**

Replace the entire contents of `GitSwitcher/Views/ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Loading…")
    }
}
```

**Step 4: Stub out GitSwitcherApp.swift**

Replace the entire contents of `GitSwitcher/App/GitSwitcherApp.swift` with:

```swift
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
```

**Step 5: Regenerate Xcode project and verify build**

```bash
xcodegen generate

xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: delete v2 — clear the slate for gh CLI wrapper rewrite"
```

---

### Task 2: GHAccount model + GHAccountParser (TDD)

**Files:**
- Create: `GitSwitcher/Models/GHAccount.swift`
- Create: `GitSwitcherTests/GHAccountParserTests.swift`

---

**Step 1: Write the failing tests**

Create `GitSwitcherTests/GHAccountParserTests.swift`:

```swift
import XCTest
@testable import GitSwitcher

final class GHAccountParserTests: XCTestCase {

    func test_parse_single_active_account() throws {
        let json = """
        {"hosts":{"github.com":[{
            "login":"alice","active":true,"host":"github.com",
            "state":"success","tokenSource":"keyring",
            "scopes":"repo","gitProtocol":"https"
        }]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].login, "alice")
        XCTAssertEqual(accounts[0].host, "github.com")
        XCTAssertTrue(accounts[0].active)
    }

    func test_parse_two_accounts_same_host_one_active() throws {
        let json = """
        {"hosts":{"github.com":[
            {"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"},
            {"login":"bob","active":false,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}
        ]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.filter { $0.active }.count, 1)
        let bob = accounts.first { $0.login == "bob" }
        XCTAssertNotNil(bob)
        XCTAssertFalse(bob!.active)
    }

    func test_parse_accounts_across_multiple_hosts() throws {
        let json = """
        {"hosts":{
            "github.com":[{"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}],
            "enterprise.internal":[{"login":"corp-alice","active":false,"host":"enterprise.internal","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]
        }}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 2)
        let hosts = Set(accounts.map { $0.host })
        XCTAssertTrue(hosts.contains("github.com"))
        XCTAssertTrue(hosts.contains("enterprise.internal"))
    }

    func test_parse_empty_hosts_returns_empty_array() throws {
        let accounts = try GHAccountParser.parse(#"{"hosts":{}}"#)
        XCTAssertTrue(accounts.isEmpty)
    }

    func test_parse_invalid_json_throws() {
        XCTAssertThrowsError(try GHAccountParser.parse("not json"))
    }

    func test_display_name_github_com_is_just_login() throws {
        let json = """
        {"hosts":{"github.com":[{"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts[0].displayName, "alice")
    }

    func test_display_name_enterprise_host_includes_hostname() throws {
        let json = """
        {"hosts":{"enterprise.internal":[{"login":"alice","active":false,"host":"enterprise.internal","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts[0].displayName, "alice (enterprise.internal)")
    }
}
```

**Step 2: Run tests to verify they fail**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "error:|FAILED"
```

Expected: errors — `GHAccountParser` and `GHAccount` not defined.

**Step 3: Write `GitSwitcher/Models/GHAccount.swift`**

```swift
import Foundation

struct GHAccount: Identifiable, Equatable {
    let login: String
    let host: String
    let active: Bool

    var id: String { "\(host)/\(login)" }

    var displayName: String {
        host == "github.com" ? login : "\(login) (\(host))"
    }
}

enum GHAccountParser {
    private struct RawAccount: Decodable {
        let login: String
        let host: String
        let active: Bool
    }

    private struct RawStatus: Decodable {
        let hosts: [String: [RawAccount]]
    }

    static func parse(_ json: String) throws -> [GHAccount] {
        let data = Data(json.utf8)
        let status = try JSONDecoder().decode(RawStatus.self, from: data)
        return status.hosts.values.flatMap { accounts in
            accounts.map { GHAccount(login: $0.login, host: $0.host, active: $0.active) }
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

Expected: all 7 `GHAccountParserTests` pass, 0 failures.

**Step 5: Commit**

```bash
git add GitSwitcher/Models/GHAccount.swift GitSwitcherTests/GHAccountParserTests.swift
git commit -m "feat: add GHAccount model and GHAccountParser with tests"
```

---

### Task 3: GHCLIService

**Files:**
- Create: `GitSwitcher/Services/GHCLIService.swift`

No unit tests for shell calls — the parser (the only logic) is already tested. This task is build-verified.

---

**Step 1: Write `GitSwitcher/Services/GHCLIService.swift`**

```swift
import AppKit
import Combine

@MainActor
final class GHCLIService: ObservableObject {
    @Published var accounts: [GHAccount] = []
    @Published var ghError: GHError?

    var activeAccount: GHAccount? { accounts.first { $0.active } }

    // Locate gh at app launch once; nil means not installed.
    private static let ghPath: String? = {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }()

    init() {
        // Refresh every time any NSMenu opens (includes our menu bar extra).
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        Task {
            do {
                let json = try await runGH(["auth", "status", "--json", "hosts"])
                accounts = try GHAccountParser.parse(json)
                ghError = nil
            } catch let e as GHError {
                ghError = e
                accounts = []
            } catch {
                ghError = .commandFailed(error.localizedDescription)
                accounts = []
            }
        }
    }

    func switchTo(_ account: GHAccount) {
        Task {
            do {
                try await runGHVoid(["auth", "switch", "--user", account.login, "--hostname", account.host])
                refresh()
            } catch let e as GHError {
                ghError = e
            }
        }
    }

    /// Opens Terminal and runs `gh auth login` interactively.
    /// The user closes Terminal when done; next menu open auto-refreshes.
    func addAccount() {
        let src = "tell application \"Terminal\" to do script \"gh auth login\""
        let script = NSAppleScript(source: src)
        script?.executeAndReturnError(nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    func remove(_ account: GHAccount) {
        Task {
            do {
                try await runGHVoid(["auth", "logout", "--user", account.login, "--hostname", account.host])
                refresh()
            } catch let e as GHError {
                ghError = e
            }
        }
    }

    // MARK: - Private

    @discardableResult
    private func runGH(_ args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let ghPath = GHCLIService.ghPath else { throw GHError.notInstalled }
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = args
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            guard process.terminationStatus == 0 else {
                let errOutput = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw GHError.commandFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }

    private func runGHVoid(_ args: [String]) async throws {
        _ = try await runGH(args)
    }
}

enum GHError: LocalizedError, Equatable {
    case notInstalled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "GitHub CLI (gh) not found. Install with: brew install gh"
        case .commandFailed(let msg):
            return msg.isEmpty ? "gh command failed" : msg
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
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add GitSwitcher/Services/GHCLIService.swift
git commit -m "feat: add GHCLIService wrapping gh auth commands"
```

---

### Task 4: ContentView

**Files:**
- Modify: `GitSwitcher/Views/ContentView.swift`

---

**Step 1: Replace `GitSwitcher/Views/ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var service: GHCLIService

    var body: some View {
        if let error = service.ghError {
            Text(error.localizedDescription)
                .foregroundStyle(.red)
                .font(.caption)
            Divider()
        } else if service.accounts.isEmpty {
            Text("No accounts — add one below")
                .foregroundStyle(.secondary)
            Divider()
        } else {
            ForEach(service.accounts) { account in
                Button {
                    service.switchTo(account)
                } label: {
                    HStack {
                        Text(account.displayName)
                        Spacer()
                        if account.active {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            let removable = service.accounts.filter { !$0.active }
            if !removable.isEmpty {
                Menu("Remove Account") {
                    ForEach(removable) { account in
                        Button(account.displayName) {
                            service.remove(account)
                        }
                    }
                }
            }
        }

        Button("Add Account…") {
            service.addAccount()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add GitSwitcher/Views/ContentView.swift
git commit -m "feat: rewrite ContentView as gh auth account switcher"
```

---

### Task 5: GitSwitcherApp — wire GHCLIService

**Files:**
- Modify: `GitSwitcher/App/GitSwitcherApp.swift`

---

**Step 1: Replace `GitSwitcher/App/GitSwitcherApp.swift`**

```swift
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
```

**Step 2: Build to verify**

```bash
xcodebuild build \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -destination 'platform=macOS' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

**Step 3: Commit**

```bash
git add GitSwitcher/App/GitSwitcherApp.swift
git commit -m "feat: wire GHCLIService into MenuBarExtra app entry point"
```

---

### Task 6: Full test run + smoke test

---

**Step 1: Run full test suite**

```bash
xcodebuild test \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcherTests \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: all `GHAccountParserTests` pass, 0 failures.

**Step 2: Build release archive**

```bash
xcodebuild archive \
  -project GitSwitcher.xcodeproj \
  -scheme GitSwitcher \
  -archivePath build/GitSwitcher.xcarchive \
  2>&1 | tail -3
```

Expected: `** ARCHIVE SUCCEEDED **`

**Step 3: Smoke test**

```bash
open build/GitSwitcher.xcarchive/Products/Applications/GitSwitcher.app
```

Verify:
- Menu bar icon appears showing your active `gh` account login (e.g. "weerasuriyas")
- Clicking the icon lists all `gh`-authenticated accounts
- Active account has a checkmark
- "Add Account…" opens Terminal with `gh auth login`
- Re-opening the menu after Terminal login shows the new account
- "Remove Account" submenu only shows non-active accounts
- Switching accounts updates the checkmark and the menu bar label

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: v3 complete — gh CLI wrapper, all tests pass"
```

---

## Summary

| Task | What it builds | Verified by |
|------|---------------|-------------|
| 1 | Delete v2, stub views | Build check |
| 2 | `GHAccount` + `GHAccountParser` | 7 unit tests |
| 3 | `GHCLIService` (shell + refresh) | Build check |
| 4 | `ContentView` (menu UI) | Build check |
| 5 | `GitSwitcherApp` wiring | Build check |
| 6 | Full test + smoke test | All tests + manual |

**Total unit tests: 7**
**Files deleted: 12 (all v2)**
**Files created: 3 (`GHAccount.swift`, `GHCLIService.swift`, updated views)**
