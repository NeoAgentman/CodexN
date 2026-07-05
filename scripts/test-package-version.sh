#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VERSION_FILE="$TMP_DIR/VERSION"
printf '0.1.11\n' > "$VERSION_FILE"

if "$ROOT/scripts/package-version.sh" >/dev/null 2>&1; then
  echo "package-version.sh should fail when no explicit version is provided" >&2
  exit 1
fi

if "$ROOT/scripts/package-app.sh" >/dev/null 2>&1; then
  echo "package-app.sh should fail when no explicit version is provided" >&2
  exit 1
fi

ARG_VERSION="$("$ROOT/scripts/package-version.sh" 9.8.7)"
if [[ "$ARG_VERSION" != "9.8.7" ]]; then
  echo "expected argument version 9.8.7, got $ARG_VERSION" >&2
  exit 1
fi

OVERRIDE_VERSION="$(CODEXN_VERSION=9.8.7 "$ROOT/scripts/package-version.sh")"
if [[ "$OVERRIDE_VERSION" != "9.8.7" ]]; then
  echo "expected override version 9.8.7, got $OVERRIDE_VERSION" >&2
  exit 1
fi

if [[ "$(cat "$VERSION_FILE")" != "0.1.11" ]]; then
  echo "explicit version resolution should not rewrite VERSION file" >&2
  exit 1
fi

if "$ROOT/scripts/package-version.sh" 9.8 >/dev/null 2>&1; then
  echo "package-version.sh should reject invalid semantic versions" >&2
  exit 1
fi
