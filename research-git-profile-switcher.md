# Research: Git Profile Switcher — Modify GitHub Desktop vs. macOS Menu Bar App

## Problem Statement

Switch between personal and work Git identities (name, email, SSH key, signing key) quickly and reliably across all Git tools.

---

## Option 1: Modify GitHub Desktop

### Current State

GitHub Desktop is a large Electron + React + TypeScript app (~200k+ lines). It supports one GitHub.com account and one GitHub Enterprise account. There is **no concept of multiple Git identities per account** — `user.name` and `user.email` are set globally and apply to all commits.

### What Would Need to Change

| Component | Current | Required Change | Complexity |
|-----------|---------|-----------------|------------|
| Git Config Scope | Global only | Per-repo local config | Low |
| Profile Model | Account class | New `GitProfile` model | Low |
| UI - Repository Level | No git config UI | Profile selector in repo settings | Medium |
| Git Identity Selection | Automatic (global) | Per-commit profile selection | Medium |
| SSH Key Management | Not in scope | Store SSH key paths in keytar | Medium-High |
| Commit Creation | Uses global git config | Pass `GIT_AUTHOR_NAME/EMAIL` env vars | Low |

### Estimated Effort

- **MVP (git config + UI selector, no SSH):** 3–4 weeks
- **Production-ready with SSH:** 6–10 weeks
- **Maintenance burden:** Must keep fork in sync with upstream indefinitely

### Key Problems

1. Changes only affect behavior *inside GitHub Desktop* — terminal, VS Code, JetBrains are unaffected
2. Large codebase with tightly coupled account handling (auth, commits, API, UI)
3. Unlikely to be accepted upstream — niche feature for general audience
4. Permanent fork maintenance burden

---

## Option 2: macOS Menu Bar App (Swift/SwiftUI)

### Architecture

A lightweight menu bar utility using SwiftUI's `MenuBarExtra` (macOS 13+). Shows current Git profile in the menu bar; click to switch. Runs in background, no Dock icon.

### What Git Profile Switching Involves

A complete profile is:

| Field | Config Location | Required |
|-------|----------------|----------|
| `user.name` | `~/.gitconfig` or `.git/config` | Yes |
| `user.email` | `~/.gitconfig` or `.git/config` | Yes |
| SSH key path | `~/.ssh/config` or `core.sshCommand` | For SSH auth |
| Signing key | `user.signingkey` | For signed commits |
| Signing format | `gpg.format` (gpg or ssh) | For signed commits |

### Technology Comparison

| Criterion | Swift/SwiftUI | Tauri | Electron |
|-----------|--------------|-------|----------|
| App size | ~5–10 MB | ~5–15 MB | ~150–200 MB |
| Idle RAM | ~10–20 MB | ~20–30 MB | ~80–150 MB |
| Native feel | Excellent | Good | Poor |
| Cross-platform | No | Yes | Yes |
| Keychain access | Native API | Via Rust crates | Via npm |

**Swift/SwiftUI is the clear choice** — this is a macOS-only utility that should feel native and use minimal resources.

### MVP Scope (~10–15 hours)

1. Menu bar icon showing current profile name
2. Click to see list of profiles with checkmark on active
3. Click a profile to switch (`git config --global`)
4. Add/edit/delete profiles (name, email, SSH key path)
5. JSON persistence in `~/.config/git-profile-switcher/`
6. Launch at login via `SMAppService`

### Advanced Features (v2, ~30–45 hours total)

1. `includeIf` generation for directory-based auto-switching
2. `~/.ssh/config` management
3. Signing key management
4. Current repo profile detection

### Existing Tools

Many CLI tools exist but **no macOS menu bar app**:
- [gitego](https://github.com/bgreenwell/gitego) — most feature-rich CLI (Go)
- [git-switch](https://github.com/tsoodo/git-switch) — Rust CLI with SSH support
- [git-profile](https://github.com/takuma7/git-profile) — Rust CLI with signing key support

---

## Recommendation: Build the Menu Bar App

| Factor | Modify GitHub Desktop | Menu Bar App (Swift) |
|--------|----------------------|---------------------|
| Effort | 6–10 weeks | 1–2 weeks |
| Codebase size | ~200k lines to navigate | ~500–1000 lines |
| Resource usage | Already heavy (Electron) | 10 MB RAM, invisible |
| Maintenance | Must merge upstream forever | Self-contained |
| Scope of change | Deep (models, stores, UI, git) | Shallow (git config + simple UI) |
| Works everywhere | No (GitHub Desktop only) | Yes (all Git tools) |
| Native feel | Electron | Native macOS |

**The menu bar app is easier by an order of magnitude**, and it's more useful because it changes your global Git config — affecting GitHub Desktop, terminal, VS Code, and every other tool simultaneously.

### Recommended Approach

1. **Phase 1 (MVP):** SwiftUI menu bar app with profile CRUD and global git config switching
2. **Phase 2:** Add `includeIf` support for automatic directory-based profile switching (e.g., `~/work/` always uses work profile)
3. **Phase 3:** SSH config management and signing key support
4. **Auth strategy:** Recommend SSH over HTTPS to avoid the credential-collision problem (macOS Keychain stores one credential per hostname)
