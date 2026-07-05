#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="${1:?usage: package-version.sh VERSION_FILE}"

if [[ -n "${CODEXN_VERSION:-}" ]]; then
  printf '%s\n' "$CODEXN_VERSION"
  exit 0
fi

DEFAULT_VERSION="${CODEXN_DEFAULT_VERSION:-0.1.11}"
CURRENT_VERSION="$DEFAULT_VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

if [[ "${CODEXN_AUTO_BUMP_VERSION:-1}" == "0" ]]; then
  printf '%s\n' "$CURRENT_VERSION"
  exit 0
fi

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Invalid version in $VERSION_FILE: $CURRENT_VERSION" >&2
  exit 1
fi

NEXT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
printf '%s\n' "$NEXT_VERSION" > "$VERSION_FILE"
printf '%s\n' "$NEXT_VERSION"
