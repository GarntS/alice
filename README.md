# alice

`alice` is a wayland bar for `wlroots` compositors, with a collection of 
expanding sub-panels associated with some widgets. Native Linux integration for
data-collection and system interaction with the filesystem, devices, and D-Bus 
is all implemented in Rust for safety and portability. `alice` is configurable 
for theming and data sources, but its design is deliberately opinionated 
according to my tastes and is not highly configurable in a similar manner to
other wayland bar projects.

### Etymology
The project name "alice" is named after a *fantastic* cocktail bar in 
Cheongdam-dong, Seoul, South Korea called "Alice Cheongdam". I needed a name
for a bar, and the name "alice" is an homage. If you're ever in Seoul, you
should visit.

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
`BarSnapshot`, which is updated by messages sent from the Rust-based native
code to the Flutter code. These messages are either sent periodically, for data
that doesn't have clear events, like memory usage or the system time, or when
relevant messages come in for event-based data like D-Bus messages. This design 
allows all the Flutter widgets to be a pure function of the data snapshot,
which significantly reduces the level of complexity in the widgets themselves.

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

  # Whether the outer top bar shell should omit its background and border.
  transparent_top_bar: false

  # Gap in pixels between the bottom of the bar and the top of panel windows.
  # Default: 8
  panel_top_gap_px: 8

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

### Google Calendar

The clock panel can display your Google Calendar events for any selected day. This is opt-in and requires a Google Cloud OAuth 2.0 credential.

**1. Create a Google Cloud credential**

- Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a project (or select an existing one).
- Enable the **Google Calendar API** for the project: *APIs & Services → Enable APIs & Services → search "Google Calendar API" → Enable*.
- Create an OAuth 2.0 credential: *APIs & Services → Credentials → Create Credentials → OAuth client ID*.
  - Application type: **TVs and Limited Input Devices** — this is the correct type for the device authorization grant (RFC 8628) that Alice uses. "Desktop app" and "Web application" types use a different OAuth flow and will produce an `invalid_client: Invalid client type` error.
  - Copy the **Client ID** and **Client Secret**.

**2. Add the credential to `config.yaml`**

Add the following section to `$XDG_CONFIG_HOME/alice/config.yaml`:

```yaml
calendar:
  google_client_id: "YOUR_CLIENT_ID.apps.googleusercontent.com"
  google_client_secret: "YOUR_CLIENT_SECRET"
```

**3. Authorise on first run**

The first time you open the clock panel after adding credentials, an authorisation card will appear in place of the events list. It shows:

- A URL — open it in any browser (it's the standard `accounts.google.com/device` flow).
- A short code — enter it when prompted.

After you approve access in the browser, close and reopen the clock panel. Events for the selected day will appear. The token is cached at `$XDG_CONFIG_HOME/alice/calendar_token.json` and refreshed automatically, so you only need to do this once.

**Permissions**

Alice requests the `calendar.readonly` scope — read-only access to your calendar events. No data leaves your machine except for the OAuth token exchange with Google's servers.

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

## Acquiring + Running `alice`
Install `alice` using one of the methods below (the package will be called
`alicebar`), then run the `alicebar` binary.

### Pre-build Packages
Pre-built packages are provided in [Github Releases](https://github.com/GarntS/alice/releases/latest) for:
- Debian 13 (trixie)
- Debian Unstable (sid)
- Ubuntu 24.04 LTS
- Ubuntu 25.10
- Fedora 42
- Fedora 43
- Fedora Rawhide
- Arch Linux

At present, `alice` isn't in any package managers.

### Nix Flake
If you're on `nix`, this repo is also set up as a Nix flake. It can be installed
by adding this repo as an input to your system's `flake.nix`, then passing it to
your configuration via `specialArgs`:
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  alice-git.url = "github:garnts/alice";
};

outputs = inputs@{ self, nixpkgs, alice-git, ... }: {
  nixosConfigurations.your-system = nixpkgs.lib.nixosSystem {
    system = "your-system-string";
    specialArgs = {
     	alice-git = alice-git;
      };
      modules = [
        ./configuration.nix
      ];
    };
  };
}
```

Then, add the package to your `configuration.nix`:
```nix
{ config, lib, pkgs, alice-git, ... }:
{
  environment.systemPackages = [
    # replace "x86_64-linux" with your system string if not on x86_64
    alice-git.packages.x86_64-linux.default
  ];
}
```

## Building `alice`

### Build Dependencies
t
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

### Building without Nix

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

### Building with Nix

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
