# CodexN

CodexN is a macOS launcher for running multiple isolated Codex environments on one machine.

It provides:

- a small `codexn` CLI for profile management
- a native Swift menu bar app for opening Codex Desktop or CLI profiles
- isolated `CODEX_HOME` and Electron user-data directories per profile
- an `origin (system default)` entry for launching your normal system Codex

This is useful when you want separate Codex accounts, providers, auth state, sessions, plugins, and Desktop user data on the same Mac.

## How It Works

Each managed profile gets its own directory under `~/.codex-profiles` by default:

```text
~/.codex-profiles/<profile-id>/
  codex-home/
  electron-user-data/
  logs/
```

When launching a managed profile, CodexN sets:

```text
CODEX_HOME=<profile>/codex-home
CODEX_ELECTRON_USER_DATA_PATH=<profile>/electron-user-data
--user-data-dir=<profile>/electron-user-data
```

Codex itself initializes `config.toml`, auth files, sessions, plugins, and other Codex-owned data when you first open that profile.

## CLI

```bash
npm install
node ./bin/codexn.js init work --name Work
node ./bin/codexn.js import-default default --name Default
node ./bin/codexn.js list
node ./bin/codexn.js desktop work
node ./bin/codexn.js cli work -- --help
```

Supported commands:

```text
init <id> [--name <name>]
import-default <id> [--name <name>]
list [--json]
desktop <id> [--project <path>] [--app <Codex|/path/Codex.app>]
cli <id> -- <codex args...>
backup <id>
remove <id> [--yes]
```

`remove` only removes the profile from the registry. It does not delete profile files and does not create a backup automatically.

## Menu Bar App

The native app lives in `CodexNMenuBar`.

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

- opening the system default Codex via `origin (system default)`
- creating empty OAuth-login profiles
- importing the current default Codex profile
- creating custom API-key profiles
- launching Codex Desktop and CLI for each managed profile
- backing up or removing profile registry entries

For the first local version, custom API keys are stored in `~/.codex-profiles/profiles.json`. The generated `config.toml` stores only a random `env_key`; CodexN injects the matching API key into the child process environment when launching that profile.

## Development

Run Node checks and tests:

```bash
npm run check
npm test
```

Run Swift checks:

```bash
cd CodexNMenuBar
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
```

## Safety Notes

- Do not open multiple Codex Desktop windows against the same managed profile unless you are comfortable with shared local state writes.
- `init` refuses to reuse a non-empty profile directory.
- `import-default` copies both `~/.codex` and `~/Library/Application Support/Codex` into a new managed profile.
- Profile data can become large because it contains sessions, plugins, caches, and Electron user data.
