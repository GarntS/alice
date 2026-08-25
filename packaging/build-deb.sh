#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.47.0"
FLUTTER_SDK="$(pwd)/.flutter-sdk"
APP_VERSION="$(./packaging/version.sh)"

./packaging/check-version-sync.sh

# Install build dependencies
apt-get update -qq
apt-get install -y --no-install-recommends \
  ca-certificates build-essential debhelper clang cmake ninja-build pkg-config \
  curl file git unzip xz-utils zip \
  libwayland-bin libgtk-3-dev \
  libwayland-dev wayland-protocols \
  cargo rustc \
  libdbus-1-dev libatk1.0-dev libgdk-pixbuf-2.0-dev \
  libharfbuzz-dev libepoxy-dev libxkbcommon-dev \
  libpango1.0-dev libcairo2-dev \
  meson gobject-introspection libgirepository1.0-dev

# Build gtk-layer-shell 0.10.0 from source — distro ships 0.9.0 which is missing
# gtk_layer_set_respect_close (added in 0.10.0).
GTK_LAYER_SHELL_VERSION="0.10.0"
GTK_LAYER_SHELL_PREFIX="$(pwd)/.gtk-layer-shell-install"
curl -Lo /tmp/gtk-layer-shell.tar.gz \
  "https://github.com/wmww/gtk-layer-shell/archive/refs/tags/v${GTK_LAYER_SHELL_VERSION}.tar.gz"
tar -xf /tmp/gtk-layer-shell.tar.gz -C /tmp
rm -rf /tmp/gtk-layer-shell-build "$GTK_LAYER_SHELL_PREFIX"
meson setup /tmp/gtk-layer-shell-build \
  "/tmp/gtk-layer-shell-${GTK_LAYER_SHELL_VERSION}" \
  --prefix="$GTK_LAYER_SHELL_PREFIX" --libdir=lib \
  --buildtype=release -Dvapi=false
ninja -C /tmp/gtk-layer-shell-build install
export PKG_CONFIG_PATH="$GTK_LAYER_SHELL_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Download Flutter SDK
if [ ! -d "$FLUTTER_SDK" ]; then
  curl -Lo /tmp/flutter.tar.xz \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  mkdir -p "$FLUTTER_SDK"
  tar -xf /tmp/flutter.tar.xz --strip-components=1 -C "$FLUTTER_SDK"
fi
export PATH="$FLUTTER_SDK/bin:$PATH"

# Install latest stable Rust via rustup — distro rustc is often too old for crates.
# apt cargo/rustc remain installed only to satisfy the Build-Depends check.
export RUSTUP_HOME=/opt/rustup
export CARGO_HOME=/opt/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
  sh -s -- -y --no-modify-path --default-toolchain stable
export PATH="/opt/cargo/bin:$PATH"

# Allow git to operate on directories owned by a different uid (common in Docker)
git config --global --add safe.directory '*'

# dpkg-buildpackage expects debian/ in the working directory
ln -sf packaging/deb debian

# Build .deb
dpkg-buildpackage -us -uc -b \
  --rules-file="packaging/deb/rules"

# Reject packages with stale metadata, a missing payload, or an old app bundle.
PACKAGE_VERSION="$(dpkg-parsechangelog --show-field Version)"
PACKAGE_ARCH="$(dpkg-architecture --query DEB_HOST_ARCH)"
PACKAGE_PATH="../alicebar_${PACKAGE_VERSION}_${PACKAGE_ARCH}.deb"
./packaging/verify-package.sh deb "$PACKAGE_PATH" "$APP_VERSION"
