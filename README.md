# CodexN

CodexN is a native macOS menu bar launcher for running multiple isolated Codex environments on one machine.

It provides:

- a Swift menu bar app for opening isolated Codex app profiles
- isolated `CODEX_HOME` and Electron user-data directories per profile
- a `Default Codex` entry for launching the normal system Codex environment
- Settings for adding profiles and controlling app startup behavior

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
CODEX_HOME=<profile>/codex-home
CODEX_ELECTRON_USER_DATA_PATH=<profile>/electron-user-data
--user-data-dir=<profile>/electron-user-data
```

Codex itself initializes `config.toml`, auth files, sessions, plugins, and other Codex-owned data when you first open that profile.

## Menu Bar App

The native app lives in `CodexNMenuBar` and does not depend on Node.js.

Build and package:

```bash
cd CodexNMenuBar
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
scripts/package-app.sh
open CodexN.app
```

Install locally:

```bash
ditto CodexNMenuBar/CodexN.app /Applications/CodexN.app
```

The menu bar app supports:

- opening the system default Codex via `Default Codex`
- creating empty login profiles
- importing the current default Codex profile
- creating custom API-key profiles
- launching the Codex app for each profile
- backing up or removing profile registry entries
- enabling or disabling launch at login from Settings

For the first local version, custom API keys are stored in `~/.codex-profiles/profiles.json`. The generated `config.toml` stores only a random `env_key`; CodexN injects the matching API key into the child process environment when launching that profile.

## Development

Run Swift checks:

```bash
cd CodexNMenuBar
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
```

## Safety Notes

- Do not open multiple Codex Desktop windows against the same profile unless you are comfortable with shared local state writes.
- Empty profiles do not pre-generate Codex config. Codex initializes its own files on first launch.
- Importing the default profile copies both `~/.codex` and `~/Library/Application Support/Codex` into a new profile.
- Profile data can become large because it contains sessions, plugins, caches, and Electron user data.
