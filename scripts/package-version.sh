#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-${CODEXN_VERSION:-}}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: package-version.sh VERSION" >&2
  echo "Or set CODEXN_VERSION=VERSION." >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

printf '%s\n' "$VERSION"
