#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VERSION_FILE="$TMP_DIR/VERSION"
printf '0.1.11\n' > "$VERSION_FILE"

NEXT_VERSION="$("$ROOT/scripts/package-version.sh" "$VERSION_FILE")"
if [[ "$NEXT_VERSION" != "0.1.12" ]]; then
  echo "expected bumped version 0.1.12, got $NEXT_VERSION" >&2
  exit 1
fi
if [[ "$(cat "$VERSION_FILE")" != "0.1.12" ]]; then
  echo "expected VERSION file to contain 0.1.12" >&2
  exit 1
fi

OVERRIDE_VERSION="$(CODEXN_VERSION=9.8.7 "$ROOT/scripts/package-version.sh" "$VERSION_FILE")"
if [[ "$OVERRIDE_VERSION" != "9.8.7" ]]; then
  echo "expected override version 9.8.7, got $OVERRIDE_VERSION" >&2
  exit 1
fi
if [[ "$(cat "$VERSION_FILE")" != "0.1.12" ]]; then
  echo "CODEXN_VERSION override should not rewrite VERSION file" >&2
  exit 1
fi

PINNED_VERSION="$(CODEXN_AUTO_BUMP_VERSION=0 "$ROOT/scripts/package-version.sh" "$VERSION_FILE")"
if [[ "$PINNED_VERSION" != "0.1.12" ]]; then
  echo "expected pinned version 0.1.12, got $PINNED_VERSION" >&2
  exit 1
fi
