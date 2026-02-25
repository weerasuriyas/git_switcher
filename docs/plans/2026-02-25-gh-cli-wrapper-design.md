# GitSwitcher v3 — gh CLI Wrapper Design

**Date:** 2026-02-25

## Summary

Full rewrite of GitSwitcher as a thin macOS menu bar UI wrapper around the `gh` CLI's multi-account auth system. No custom profile storage. `gh` is the single source of truth.

## Problem

The v2 app maintained its own JSON profile store and wrote directly to `~/.gitconfig`. This duplicated state that `gh` already manages. The simpler approach: use `gh auth status` to list accounts and `gh auth switch` to switch between them.

## Architecture

**Platform:** macOS 13+, SwiftUI `MenuBarExtra`, no Dock icon.

**Single source of truth:** `gh auth status --json hosts` — the CLI's own account registry.

**No persistence layer.** All state is read from `gh` on launch and after any mutating action.

## Data Model

```swift
struct GHAccount {
    let login: String    // GitHub username, e.g. "weerasuriyas"
    let host: String     // e.g. "github.com" or enterprise hostname
    let active: Bool     // whether this is the currently active account
}
```

Parsed from:
```json
{"hosts":{"github.com":[{"login":"weerasuriyas","active":true,"host":"github.com",...}]}}
```

## Components

### GHCLIService
`ObservableObject` that owns all `gh` interactions.

- `refresh()` — runs `gh auth status --json hosts`, parses JSON into `[GHAccount]`
- `switchTo(login:host:)` — runs `gh auth switch --user <login> --hostname <host>`, then `refresh()`
- `addAccount()` — opens Terminal with `gh auth login` via `open -a Terminal`; app must re-refresh after user completes login
- `remove(login:host:)` — runs `gh auth logout --user <login> --hostname <host>`, then `refresh()`

### ContentView (MenuBarExtra content)
Menu structure:
```
✓ weerasuriyas          ← active account (checkmark)
  other-account         ← tap to switch
──────────────
  Add Account…          ← triggers addAccount()
  Remove Account ▶      ← submenu listing non-active accounts
──────────────
  Quit
```

Menu bar label shows the active account login, or "No Account" if none.

### GitSwitcherApp
`MenuBarExtra` scene. Owns `@StateObject var service = GHCLIService()`. Calls `service.refresh()` on appear.

## Files

### Delete (entire v2 surface)
- `GitSwitcher/Models/GitProfile.swift`
- `GitSwitcher/Services/GitConfigManager.swift`
- `GitSwitcher/Services/GitConfigRulesManager.swift`
- `GitSwitcher/Services/GitHubImporter.swift`
- `GitSwitcher/Services/ProfileStore.swift`
- `GitSwitcher/Services/LaunchAtLoginManager.swift`

### Create / Replace
- `GitSwitcher/Services/GHCLIService.swift` — new
- `GitSwitcher/Views/ContentView.swift` — replace
- `GitSwitcher/App/GitSwitcherApp.swift` — update

## Error Handling

- If `gh` is not installed: show "gh not found — install GitHub CLI" in the menu
- If `gh auth status` returns no accounts: show "No accounts — Add Account…"
- If switch/remove fails: show error message inline in the menu

## Out of Scope

- Modifying `~/.gitconfig` user.name/email
- Per-directory git config rules
- GitHub import wizard
- Launch at login
