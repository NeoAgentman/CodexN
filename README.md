# CodexN

CodexN is a native macOS menu bar launcher for running multiple isolated Codex environments on one machine.

It provides:

- a Swift menu bar app for opening isolated Codex app profiles
- isolated `CODEX_HOME` and Electron user-data directories per profile
- a `Default Codex` entry for launching the normal system Codex environment
- a menu bar token-usage chart for today's per-profile Codex usage
- Settings for managing profiles, adding profiles, controlling app startup behavior, and viewing app version details

This is useful when you want separate Codex accounts, providers, auth state, sessions, plugins, and Desktop user data on the same Mac.

## How It Works

Each profile gets its own directory under `~/.codex-profiles` by default:

```text
~/.codex-profiles/<profile-id>/
  codex-home/
  electron-user-data/
  logs/
```

When launching a profile, CodexN sets:

```text
CODEXN_PROFILE_ID=<profile-id>
CODEX_HOME=<profile>/codex-home
CODEX_ELECTRON_USER_DATA_PATH=<profile>/electron-user-data
--user-data-dir=<profile>/electron-user-data
--codexn-profile-id=<profile-id>
```

Codex itself initializes `config.toml`, auth files, sessions, plugins, and other Codex-owned data when you first open that profile.
CodexN uses the explicit profile id to update its menu bar title when a Codex window is focused, so the title changes from `CodexN` to `CodexN | <profile-id>` for managed profiles and `CodexN | Default` for the system default Codex app.

## Menu Bar App

The native app is implemented in Swift and does not depend on Node.js.

Build and package:

```bash
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
scripts/package-app.sh 0.1.12
open CodexN.app
```

`scripts/package-app.sh` requires an explicit semantic version and does not read or update a `VERSION` file. You can pass the version as the first argument, or use `CODEXN_VERSION=0.1.12 scripts/package-app.sh`.

Install locally:

```bash
ditto CodexN.app /Applications/CodexN.app
```

The menu bar app supports:

- opening the system default Codex by clicking the first-level `Default Codex` menu item
- opening a profile's Codex app by clicking that profile directly in the first-level menu
- showing the currently focused Codex environment in the menu bar title, with the active profile id highlighted
- viewing today's token usage as a cached menu bar chart, refreshed in the background at launch and every 30 minutes
- creating empty OAuth-login profiles from `Settings...` -> `Profiles` -> `Add Profile`
- importing the current default Codex profile from `Settings...` -> `Profiles` -> `Add Profile`
- creating custom API-key profiles from `Settings...` -> `Profiles` -> `Add Profile`
- removing profile registry entries from `Settings...` -> `Profiles`
- opening the managed profiles folder from the menu
- enabling or disabling launch at login from `Settings...` -> `General`
- viewing version, build number, and build time from `About...` or `Settings...` -> `About`

For the first local version, custom API keys are stored in `~/.codex-profiles/profiles.json`. The generated `config.toml` stores only a random `env_key`; CodexN injects the matching API key into the child process environment when launching that profile.

Set `CODEXN_ROOT` before launching the app executable if you need a different profile root.

`Remove Profile` only removes the profile from `profiles.json`. It does not delete that profile's `codex-home`, `electron-user-data`, or `logs` directories from disk.

Usage statistics are read from each profile's `codex-home/sessions` and `codex-home/archived_sessions` logs, plus the system default `~/.codex` logs. The scanner targets the current day's partitioned logs and recently modified active sessions, then records the latest totals in `~/.codex-profiles/usage-cache.json`; the menu only reads that cache and does not estimate cost.

## Development

Run Swift checks:

```bash
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
```

## Safety Notes

- Do not open multiple Codex Desktop windows against the same profile unless you are comfortable with shared local state writes.
- Empty profiles do not pre-generate Codex config. Codex initializes its own files on first launch.
- Importing the default profile copies both `~/.codex` and `~/Library/Application Support/Codex` into a new profile.
- Profile data can become large because it contains sessions, plugins, caches, and Electron user data.
