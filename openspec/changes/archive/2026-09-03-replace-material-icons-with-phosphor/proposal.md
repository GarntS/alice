## Why

Alice’s interface currently mixes Material Symbols into an otherwise custom visual system. Phosphor Icons provide a consistent icon family and duotone treatment, while user preferences should control whether that treatment and accent-tinted secondary layers are used.

## What Changes

- Replace Alice-owned Material icon glyphs throughout the bar, panels, weather UI, and fallback states with icons from `phosphoricons_flutter`.
- Add `theme.use_duotone_icons` (default `true`) to select Phosphor duotone icons or regular icons.
- Add `theme.use_accent_on_icons` (default `true`) to select an accent-colored duotone secondary layer; when disabled, use fixed theme-aware gray secondary colors.
- Preserve contextual primary icon colors, including existing foreground, warning, alert, and highlighted-state colors.
- Keep externally supplied tray and notification application artwork unchanged.
- Replace Material-icon-specific test expectations and remove the Material icon font dependency if no Material glyphs remain.

## Capabilities

### New Capabilities
- `phosphor-icon-system`: Alice-owned interface icons render as configurable Phosphor regular or duotone icons with consistent primary and secondary color behavior.

### Modified Capabilities
- `configuration`: Add typed, defaulted theme preferences for duotone icon selection and duotone secondary coloring.
- `theme-system`: Define the fixed light- and dark-theme gray tokens used by non-accented duotone icon secondary layers.
- `weather-forecast`: Render weather and wind-direction icon mappings using Phosphor icons rather than Material icons.

## Impact

- Flutter UI icon rendering, reusable icon-bearing widgets, weather icon mapping, and rendering tests.
- Rust configuration parsing/defaults, Flutter Rust Bridge UI config contract and generated bindings, Dart configuration mapping and fallback defaults.
- `pubspec.yaml`/lockfile dependency graph, shipped default configuration template, README configuration documentation, and OpenSpec requirements.
