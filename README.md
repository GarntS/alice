# alice

`alice` is a Flutter-first Wayland bar for `wlroots` compositors, with native Linux integration implemented in Rust.

## Project Design

#### Overall Structure
- The front-end is written in Flutter.
- The surfaces/windows which Flutter renders to are created and managed using
the `wlroots` Layer-Shell protocol.

#### A Quick Note on LLMs
The extreme majority of this project was built using a combination of 
locally-hosted and frontier lab coding agents as a project to build something
useful for myself while learning about how to use the tools effectively.

I don't like LLMs. As a class, I think they represent more of a potential threat
to society than they do a benefit. However, as a tool, they exist, and provide
a clear advantage in the speed at which developers can build out projects,
assuming the developer understands how to use them as a tool. That means I have
to learn to use them to remain competitive. And, as it turns out, they're quite
good at writing code, if they're given sufficient guidance and project design 
instructions. I hate it here.

With that said, I think that anyone who vomits LLM-generated code on the 
internet has a responsibility to own that code themselves, so this codebase was
carefully designed and refactored multiple times until it was in a state that
I would have actually liked had I built it myself. I've read and re-read every
file in this codebase.

## Build dependencies

| Dependency | Notes |
|---|---|
| Flutter SDK ≥ 3.x | Includes Dart SDK |
| Rust toolchain | `cargo`, `rustc` |
| `flutter_rust_bridge_codegen` 2.11.1 | `cargo install flutter_rust_bridge_codegen@2.11.1` |
| Clang / clang++ | C++ compiler for the GTK runner |
| CMake ≥ 3.13 | |
| Ninja | |
| pkg-config | |
| wayland-scanner | |
| GTK 3 dev headers | `libgtk-3-dev` / `gtk3-devel` |
| gtk-layer-shell dev headers | `libgtk-layer-shell-dev` / `gtk-layer-shell-devel` |
| Standard Wayland dev libs | libwayland, libxkbcommon, libepoxy, etc. |

## Building without Nix

Install the dependencies above for your distribution, then:

```bash
# Get Dart/Flutter packages
flutter pub get

# Build the release binary
# CMake will automatically run flutter_rust_bridge_codegen and cargo
flutter build linux --release
```

The built bundle is at `build/linux/x64/release/bundle/alice`.

If CMake has cached a stale compiler path from a previous build, clear the build directory first:

```bash
flutter clean
flutter build linux --release
```

## Building with Nix

The repo provides a Nix flake with a devShell that includes the full toolchain — Flutter, Dart, Rust, Clang, CMake, Ninja, pkg-config, wayland-scanner, `flutter_rust_bridge_codegen`, and all required libraries.

Enter the dev shell:

```bash
nix develop
```

Then build as normal:

```bash
flutter build linux --release
```

Other useful commands inside the shell:

```bash
flutter analyze
flutter clean
cargo test --manifest-path native/Cargo.toml
```

You can also run individual commands without entering the shell interactively:

```bash
nix develop --command flutter build linux --release
```

To build a Nix package directly:

```bash
nix build .#alice
./result/bin/alice
```
