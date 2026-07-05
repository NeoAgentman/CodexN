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

Packaging increments the patch version stored in `VERSION` by default. To package without bumping the file, run `CODEXN_AUTO_BUMP_VERSION=0 scripts/package-app.sh`. To package with a temporary explicit version, run `CODEXN_VERSION=0.1.99 scripts/package-app.sh`.

The app reads and writes its profile registry at:

```text
~/.codex-profiles/profiles.json
```

Set `CODEXN_ROOT` before launching the app executable if you need a different profile root.

Use `Settings...` from the menu bar app to manage profiles:

- `Profiles` lists the managed profiles and provides the remove action for each one.
- `Profiles` -> `Add Profile` -> `Import Default` copies the system default `~/.codex` and Electron user data into a new profile.
- `Profiles` -> `Add Profile` -> `OAuth Login` creates isolated empty Codex home and Electron user data directories. Codex initializes them when you first open that profile.
- `Profiles` -> `Add Profile` -> `API Key` writes a minimal `codex-home/config.toml` with a generated `env_key`. The API key itself is stored in `profiles.json` for this first local version and is injected only when launching that profile.
- `General` controls whether CodexN opens at login.
- `About` shows the app version, build number, build time, and project link. The `About...` menu item opens this same pane directly.

`Remove Profile` only removes a profile from the registry. It does not delete profile files from disk.

The menu also includes a first-level `Default Codex` item. It opens the default Codex app without inheriting CodexN profile environment variables or setting a Chromium `--user-data-dir`.

Each managed profile also appears as a first-level menu item. Clicking a profile opens the Codex app for that profile directly.
Managed launches inject `CODEXN_PROFILE_ID` and `--codexn-profile-id=<profile-id>` so CodexN can identify focused Codex windows directly. When a Codex window is focused, the menu bar title changes to `CodexN | <profile-id>` for managed profiles or `CodexN | Default` for the system default app; the active profile segment is highlighted.

The token-usage chart reads `usage-cache.json` from the profile root. CodexN refreshes that cache in the background at launch and every 30 minutes; the menu itself only reads the cache.
