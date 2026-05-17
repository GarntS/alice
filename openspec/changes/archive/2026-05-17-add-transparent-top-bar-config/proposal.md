## Why

Users may want Alice's top bar to visually blend into their wallpaper or compositor styling while keeping the existing modules and pills readable. The current top bar always draws a semi-opaque surface and accent-colored outer border, so this look is not configurable.

## What Changes

- Add a `theme.transparent_top_bar` boolean configuration option.
- Default the option to `false` to preserve the current top bar appearance.
- When enabled, render the outer top bar shell without its background fill and without its accent-colored outer border.
- Preserve all child module styling, including pills, workspace chips, highlights, and panel styling.
- Document the option in the shipped default `config.yaml` template and README/config documentation where applicable.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `configuration`: Add typed support for `theme.transparent_top_bar` with safe default behavior.
- `bar-shell-layout`: Make top bar shell surface styling conditional on the transparent top bar configuration.

## Impact

- Native configuration parsing and defaults in `native/alice_platform/src/config.rs`.
- flutter_rust_bridge generated configuration bindings.
- Flutter configuration mapping in `lib/alice_config.dart` and `lib/alice_platform.dart`.
- Top bar shell decoration in `lib/widgets/top_bar.dart`.
- Shipped default config template at `assets/config/default_config.yaml` and user-facing docs/tests.
