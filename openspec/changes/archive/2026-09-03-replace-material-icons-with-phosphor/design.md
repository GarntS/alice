## Context

See proposal.md for motivation. Alice currently passes `IconData` through reusable bar and panel widgets, while Material icon constants are used directly in 18 Flutter source files. `phosphoricons_flutter` v1.0.0 represents regular icons as `IconData`, but represents duotone icons with a distinct data type that must be rendered by `PhosphorIcon`. Configuration originates in Rust, crosses the flutter_rust_bridge `AliceUiConfig` contract, and is mapped into Dart `AliceConfig`.

## Goals / Non-Goals

**Goals:**
- Make one shared renderer responsible for choosing regular versus duotone Phosphor output and applying the secondary-layer color policy.
- Preserve current call-site primary icon color behavior without duplicating configuration logic in every widget.
- Keep Rust, generated bridge bindings, Dart defaults, and the shipped YAML template in default parity.

**Non-Goals:**
- Recolor or replace application-provided tray and notification artwork.
- Add configurable icon weights, secondary opacity, individual icon overrides, or user-configurable gray values.
- Change Alice's Material component theme or its warning, alert, and highlighted-state semantics.

## Decisions

### Use `phosphoricons_flutter` 1.0.0

Add `phosphoricons_flutter: ^1.0.0`. It supports the repository's Dart 3.x SDK and provides both regular `IconData` constants and its required duotone renderer.

The older `phosphor_flutter` package is incompatible with Dart 3 because it subclasses `IconData`; using it would create an avoidable compatibility risk.

### Introduce paired icon descriptors and one Alice-owned renderer

Define an internal icon descriptor that pairs a regular Phosphor constant with its equivalent duotone constant. Define a shared widget that accepts that descriptor and normal icon properties (size, primary color, semantics). It renders Flutter's `Icon` for regular mode and `PhosphorIcon` for duotone mode.

This replaces the existing `IconData` contracts in reusable icon-bearing widgets and weather mapping functions. It confines the package's duotone type difference to the shared rendering layer and allows all source icon mappings to stay semantically paired.

A direct constant-for-constant replacement was rejected because duotone values cannot be passed to `Icon` or stored as `IconData`.

### Resolve secondary duotone color in the shared renderer

The renderer will read `AliceConfig` from the active application context. In duotone mode it will preserve the existing explicit or inherited primary color. When `useAccentOnIcons` is true, it supplies `config.accentColor` as the secondary color. When false, it supplies a fixed gray token selected from the active brightness: `#6B7280` in light mode and `#9CA3AF` in dark mode.

The package default secondary opacity remains unchanged. The user requested a secondary color policy, not opacity configuration; retaining the library default avoids expanding the configuration surface.

Using `ThemeData` alone was rejected because the rendering policy needs the icon configuration values, and the existing `secondary` palette colors are surface-oriented rather than deliberate visible icon-fill tokens.

### Extend configuration end-to-end and regenerate bindings

Add optional booleans to Rust's raw theme config and default both fields to `true` in the typed Rust config. Add them to the secret-free UI config contract, regenerate flutter_rust_bridge bindings, map them into Dart `AliceConfig`, and add them to Dart's fallback config. Document both in the default YAML and README and test omitted/provided/template-default behavior.

Generated Dart and Rust bridge files must be produced by the project code-generation command, not edited by hand.

### Migrate all Alice-owned glyphs and tests

Replace every `Icons.*` use in `lib/`, including weather and fallback glyphs. Retain `material_ui` for Material widgets/theme types, but remove `uses-material-design` only after a repository search confirms no Material glyphs remain. Update widget tests that find Material `IconData` to assert the new renderer or Phosphor glyphs and add coverage for all configuration combinations.

## Risks / Trade-offs

- [Phosphor lacks an exact Material equivalent for a weather or system icon] → Choose the closest semantic Phosphor icon and retain the existing mapping behavior; validate representative weather and fallback states in widget tests.
- [A remaining `IconData` field blocks duotone rendering] → Migrate all shared icon contracts before converting call sites; search for `Icons.` and `IconData` references as completion checks.
- [Bridge bindings drift from Rust config fields] → Regenerate bindings and cover config mapping plus default-template parity in tests.
- [Icon layer color becomes unreadable in an existing highlighted or alert surface] → Preserve call-site primary colors and test representative contrasting, warning, and alert contexts.

## Migration Plan

1. Add the dependency and configuration contract with defaults and documentation.
2. Generate bridge bindings, add the shared descriptor/renderer, and migrate all Alice-owned icon call sites.
3. Update and add Rust/Dart/widget tests, then verify there are no remaining Material icon glyph references.
4. On rollback, restore the prior dependency/config bridge and Material icon call sites; existing user config files remain parseable because the new keys are optional.
