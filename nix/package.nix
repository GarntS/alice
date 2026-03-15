{ lib
, buildFlutterApplication
, rustPlatform
, clang
, cargo
, rustc
, cargo-expand
, cmake
, ninja
, pkg-config
, wayland-scanner
, flutter_rust_bridge_codegen

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
    zlib
  ];
in
buildFlutterApplication {
  pname = "alicebar";
  version = "1.0.0";

  src = lib.cleanSource ../.;
  pubspecLock = lib.importJSON ./pubspec.lock.json;

  # Cargo integration
  cargoRoot = "native";
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ../native/Cargo.lock;
  };

  nativeBuildInputs = [
    clang
    cargo
    rustc
    cargo-expand
    rustPlatform.cargoSetupHook
    cmake
    ninja
    pkg-config
    wayland-scanner
    flutter_rust_bridge_codegen
  ];

  buildInputs = runtimeLibraries;

  dontUseCmakeConfigure = true;

  preConfigure = ''
    export CC=${clang}/bin/clang
    export CXX=${clang}/bin/clang++
    export CMAKE_C_COMPILER="$CC"
    export CMAKE_CXX_COMPILER="$CXX"
  '';

  postInstall = ''
    wrapProgram "$out/app/alicebar/alicebar" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}"
  '';

  meta = with lib; {
    description = "Flutter-based Wayland top bar for wlroots compositors";
    homepage = "https://github.com/garnts/alicebar";
    license = licenses.gpl3;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
    mainProgram = "alicebar";
  };
}
