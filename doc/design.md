# Design Doc

This project will implement a top bar and a few expanding widgets for a wayland desktop.

## Configuration
All configuration for the bar should be accomplished through a single `.yaml` file, stored in `$XDG_CONFIG_HOME/alice/config.yaml`. On run, if a config file does not exist at that path, a default configuration file, with comments representing all of the valid configuration values, should be placed at that path.

## Constraints
- The UX for the application should be written 100% in Flutter.
- If native code is necessary to provide data to the flutter code for things like memory usage, D-Bus access for MPRIS, Wi-Fi info, etc. That's fine. Native components *DO NOT* need to be written in Dart, and can instead be in Rust if that's easier.
- The bar should have a light theme, a dark theme, and an accent color, all of which are user-configurable via the `config.yaml`.
- Because we're implementing a bar for a wayland desktop, it'll need to integrate with the wlr layer-shell protocol. You'll need to write a Flutter plugin with some native code that hooks into the WLR layer shell protocol, providing it space to render the bar and a mechanism to render the panels over other windows. This will be a major lift.
- Some of the widgets mentioned in the layout below mention "panels", which should expand from the bar and float over other windows without resizing them.

## Layout
The top-bar should always have the following layout, displayed in 3 groups:
**Floating on the left side (in LTR order):**
1. An indicator of what `swaywm` desktops are available on the current monitor. The current workspace for each monitor should be visible and distinct from the other numbers.

**Floating Center:**
1. A playing media display.
  - If media is playing (as published on D-Bus's MPRIS), a track title, artist, current media time, and media length.
    - E.G. - "I Get Off - Halestorm - 0:26/2:10".
  - If media is playing, on click, this should expand a panel that has all of the above information, and play/pause, previous track, and next track buttons, laid out how it would be in a media player.
  - If media is not playing (via MPRIS), nothing.

**Floating Right (in LTR order):**
1. A memory usage indicator.
  - This should show a memory icon, and a percentage representing the amount of system memory currently in-use.
  - When memory usage is close to 100%, this should change to be a bright and distracting color, like yellow or red.
2. A CPU usage indicator.
  - This should show a processor icon, and a number representing the number of cores of processing power currently in-use, as a sum of the percentage usages of each core. e.g. - 4 cores, all 60% usage, 2.4.
  - When CPU usage is high (over 60%), this should change to be a bright and distracting color, like yellow or red.
3. A status indicator showing the status of the network connection.
  - If connected to WiFi, it should show a wireless icon and the SSID of the current network.
  - If disconnected from WiFi, or if the device has no WiFi, but if the device has a wired network connection, show a plug icon and a label that says "Connected".
  - If no network devices are connected, show a disconnected icon and a label that says "Disconnected".
  - It should be user-configurable via the config file whether the labels and network names are shown.
4. A clock, showing a timezone short code (EST, AEST, GMT, etc.), a day and month, and the 24-hour time.
  - On click, it should expand a panel to display a vertical list of different times in any number of additional time zones, as configured by the user in the configuration file.
5. A `libappindicator`-compatible tray that shows icons for each running application that has published an application indicator.
  - Once a configurable number of application indicators are being shown, it should hide all but N-1 icons, and show a carat that can be used to expand a panel that shows all the remaining application indicators, in much the same style as Windows's taskbar does.
6. A power icon, which, when clicked, displays a power menu. The power menu should have 4 options: lock, lock + suspend, restart, and poweroff.

## Agreed Decisions
- Target compositor scope is `wlroots` compositors generally, with `sway` used as the first validation environment.
- The UX layer will be written in Flutter, while native Linux integrations will be implemented in Rust.
- Workspace state will use `sway` IPC for the first implementation, but the UI-facing integration should be abstracted so additional compositor backends can be added later.
- Tray support will target `StatusNotifierItem` behavior over D-Bus.
- Configuration will use a hand-authored default `config.yaml` template with comments, plus typed parsing and validation in code.
- Only one panel may be open at a time.
- Power actions will delegate to configurable shell commands with sane defaults.
- Initial delivery is for local development and validation only; packaging is out of scope for the first implementation.

## Implementation Plan
1. Define the platform boundary.
   - Flutter owns rendering, layout, theme application, panel state, and widget composition.
   - Rust owns `wlr-layer-shell` integration, D-Bus access, `sway` IPC, system stats, network inspection, and StatusNotifier hosting.
   - Native functionality should be exposed to Flutter through a small, explicit plugin/channel API.
2. Scaffold the project structure.
   - Create the Flutter app shell for the bar UI.
   - Create Linux native/plugin crates for layer-shell integration, panel window creation and positioning, and native data providers.
   - Define a shared event model for pushing native state updates into Flutter.
3. Implement configuration first.
   - Load `~/.config/alice/config.yaml` using XDG conventions.
   - On first run, write a hand-authored commented config template if the file does not exist.
   - Parse configuration into typed structures with validation and fallback behavior for invalid values.
4. Build the core bar shell.
   - Create the top bar as a layer-shell surface anchored to the top of the output.
   - Implement the three layout groups: left, center, and right.
   - Add configurable light theme, dark theme, and accent color support.
   - Ensure the bar is monitor-aware and behaves correctly on `wlroots` compositors.
5. Implement widget data sources.
   - Left: workspace indicator backed by `sway` IPC.
   - Center: MPRIS now-playing state and click-to-open media panel.
   - Right: memory usage, CPU usage, network status, clock with configured extra time zones, StatusNotifier tray, and power menu trigger.
6. Implement single-panel behavior.
   - Create a shared panel controller so opening one panel closes any other open panel.
   - Back each panel with a native floating surface positioned relative to the bar so it renders over other windows without resizing them.
   - Implement the media controls panel, timezone list panel, tray overflow panel, and power menu panel.
7. Implement StatusNotifier support.
   - Host the necessary StatusNotifier watcher and item integration over D-Bus from Rust.
   - Forward icon, tooltip, and action events into Flutter for rendering and interaction.
   - Add overflow behavior based on a configurable visible-item threshold.
8. Add resilience and polish.
   - Validate and clamp unsupported or invalid config values.
   - Provide sensible fallback behavior when services are unavailable, such as no MPRIS clients, no wireless device, or no tray items.
   - Ensure power actions use configurable commands with documented defaults.
9. Validate in a real session.
   - Test on `sway` first.
   - Verify anchoring, z-order, focus behavior, multi-monitor handling, D-Bus updates, tray activation, and first-run config generation.

## Milestones
1. Configuration, bar shell, and theming.
2. Layer-shell integration for the bar and floating panels.
3. Workspace, clock, CPU, and memory widgets.
4. MPRIS integration and the media panel.
5. Network status widget.
6. StatusNotifier tray and overflow panel.
7. Power menu, validation, and polish.
