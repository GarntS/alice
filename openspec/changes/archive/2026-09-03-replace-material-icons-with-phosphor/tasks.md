## 1. Dependency and configuration contract

- [x] 1.1 Add `phosphoricons_flutter` and update the lockfile; retain Material UI dependencies needed for widgets and theming.
- [x] 1.2 Add defaulted `use_duotone_icons` and `use_accent_on_icons` fields to Rust raw and typed theme configuration, and cover omitted/provided/default-template parity cases with Rust tests.
- [x] 1.3 Expose both icon preferences through `AliceUiConfig`, regenerate flutter_rust_bridge bindings, and map them into Dart `AliceConfig` and its fallback default.
- [x] 1.4 Document both theme keys and their `true` defaults in `assets/config/default_config.yaml` and the README configuration example.

## 2. Shared icon presentation

- [x] 2.1 Add the paired regular/duotone Phosphor icon descriptor and shared renderer that selects the configured style.
- [x] 2.2 Implement the shared renderer's secondary-layer policy: configured accent when enabled; fixed `#6B7280` light-theme or `#9CA3AF` dark-theme gray when disabled; preserve the contextual primary color.
- [x] 2.3 Migrate reusable icon-bearing widget contracts from `IconData`/`Icon` to the shared descriptor/renderer without changing existing size, semantics, or contextual colors.
- [x] 2.4 Add widget coverage for regular mode, accent duotone mode, gray duotone mode in both brightnesses, and semantic primary-color preservation.

## 3. Icon migration

- [x] 3.1 Replace all Alice-owned Material glyphs in bar modules, panels, and fallback states with semantically equivalent paired Phosphor descriptors.
- [x] 3.2 Replace weather condition, moon-phase, humidity, and wind-direction mappings with paired Phosphor descriptors while preserving all existing mapping and bearing behavior.
- [x] 3.3 Preserve application-supplied tray and notification artwork and route only their Alice-owned fallback glyphs through the shared renderer.
- [x] 3.4 Update icon-specific widget and mapping tests to assert Phosphor rendering and the preserved weather semantics.

## 4. Verification and cleanup

- [x] 4.1 Search `lib/` for remaining `Icons.` material glyph references and remove `uses-material-design` only when none remain.
- [x] 4.2 Run Rust configuration tests, Flutter formatting/analyzer/tests, and OpenSpec strict validation for this change.
