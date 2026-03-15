# alice

`alice` is a Flutter-first Wayland bar for `wlroots` compositors, with native Linux integration implemented in Rust.

## Project Design

### Overall Structure
- The bar is logically organized out of the bar itself, **Bar Widgets**, which
are the widgets that can be rendered directly on the bar, and **Panels**, which
are any pop-out windows that are spawned upon clicking a widget.
- The front-end is written in Flutter. This is located in `lib/`.
- The data back-end is written in Rust. This is located in
`native/alice_platform`.
- A small binary that actually runs the application is written in C++. The only
things this binary handles are the command line parsing and startup, and the
linkage for the creation and management of render surfaces.
- There is an additional Rust library that handles the interactions with
`wlr-layer-shell` for capability detection and to help manage surface geometry.
It exposes some functions over C FFI, which the `runner` binary links against.
It's a rather small library, but the goal was to move as much logic out of the
C++ binary as was possible. This is located in `native/alice_layer_shell`.
- The entire data state for the bar is stored in a snapshot object,
`BarSnapshot`, which is periodically-updated by messages sent from the
Rust-based native code to the Flutter code. When Flutter widgets re-render,
they pull data from the snapshot.

#### TL;DR of how windows surfaces are created:
- Rust `alice_layer_shell` provides the placement geometry and capability
detection.
- C++ `runner` applies the layer-shell configuration via `gtk-layer-shell`.
- Flutter simply renders into the resulting window.

### Configuration
Many settings are configurable by a `config.yaml` file, located at
`$XDG_CONFIG_HOME/alice/config.yaml`. On first run, if the file doesn't exist,
a default with comments explaining all the fields will be placed there. 
`config.yaml` allows for things like theming, time zones, and power menu 
commands.

**An abbreviated version of the default `config.yaml`:**
```yaml
theme:
  # One of: system, light, dark
  mode: system

  # Accent color used throughout the bar and panels.
  # Format: #RRGGBB
  accent: "#4C956C"

network:
  # Whether to show the SSID or status label next to the network icon.
  show_label: true

tray:
  # Once this many tray items are visible, the remainder are collapsed into an
  # overflow panel. The bar shows N-1 items and an overflow toggle.
  max_visible_items: 5

clock:
  # Optional label for the local time zone shown in the bar and clock panel.
  # local_time_zone_label: EST

  # Additional time zones shown in the clock panel.
  additional_time_zones:
    # Pick exactly one: offset_hours, tz_name, or tz_abbrev_name.
    # label overrides the default abbreviation shown in the UI.
    - tz_name: UTC
    - tz_name: Australia/Sydney
    # Example using a timezone abbreviation.
    # - tz_abbrev_name: AEST

power:
  # Commands are delegated to the shell and may be customized by the user.
  lock: "loginctl lock-session"
  lock_and_suspend: "loginctl lock-session && systemctl suspend"
  restart: "systemctl reboot"
  poweroff: "systemctl poweroff"
```

### A Quick Note on LLMs
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
| Standard Wayland and X11 dev libs | libwayland, libxkbcommon, libX11, libepoxy, etc. |

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
