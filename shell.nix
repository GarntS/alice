{ pkgs ? import <nixpkgs> {} }:
let
  linuxLibraries = with pkgs; [
    atk
    at-spi2-atk
    cairo
    dbus
    gdk-pixbuf
    glib
    gtk3
    gtk-layer-shell
    harfbuzz
    libepoxy
    libxkbcommon
    pango
    stdenv.cc.cc.lib
    stdenv.cc.libc
    wayland
    xorg.libX11
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    zlib
  ];
in
(pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
  packages = with pkgs; [
    cargo
    clang
    cmake
    dart
    flutter
    ninja
    pkg-config
    rustc
    rustfmt
    wayland-scanner
  ] ++ linuxLibraries;

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath linuxLibraries;

  shellHook = ''
    export CC=${pkgs.clang}/bin/clang
    export CXX=${pkgs.clang}/bin/clang++
    export CMAKE_C_COMPILER="$CC"
    export CMAKE_CXX_COMPILER="$CXX"
    export XDG_CACHE_HOME="$PWD/.cache"
    export PUB_CACHE="$PWD/.pub-cache"
    export CARGO_HOME="$PWD/.cargo-home"

    mkdir -p "$XDG_CACHE_HOME" "$PUB_CACHE" "$CARGO_HOME"

    echo "alice dev shell ready"
    echo "  flutter: $(command -v flutter)"
    echo "  clang++: $(command -v clang++)"
    echo "  pkg-config: $(command -v pkg-config)"
  '';
}
