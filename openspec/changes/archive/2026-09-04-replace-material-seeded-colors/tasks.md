## 1. Define the explicit palette

- [x] 1.1 Add an immutable, brightness-specific Alice color-token model with exact accent, opaque surface-blended accent variants, neutral tokens, error, and warning.
- [x] 1.2 Implement exact-accent foreground selection and the defined 14%, 20%, and 28% surface-blend token calculations.
- [x] 1.3 Build complete explicit light and dark `ColorScheme` projections and `ThemeData` without `ColorScheme.fromSeed`.
- [x] 1.4 Expose Alice-specific tokens to Alice-owned widgets while retaining existing Material theme access.

## 2. Apply palette roles

- [x] 2.1 Audit Alice widget uses of `ColorScheme` roles and local primary/secondary opacity; map accent fills, subtle backgrounds, borders, and interactive states to the explicit tokens.
- [x] 2.2 Preserve exact configured accent weather-card fills and the existing duotone icon secondary-layer configuration behavior.
- [x] 2.3 Apply fixed neutral raised-container, error, and warning tokens to their current visual consumers.

## 3. Verify color behavior

- [x] 3.1 Add unit coverage for exact primary accent, light/dark opaque blend values, black-or-white accent foreground, and fixed neutral/semantic tokens.
- [x] 3.2 Add widget coverage for primary and neutral Material container mappings plus focus, hover, and pressed Alice control states.
- [x] 3.3 Add regression coverage that enabled and disabled duotone icon secondary-layer policies remain unchanged.
- [x] 3.4 Run the relevant Dart/Flutter test suites and OpenSpec strict validation.
