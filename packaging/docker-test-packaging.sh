#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# docker-test-packaging.sh — spin up distro containers and verify packaging
# Run from the repo root: bash packaging/docker-test-packaging.sh [target ...]
#
# With no arguments, all targets are tested.
# Pass one or more target labels to test only those:
#   bash packaging/docker-test-packaging.sh debian-trixie fedora-42
# ---------------------------------------------------------------------------

# Color helpers (suppressed when not writing to a terminal)
if [[ -t 1 ]]; then
  GREEN='\033[32m'
  RED='\033[31m'
  RESET='\033[0m'
else
  GREEN=''
  RED=''
  RESET=''
fi

pass() { printf "${GREEN}PASS${RESET}\n"; }
fail() { printf "${RED}FAIL${RESET}\n"; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found in PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Version detection
# ---------------------------------------------------------------------------
VERSION="$(grep '^pkgver=' packaging/arch/PKGBUILD | cut -d= -f2)"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: could not detect version from packaging/arch/PKGBUILD" >&2
  exit 1
fi
echo "==> Version: $VERSION"

LOG_DIR="$(mktemp -d)"
CURRENT_CID_FILE=""

cleanup() {
  rm -rf "$LOG_DIR"
}
trap cleanup EXIT

interrupt_handler() {
  echo ""
  echo "==> Interrupted — stopping container..."
  if [[ -n "$CURRENT_CID_FILE" && -f "$CURRENT_CID_FILE" ]]; then
    local cid
    cid="$(cat "$CURRENT_CID_FILE" 2>/dev/null || true)"
    if [[ -n "$cid" ]]; then
      docker kill "$cid" &>/dev/null || true
    fi
  fi
  exit 130
}
trap interrupt_handler INT

# ---------------------------------------------------------------------------
# Target matrix
# ---------------------------------------------------------------------------
# Each entry: "label|image|type"
TARGETS=(
  "debian-trixie|debian:trixie|deb"
  "ubuntu-2404|ubuntu:24.04|deb"
  "ubuntu-2510|ubuntu:25.10|deb"
  "fedora-42|fedora:42|rpm"
  "fedora-43|fedora:43|rpm"
  "fedora-rawhide|fedora:rawhide|rpm"
  "arch|archlinux:latest|arch"
)

# ---------------------------------------------------------------------------
# Filter targets by CLI arguments (if any)
# ---------------------------------------------------------------------------
if [[ $# -gt 0 ]]; then
  # Collect valid labels for error reporting
  ALL_LABELS=()
  for entry in "${TARGETS[@]}"; do
    IFS='|' read -r label _ _ <<< "$entry"
    ALL_LABELS+=("$label")
  done

  FILTERED=()
  for requested in "$@"; do
    found=0
    for entry in "${TARGETS[@]}"; do
      IFS='|' read -r label _ _ <<< "$entry"
      if [[ "$label" == "$requested" ]]; then
        FILTERED+=("$entry")
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "ERROR: unknown target '$requested'" >&2
      echo "Valid targets: ${ALL_LABELS[*]}" >&2
      exit 1
    fi
  done
  TARGETS=("${FILTERED[@]}")
fi

# ---------------------------------------------------------------------------
# Build commands per type
# ---------------------------------------------------------------------------
deb_cmd() {
  cat <<'EOF'
set -euo pipefail
apt-get update -qq
mkdir -p /work
cp -r /src /work/alicebar
cd /work/alicebar
bash ./packaging/build-deb.sh
EOF
}

rpm_cmd() {
  local ver="$1"
  cat <<EOF
set -euo pipefail
dnf install -y rpm-build clang cmake ninja-build pkg-config curl tar git which \
  wayland-devel wayland-protocols-devel \
  gtk3-devel gtk-layer-shell-devel \
  atk-devel gdk-pixbuf2-devel harfbuzz-devel \
  libepoxy-devel libxkbcommon-devel pango-devel cairo-devel \
  cargo rust dbus-devel
mkdir -p /rpms /srpms /rpmbuild
# Build source tarball from the bind-mounted repo (avoids host bind-mount issues)
tar -czf /rpmbuild/alicebar-${ver}.tar.gz \
  --transform "s|^\./|alicebar-${ver}/|" \
  -C /src .
rpmbuild -ba /src/packaging/fedora/alicebar.spec \
  --define "_sourcedir /rpmbuild" \
  --define "_rpmdir /rpms" \
  --define "_srcrpmdir /srpms" \
  --define "_builddir /rpmbuild"
EOF
}

arch_cmd() {
  local ver="$1"
  cat <<EOF
set -euo pipefail
pacman -Syu --noconfirm base-devel clang cmake ninja pkg-config \\
  wayland wayland-protocols gtk3 gtk-layer-shell rustup curl git

# Download Flutter SDK
FLUTTER_VERSION=3.41.4
mkdir -p /opt/flutter
curl -Lo /tmp/flutter.tar.xz \\
  "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_\${FLUTTER_VERSION}-stable.tar.xz"
tar -xf /tmp/flutter.tar.xz --strip-components=1 -C /opt/flutter

# Set up non-root builder user
useradd -m builder
cp -r /src /home/builder/build
mkdir -p /home/builder/srcdest
# Build source tarball from the bind-mounted repo (avoids host bind-mount issues)
tar -czf /home/builder/srcdest/alicebar-${ver}.tar.gz \
  --transform "s|^\./|alice-${ver}/|" \
  -C /src .
chown -R builder:builder /home/builder/build /home/builder/srcdest /opt/flutter

su builder -c "
  set -euo pipefail
  cd /home/builder/build/packaging/arch
  SRCDEST=/home/builder/srcdest \\
  PATH=/opt/flutter/bin:\\\$PATH \\
  makepkg --noconfirm --skippgpcheck --nodeps
"
EOF
}

# ---------------------------------------------------------------------------
# Run targets
# ---------------------------------------------------------------------------
TOTAL="${#TARGETS[@]}"
PASSED=0

for entry in "${TARGETS[@]}"; do
  IFS='|' read -r label image type <<< "$entry"
  logfile="${LOG_DIR}/${label}.log"
  # mktemp to get a unique path, then remove it — docker requires cidfile to not exist
  CURRENT_CID_FILE="$(mktemp)"
  rm -f "$CURRENT_CID_FILE"

  printf "==> [%-16s] running... " "$label"

  rc=0
  case "$type" in
    deb)
      docker run --rm --cidfile "$CURRENT_CID_FILE" \
        -v "$(pwd):/src:ro" \
        "$image" \
        bash -c "$(deb_cmd)" \
        >"$logfile" 2>&1 || rc=$?
      ;;
    rpm)
      docker run --rm --cidfile "$CURRENT_CID_FILE" \
        -v "$(pwd):/src:ro" \
        "$image" \
        bash -c "$(rpm_cmd "$VERSION")" \
        >"$logfile" 2>&1 || rc=$?
      ;;
    arch)
      docker run --rm --cidfile "$CURRENT_CID_FILE" \
        -v "$(pwd):/src:ro" \
        "$image" \
        bash -c "$(arch_cmd "$VERSION")" \
        >"$logfile" 2>&1 || rc=$?
      ;;
  esac

  rm -f "$CURRENT_CID_FILE"
  CURRENT_CID_FILE=""

  if [[ $rc -eq 0 ]]; then
    (( PASSED++ )) || true
    pass
  else
    fail
    echo ""
    echo "---------- LOG: $label ----------"
    cat "$logfile"
    echo ""
    exit 1
  fi
done

echo ""
echo "${PASSED}/${TOTAL} passed."
