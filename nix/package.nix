{ lib
, clangStdenv
, rustPlatform
, flutter
, dart
, cargo
, rustc
, cmake
, ninja
, pkg-config
, wayland-scanner
, makeWrapper
, git
, atk
, at-spi2-atk
, cairo
, dbus
, gdk-pixbuf
, glib
, gtk3
, gtk-layer-shell
, harfbuzz
, libepoxy
, libxkbcommon
, pango
, stdenv
, wayland
, xorg
, zlib
}:
let
  runtimeLibraries = [
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
clangStdenv.mkDerivation {
  pname = "alice";
  version = "1.0.0";

  src = lib.cleanSource ../.;
  cargoRoot = "native";
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../native/Cargo.lock;
  };

  nativeBuildInputs = [
    cargo
    rustc
    rustPlatform.cargoSetupHook
    cmake
    ninja
    pkg-config
    flutter
    dart
    wayland-scanner
    makeWrapper
    git
  ];

  buildInputs = runtimeLibraries;

  strictDeps = true;

  preBuild = ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export PUB_CACHE="$TMPDIR/pub-cache"
    export CARGO_HOME="$TMPDIR/cargo-home"
    export RUSTUP_HOME="$TMPDIR/rustup-home"
    export FLUTTER_SUPPRESS_ANALYTICS=true
    export CC=${clangStdenv.cc}/bin/clang
    export CXX=${clangStdenv.cc}/bin/clang++
    export CMAKE_C_COMPILER="$CC"
    export CMAKE_CXX_COMPILER="$CXX"

    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$PUB_CACHE" "$CARGO_HOME" "$RUSTUP_HOME"
  '';

  buildPhase = ''
    runHook preBuild
    flutter pub get --offline
    flutter build linux --release --no-pub
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/alice" "$out/bin"
    cp -r build/linux/x64/release/bundle/* "$out/libexec/alice/"
    chmod +x "$out/libexec/alice/alice"

    makeWrapper "$out/libexec/alice/alice" "$out/bin/alice" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Flutter-based Wayland top bar for wlroots compositors";
    license = licenses.unfree;
    platforms = platforms.linux;
    mainProgram = "alice";
  };
}
