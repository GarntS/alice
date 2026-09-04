## Why

Alice currently seeds Flutter's Material 3 color system from the configured accent, causing Material You tonal variations of that accent to appear throughout the interface. Users need the configured accent to remain exact while Alice controls the small, intentional set of accent tints and neutral surfaces used by its UI.

## What Changes

- Replace `ColorScheme.fromSeed` theming with an explicit Alice color-token palette for light and dark themes.
- Keep the configured accent byte-for-byte as the primary color and as the existing accent-filled weather-card background.
- Precompute a small set of opaque accent background, border, and interactive-state tokens by blending the configured accent into the active surface.
- Map Alice's explicit palette deliberately into Flutter `ColorScheme` and retain `ThemeData`/Material widget compatibility.
- Keep fixed neutral surface/container roles and fixed error and warning semantic colors rather than deriving them from the accent.
- Preserve the existing exact-accent duotone icon secondary-layer policy.

## Capabilities

### New Capabilities
- `explicit-color-system`: Define Alice-owned light and dark color tokens, accent-variant derivation, and their projection into Material theme roles.

### Modified Capabilities
- `theme-system`: Replace the seeded Material 3 color-scheme requirement with explicit Alice palette and Material role behavior.

## Impact

- Affected Dart theming code: `lib/alice_theme.dart`, widget color-role consumers, and theme test helpers/tests.
- Affected configuration behavior: `theme.accent` remains a single `#RRGGBB` input; no new user configuration is required.
- Flutter Material `ColorScheme` and `ThemeData` remain in use; no dependency change is expected.
