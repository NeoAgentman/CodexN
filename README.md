# CodexN

CodexN is a macOS-only launcher for running multiple isolated Codex environments on one machine.

Each profile owns isolated paths for:

- `CODEX_HOME`
- `CODEX_ELECTRON_USER_DATA_PATH`
- Codex `config.toml` and `auth.json` after Codex creates them
- local sessions, sqlite state, logs, and plugins under that home

This lets `personal`, `work`, or other profiles use different Codex accounts and providers without sharing the default `~/.codex` or Desktop user data state.

## Quick Start

```bash
npm link
codexn import-default default
codexn init personal --name Personal
codexn init work --name Work
codexn desktop work
codexn cli work -- --help
```

Profile data is stored in `~/.codex-profiles` by default. Override it with `CODEXN_ROOT`.

## Commands

```bash
codexn init <id> [--name <name>]
codexn import-default <id> [--name <name>]
codexn list [--json]
codexn desktop <id> [--project <path>] [--app <Codex|/path/Codex.app>]
codexn cli <id> -- <codex args...>
codexn backup <id>
codexn remove <id> [--yes]
```

## Desktop Isolation

Desktop launch uses macOS `open -n` with both isolation knobs:

```bash
CODEX_HOME=<profile>/codex-home
CODEX_ELECTRON_USER_DATA_PATH=<profile>/electron-user-data
--user-data-dir=<profile>/electron-user-data
```

Codex Desktop itself handles multi-window startup. CodexN does not clone or patch the app bundle.

`init` only creates the profile registry entry and empty isolated directories. It does not create `config.toml`, `auth.json`, sessions, or any other Codex-owned configuration. The first `codexn cli` or `codexn desktop` run lets Codex initialize that profile's `CODEX_HOME` itself.

`import-default` creates a new profile and copies both default locations into it:

```text
~/.codex -> <profile>/codex-home
~/Library/Application Support/Codex -> <profile>/electron-user-data
```

## Safety Notes

- Do not run multiple Desktop windows against the same profile at the same time unless you are comfortable with shared SQLite/session writes.
- `init` refuses to reuse a non-empty profile directory. Pick a new id or clean the old directory first.
- `import-default` requires a new profile id and copies the current default Codex CLI and Desktop data into that profile.
- `remove` only removes the profile from the registry. It does not create a backup and does not delete profile files from disk. Run `backup` explicitly when you want an archive.
