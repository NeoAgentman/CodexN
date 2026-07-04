# CodexN Menu Bar

Native macOS menu bar launcher for CodexN profiles. This app is implemented in Swift and does not depend on Node.js.

## Build

```bash
cd CodexNMenuBar
swift run CodexNCoreTestRunner
swift build --product CodexNMenuBar
```

## Package App

```bash
cd CodexNMenuBar
scripts/package-app.sh
open CodexN.app
```

The app reads and writes its profile registry at:

```text
~/.codex-profiles/profiles.json
```

Set `CODEXN_ROOT` before launching the app executable if you need a different profile root.

Use `Settings...` from the menu bar app to create profiles:

- `Import from default` copies the system default `~/.codex` and Electron user data into a new profile.
- `New profile` + `OAuth login` creates isolated empty Codex home and Electron user data directories. Codex initializes them when you first open that profile.
- `New profile` + `Custom API key` writes a minimal `codex-home/config.toml` with a generated `env_key`. The API key itself is stored in `profiles.json` for this first local version and is injected only when launching that profile.

`Remove` only removes a profile from the registry. It does not create a backup and does not delete profile files from disk. Use `Backup` explicitly when you want an archive.

The profile list also includes `origin`. It opens the default Codex CLI/Desktop without setting `CODEX_HOME`, `CODEX_ELECTRON_USER_DATA_PATH`, or a Chromium `--user-data-dir`.
