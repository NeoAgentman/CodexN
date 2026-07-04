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

The app reads and writes the same profile registry as the CLI by default:

```text
~/.codex-profiles/profiles.json
```

Set `CODEXN_ROOT` before launching the app executable if you need a different profile root.

`Remove` only removes a profile from the registry. It does not create a backup and does not delete profile files from disk. Use `Backup` explicitly when you want an archive.

The profile list also includes `origin (system default)`. It opens the default Codex CLI/Desktop without setting `CODEX_HOME`, `CODEX_ELECTRON_USER_DATA_PATH`, or a Chromium `--user-data-dir`.
