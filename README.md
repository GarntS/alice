# alice

`alice` is a Flutter-first Wayland bar for `wlroots` compositors, with native Linux integration implemented in Rust.

## NixOS Dev Shell

This repo includes `shell.nix` for local development on NixOS.

Enter the shell with:

```bash
nix-shell
```

Inside the shell, the Flutter Linux toolchain has the compiler, linker, GTK, Wayland, and `pkg-config` inputs it expects.

Common commands:

```bash
flutter analyze
cargo test --manifest-path native/Cargo.toml
flutter build linux --debug
```

If Flutter has previously created a Linux build directory outside the Nix shell, CMake may cache the wrong compiler path. Clear it once before rebuilding:

```bash
rm -rf build/linux
flutter build linux --debug
```

The shell also redirects caches into the repo so development does not depend on writable global home-directory state.

## Nix Package

You can build `alice` as a Nix package:

```bash
# legacy Nix workflow
nix-build

# flake workflow
nix build .#alice
```

Run it directly from the result symlink:

```bash
./result/bin/alice
```
