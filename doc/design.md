# Design Doc

`alice` is a Wayland top bar for `wlroots` compositors. The UX layer is written in Flutter; native Linux integration is implemented in Rust; layer-shell window management is handled by a small C++/GTK runner.

## Configuration

All configuration is handled through a single `.yaml` file at `$XDG_CONFIG_HOME/alice/config.yaml`. On first run, if no config file exists, a default file with comments documenting every valid option is written to that path.

Supported options:

| Key | Type | Description |
|---|---|---|
| `theme` | `light` / `dark` / `system` | Bar colour scheme |
| `accent_color` | hex string | Material3 colour seed |
| `show_network_label` | bool | Show SSID / "Connected" label next to network icon |
| `max_visible_tray_items` | int | Tray icons shown before overflow |
| `time_zones` | list | Extra world-clock entries (label + UTC offset) |
| `power_commands.lock` | string | Shell command for lock action |
| `power_commands.lock_suspend` | string | Shell command for lock + suspend |
| `power_commands.restart` | string | Shell command for restart |
| `power_commands.poweroff` | string | Shell command for power off |

## Constraints

- The UX is written 100% in Flutter.
- Native Linux access (D-Bus, Sway IPC, `/proc`, network inspection, file watching) is implemented in Rust and exposed to Flutter via `flutter_rust_bridge`.
- Layer-shell window creation and positioning is handled by a C++/GTK runner.
- The bar supports a light theme, a dark theme, and a user-configurable accent colour.
- Only one panel may be open at a time.

## Layout

The bar is anchored to the top of the output at 44 px tall, split into three layout groups.

**Left:**
1. Workspace indicator — shows all Sway workspaces on the current output. The focused workspace is highlighted in the accent colour; visible-but-unfocused workspaces use a secondary colour; hidden workspaces are rendered in a muted style. Clicking a workspace chip focuses it via Sway IPC.

**Centre:**
1. Media now-playing display — shown only when an MPRIS player is active. Displays a play/pause icon and a formatted label (`Title - Artist - 0:26/2:10`). Clicking opens the media panel.

**Right (left to right):**
1. Memory usage — icon and percentage of system RAM in use. Colours shift to yellow above 75 % and red above 90 %.
2. CPU usage — icon and aggregate CPU load expressed as cores (e.g. `2.4` for four cores each at 60 %). Same warning/alert colour thresholds as memory.
3. Network status — icon and optional label. Shows Wi-Fi SSID when on wireless, "Connected" on wired, or "Disconnected" with a broken-link icon when offline. Label visibility is configurable.
4. Clock — timezone code, day-and-month date, and 24-hour time. Clicking opens the world-clock panel.
5. Tray — `StatusNotifierItem`-compatible icons, limited to a configurable count. When items overflow, a badge showing the count opens an overflow panel.
6. Power button — opens the power panel.

## Panels

Panels are floating GTK surfaces managed by the C++ runner via layer-shell. Only one panel can be open at a time; opening a new one closes any currently open panel.

| Panel | Content |
|---|---|
| Media | Album art, title, artist, album, position/length scrubber, previous/play-pause/next controls |
| World clock | Highlighted local time plus a row per configured extra timezone |
| Tray overflow | Scrollable list of tray items beyond the visible count |
| Power | Lock, Lock + Suspend, Restart, Power Off |

## Architecture

### Runtime model

A single binary is started twice by the runner: once with `--alice-window=bar` for the main bar surface, and once with `--alice-window=panel` for the floating panel surface. Both processes share a Rust library that is statically linked into the GTK runner.

### Data flow

The Rust runtime runs a Tokio async event loop with the following providers:

| Provider | Source | Update trigger |
|---|---|---|
| Workspaces | Sway IPC subscription | IPC workspace event |
| Media | D-Bus MPRIS | MPRIS property change |
| Memory | `/proc/meminfo` | 1 s timer |
| CPU | `/proc/stat` | 1 s timer |
| Network | `/sys/class/net` | `notify` file watcher |
| Clock | `chrono` | 30 s timer |
| Tray | D-Bus SNI watcher | SNI registration / icon change |

All providers write into a shared `BarSnapshot` struct. A 50 ms debounce is applied before each snapshot is sent to Flutter over a `flutter_rust_bridge` stream, collapsing bursts of concurrent updates into a single widget rebuild.

### Platform bridge

`AlicePlatform` in Dart wraps two transport layers:

- **`flutter_rust_bridge` stream/function calls** — `watchBarSnapshots`, `loadConfig`, `sendMediaAction`, `focusWorkspace`, `sendTrayAction`, `executePowerAction`
- **`MethodChannel`** — `showPanel` / `hidePanel` for instructing the C++ runner to create or destroy the floating panel surface

### Tray integration

The Rust `tray` module hosts a `StatusNotifierWatcher` D-Bus service that accepts registrations from both the `org.kde.StatusNotifierItem` and `org.freedesktop.StatusNotifierItem` interfaces. For each registered item it fetches a 16×16 PNG icon and forwards it to Flutter as raw bytes. Tray item activation, secondary activation, and context-menu calls are routed back to the registrant via D-Bus.

## Agreed decisions

- Target compositor scope is `wlroots` compositors, with Sway as the first validation environment.
- The UX layer is Flutter; native Linux integrations are Rust.
- Workspace state uses Sway IPC, behind a thin abstraction so other compositor backends can be added later.
- Tray support targets `StatusNotifierItem` over D-Bus.
- Configuration is a hand-authored YAML template with comments, parsed into typed Rust structs via `serde`.
- Only one panel may be open at a time.
- Power actions delegate to configurable shell commands with `systemctl` defaults.

## Implementation status

All major milestones are complete.

| Component | Status |
|---|---|
| Configuration (load, first-run generation, typed structs) | Done |
| Bar shell and three-column layout | Done |
| Layer-shell integration (bar + floating panels) | Done |
| Theming (light, dark, system, accent colour) | Done |
| Workspace indicator (Sway IPC) | Done |
| Clock widget and world-clock panel | Done |
| Memory and CPU widgets | Done |
| Network status widget | Done |
| MPRIS media widget and media panel | Done |
| StatusNotifier tray and overflow panel | Done |
| Power menu panel | Done |
| Single-panel-at-a-time panel controller | Done |
| flutter_rust_bridge codegen wired into CMake build | Done |
| Nix flake devShell and package | Done |
