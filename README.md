# CodexN

CodexN is a macOS-only launcher for running multiple isolated Codex environments on one machine.

Each profile owns:

- `CODEX_HOME`
- `CODEX_ELECTRON_USER_DATA_PATH`
- Codex `config.toml`
- Codex `auth.json`
- local sessions, sqlite state, logs, and plugins under that home

This lets `personal`, `work`, `relay`, or other profiles use different Codex accounts and providers without sharing the default `~/.codex` state.

## Quick Start

```bash
npm link
codexn init personal --name Personal
codexn init work --name Work
codexn login work
codexn desktop work
codexn terminal work
codexn gui
```

Profile data is stored in `~/.codex-profiles` by default. Override it with `CODEXN_ROOT`.

## Commands

```bash
codexn init <id> [--name <name>] [--from-current]
codexn list [--json]
codexn doctor <id> [--json]
codexn desktop <id> [--project <path>]
codexn terminal <id> [--project <path>]
codexn cli <id> -- <codex args...>
codexn login <id>
codexn provider <id> set --id <provider> [--base-url <url>] [--api-key <key>] [--model <model>]
codexn backup <id>
codexn import-current <id>
codexn reveal <id>
codexn gui
```

## Desktop Isolation

Desktop launch uses macOS `open -n` with both isolation knobs:

```bash
CODEX_HOME=<profile>/codex-home
CODEX_ELECTRON_USER_DATA_PATH=<profile>/electron-user-data
--user-data-dir=<profile>/electron-user-data
```

Codex Desktop itself handles multi-window startup. CodexN does not clone or patch the app bundle.

## Provider Setup

Example:

```bash
codexn provider work set \
  --id relay \
  --name Relay \
  --base-url https://api.example.com/v1 \
  --api-key RELAY_API_KEY \
  --model gpt-5.2-codex
```

If `--api-key` starts with `sk-`, CodexN writes it as `experimental_bearer_token`. Otherwise it writes the value as `env_key`.

## Safety Notes

- Do not run multiple Desktop windows against the same profile at the same time unless you are comfortable with shared SQLite/session writes.
- `import-current` copies your current `~/.codex` into the selected profile and may overwrite files in that profile.
- `remove` creates a backup archive before removing the profile from the registry, but it does not delete profile files from disk.
