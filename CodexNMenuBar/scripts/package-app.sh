#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/CodexN.app"
EXECUTABLE="$ROOT/.build/release/CodexNMenuBar"
ICON="$ROOT/Assets/CodexN.icns"
VERSION="${CODEXN_VERSION:-0.1.7}"
BUILD="${CODEXN_BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
BUILD_DATE="${CODEXN_BUILD_DATE:-$(date -u "+%Y-%m-%d %H:%M:%S UTC")}"

cd "$ROOT"
swift build -c release --product CodexNMenuBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/CodexN"
cp "$ICON" "$APP/Contents/Resources/CodexN.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>CodexN</string>
  <key>CFBundleIdentifier</key>
  <string>local.codexn.menubar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>CodexN</string>
  <key>CFBundleName</key>
  <string>CodexN</string>
  <key>CFBundleDisplayName</key>
  <string>CodexN</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>CodexNBuildDate</key>
  <string>$BUILD_DATE</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
