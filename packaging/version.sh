#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(awk '$1 == "version:" { print $2; exit }' "$ROOT_DIR/pubspec.yaml")"
VERSION="${VERSION%%+*}"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9A-Za-z~]+)*$ ]]; then
  echo "ERROR: unsupported pubspec version '$VERSION'" >&2
  exit 1
fi

printf '%s\n' "$VERSION"
