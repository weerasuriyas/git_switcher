# GitHub Account Import + Directory Rules — Design

**Date:** 2026-02-24
**Status:** Approved

---

## Goal

Allow users to add Git profiles by importing from GitHub (no OAuth App required), then assign those profiles to folders or specific repos so git automatically uses the right identity — without the app needing to be running.

---

## Architecture

Three layers, all composable:

1. **GitHub import** — fetch name/email from GitHub to auto-populate a profile at creation time. No token stored.
2. **Directory rules** — assign a profile to a top-level folder. App writes `[includeIf]` blocks into `~/.gitconfig`. Git resolves automatically.
3. **Per-repo overrides** — assign a profile to a specific repo. App writes directly into `.git/config`. Takes priority over everything.

Manual global switching (existing behavior) remains unchanged.

---

## GitHub Import Flow

Two strategies, tried in order:

### Strategy A: `gh` CLI (preferred)
- Detect `gh` with `which gh`
- Run `gh api user` — returns JSON with `name`, `email`, `login`
- If exit code 0: fill profile fields, show "Connected as @{login} ✓"
- If exit code non-zero or `gh` not found: fall back to Strategy B

### Strategy B: Public GitHub API
- Show text field: "Enter GitHub username"
- Fetch `https://api.github.com/users/{username}` (unauthenticated, 60 req/hr limit)
- Fill `name` from response `name` field
- Fill `email` from response `email` field (may be null if user has private email — leave blank for manual entry)
- Show fetched name/email in form for user to confirm/edit before saving

No token is stored at any point. Import is one-time at profile creation.

---

## Directory Rules (`includeIf`)

### Storage
Each profile with directory rules gets a companion config file:
```
~/.config/git-profile-switcher/{profile-id}.gitconfig
```
Contents:
```ini
[user]
    name = Shane Weerasuriya
    email = shane@personal.com
```

### `~/.gitconfig` entries
For each directory rule, the app appends/manages:
```ini
[includeIf "gitdir/i:/Users/shane/work/"]
    path = /Users/shane/.config/git-profile-switcher/{profile-id}.gitconfig
```

`gitdir/i:` = case-insensitive match, recursive into all subdirectories.

### Adding a rule
- User taps `+ Add Folder` → `NSOpenPanel` (directories only, no files)
- Selected path is added to the profile's `directoryRules` array
- App regenerates the `includeIf` section of `~/.gitconfig`

### Removing a rule
- User taps `[−]` next to a folder
- App removes the corresponding `includeIf` block from `~/.gitconfig`
- If profile has no remaining rules, deletes the companion `.gitconfig` file

### Conflict resolution
Git's native precedence applies — no custom logic required:
1. `.git/config` (repo override — highest priority)
2. `includeIf` match (directory rule)
3. `~/.gitconfig` global (lowest priority)

---

## Per-Repo Overrides

- User taps `+ Add Repo` → `NSOpenPanel` (directories only, must contain `.git/`)
- App validates selected path is a git repo (`test -d {path}/.git`)
- Writes directly to `{path}/.git/config`:
  ```ini
  [user]
      name = Shane Weerasuriya
      email = shane@personal.com
  ```
- Stored in profile's `repoOverrides` array (paths only — for display and removal)

### Removing an override
- User taps `[−]`
- App removes the `[user]` section from that repo's `.git/config`
- Removes path from `repoOverrides`

---

## Data Model Changes

```swift
struct GitProfile: Codable, Identifiable, Equatable {
    // existing fields unchanged
    let id: UUID
    var name: String
    var gitName: String
    var gitEmail: String
    var sshKeyPath: String?
    var signingKey: String?
    var signingFormat: String?

    // new fields
    var githubLogin: String?        // e.g. "shanew" — display only
    var directoryRules: [String]    // absolute paths, e.g. ["/Users/shane/work"]
    var repoOverrides: [String]     // absolute paths to specific repos
}
```

---

## New Services

### `GitHubImporter`
```swift
struct GitHubImporter {
    // Strategy A
    func importViaGHCLI() throws -> (name: String, email: String, login: String)

    // Strategy B
    func importViaUsername(_ username: String) async throws -> (name: String, email: String?, login: String)
}
```

### `GitConfigRulesManager`
Manages the `includeIf` section of `~/.gitconfig` and companion `.gitconfig` files.

```swift
struct GitConfigRulesManager {
    func apply(profiles: [GitProfile])  // rewrites all includeIf blocks
    func writeCompanionConfig(for profile: GitProfile)
    func removeCompanionConfig(for profile: GitProfile)
    func writeRepoOverride(path: String, profile: GitProfile) throws
    func removeRepoOverride(path: String) throws
}
```

`apply(profiles:)` is called whenever any profile's rules change. It rewrites the managed section of `~/.gitconfig` atomically, leaving all other content untouched.

---

## UI Changes

### ProfileFormView additions

Below existing fields:

```
[ Connect via GitHub ]

Folders (apply to all repos inside)
────────────────────────────────────
  ~/work/                     [Remove]
  ~/clients/                  [Remove]
  [ + Add Folder ]

Specific Repos (override for one repo)
────────────────────────────────────
  ~/personal/dotfiles/        [Remove]
  [ + Add Repo ]
```

**"Connect via GitHub" button:**
- Tries `gh api user` first
- If successful: fills gitName, gitEmail, githubLogin; shows "Connected as @{login} ✓" in green
- If `gh` not found: inline text field appears asking for GitHub username; on submit fetches public API

### ProfileSettingsView
No changes needed — the form handles everything.

### Menu bar
No changes needed — `includeIf` and repo overrides are transparent to the app at runtime.

---

## Error Handling

| Scenario | Handling |
|---|---|
| `gh` not authenticated | Fall back to username lookup silently |
| GitHub API rate limited | Show "Rate limited — enter name/email manually" |
| GitHub username not found | Inline error: "No GitHub user found for '{username}'" |
| Selected folder not accessible | `NSOpenPanel` handles permissions |
| Selected repo has no `.git/` | Show inline error: "Not a git repository" |
| `~/.gitconfig` write fails | `os_log` error + show alert in settings view |
| Repo `.git/config` write fails | Throw + show inline error in form |

---

## Testing

- `GitHubImporter`: unit tests with mocked `gh` output and mocked URL session
- `GitConfigRulesManager`: unit tests using temp `~/.gitconfig` copies (same pattern as `GitConfigManagerTests`)
- UI: build verification only (no unit tests for view layer)
