#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$("$ROOT_DIR/packaging/version.sh")"
EXPECTED_TAG="${1:-}"

DEB_VERSION="$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$ROOT_DIR/packaging/deb/changelog")"
DEB_VERSION="${DEB_VERSION#*:}"
DEB_VERSION="${DEB_VERSION%-*}"
FEDORA_VERSION="$(sed -n 's/.*alicebar_version:\([^}]*\)}.*/\1/p' "$ROOT_DIR/packaging/fedora/alicebar.spec" | head -1)"
ARCH_VERSION="$(awk -F= '$1 == "pkgver" { print $2; exit }' "$ROOT_DIR/packaging/arch/PKGBUILD")"

status=0
check_version() {
  local source="$1"
  local actual="$2"
  if [[ "$actual" != "$APP_VERSION" ]]; then
    echo "ERROR: $source version '$actual' does not match pubspec version '$APP_VERSION'" >&2
    status=1
  fi
}

check_version "Debian changelog" "$DEB_VERSION"
check_version "Fedora spec fallback" "$FEDORA_VERSION"
check_version "Arch PKGBUILD" "$ARCH_VERSION"

if [[ -n "$EXPECTED_TAG" ]]; then
  check_version "release tag" "${EXPECTED_TAG#v}"
fi

exit "$status"
