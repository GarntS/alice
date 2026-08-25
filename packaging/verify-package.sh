#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <deb|rpm|arch> <artifact> <expected-app-version>" >&2
  exit 2
fi

FORMAT="$1"
ARTIFACT="$(readlink -f "$2")"
EXPECTED_VERSION="$3"
PACKAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$PACKAGE_ROOT"' EXIT

case "$FORMAT" in
  deb)
    PACKAGE_VERSION="$(dpkg-deb --field "$ARTIFACT" Version)"
    APP_PACKAGE_VERSION="${PACKAGE_VERSION#*:}"
    APP_PACKAGE_VERSION="${APP_PACKAGE_VERSION%-*}"
    dpkg-deb --extract "$ARTIFACT" "$PACKAGE_ROOT"
    ;;
  rpm)
    PACKAGE_VERSION="$(rpm -qp --queryformat '%{VERSION}' "$ARTIFACT")"
    APP_PACKAGE_VERSION="$PACKAGE_VERSION"
    (
      cd "$PACKAGE_ROOT"
      rpm2cpio "$ARTIFACT" | cpio -idm --quiet
    )
    ;;
  arch)
    PACKAGE_VERSION="$(tar -xOf "$ARTIFACT" .PKGINFO | awk -F' = ' '$1 == "pkgver" { print $2; exit }')"
    APP_PACKAGE_VERSION="${PACKAGE_VERSION%-*}"
    tar -xf "$ARTIFACT" -C "$PACKAGE_ROOT"
    ;;
  *)
    echo "ERROR: unsupported package format '$FORMAT'" >&2
    exit 2
    ;;
esac

if [[ "$APP_PACKAGE_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: $FORMAT package version '$PACKAGE_VERSION' does not match application version '$EXPECTED_VERSION'" >&2
  exit 1
fi

if [[ "$FORMAT" == "deb" && ! -e "$PACKAGE_ROOT/usr/lib/alicebar/lib/libgtk-layer-shell.so.0" ]]; then
  echo "ERROR: deb package is missing its private gtk-layer-shell runtime" >&2
  exit 1
fi

for executable in \
  "$PACKAGE_ROOT/usr/bin/alicebar" \
  "$PACKAGE_ROOT/usr/lib/alicebar/alicebar"
do
  if [[ ! -x "$executable" ]]; then
    echo "ERROR: $FORMAT package is missing executable ${executable#"$PACKAGE_ROOT"}" >&2
    exit 1
  fi
done

VERSION_FILE="$PACKAGE_ROOT/usr/lib/alicebar/data/flutter_assets/version.json"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "ERROR: $FORMAT package is missing Flutter version metadata" >&2
  exit 1
fi

EMBEDDED_VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$VERSION_FILE")"
EMBEDDED_VERSION="${EMBEDDED_VERSION%%+*}"
if [[ "$EMBEDDED_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: $FORMAT package embeds application version '$EMBEDDED_VERSION', expected '$EXPECTED_VERSION'" >&2
  exit 1
fi

printf 'Verified %s: package=%s application=%s\n' "$ARTIFACT" "$PACKAGE_VERSION" "$EMBEDDED_VERSION"
