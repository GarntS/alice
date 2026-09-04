## Context

See `proposal.md` for motivation. `lib/alice_theme.dart` currently calls `ColorScheme.fromSeed` and overrides only a small number of generated roles. Alice widgets consume `ColorScheme` roles broadly, and Phosphor duotone icons separately use the configured accent or an existing fixed gray policy.

## Goals / Non-Goals

**Goals:**
- Make Alice's palette intentional, stable, and independent of Material 3 tonal-palette generation.
- Preserve `ThemeData` and `ColorScheme` for stock Material widget integration.
- Ensure the configured accent is exact for `primary` and accent-filled weather cards.
- Provide reusable, brightness-specific tokens for the limited accent tints and interaction states Alice needs.

**Non-Goals:**
- Add additional color fields to user configuration.
- Change the configured Phosphor duotone icon secondary-layer policy.
- Introduce success or info semantic tokens in this change.
- Replace Material widgets or remove Material theming.

## Decisions

### Alice tokens are canonical; ColorScheme is a projection
Create an Alice-owned immutable theme-token model for each brightness and make it available to Alice widgets through the app theme. Build an explicit `ColorScheme` from those tokens for Material widgets.

This prevents overloaded Material names from becoming Alice's only design vocabulary while retaining Material defaults and component theming. A ColorScheme-only palette was rejected because it cannot express Alice-specific intent such as distinct accent-border and accent-hover tokens clearly.

### The exact accent is shared by both brightnesses
`theme.accent` remains the exact `primary` color for light and dark schemes. `onPrimary` and other accent-fill foregrounds are selected as black or white using contrast/brightness evaluation.

Mode-adjusting the primary was rejected because it violates the user's expectation that the configured color is what Alice displays. Rejecting colors or adding a foreground configuration value was rejected to retain the current single-value configuration.

### Accent variants use fixed opaque surface blends
For each brightness, derive tokens once at theme construction by compositing the exact accent over the corresponding surface:

| Token | Accent contribution | Intended use |
|---|---:|---|
| `accentSubtle` | 14% | selected/background tint; `primaryContainer` |
| `accentHover` | 20% | hover state |
| `accentBorder` | 28% | accent-related border |
| `accentPressed` | 28% | pressed state |
| `accentFocus` | 100% | focus indicator |

The resulting colors are opaque and stable, rather than using translucent widget-local accent colors whose final appearance depends on an arbitrary ancestor background. HSL and OKLCH transformations were rejected because surface blending directly expresses the desired background relationship and has predictable behavior in both brightnesses.

### Map Material roles deliberately
Map `primary` to the exact accent and `primaryContainer` to `accentSubtle`. Map `secondaryContainer` to the neutral raised-container token. Supply every Material color role used by Alice or stock widgets from a defined token, with neutral aliases where a distinct visual role is unnecessary. Keep surfaces, text, outlines, and secondary colors neutral; keep error and warning as fixed semantic colors independent of accent.

Material defaults were rejected because they could reintroduce library-generated colors. Mapping both container families to accent variants was rejected because it makes quiet raised content compete with selected/active content.

### Preserve duotone icon behavior
Leave `use_accent_on_icons` unchanged: enabled duotone icons use the exact configured accent for their secondary layer; disabled icons use the existing brightness-aware gray tokens. This behavior is already specified and does not depend on seeded colors.

## Risks / Trade-offs

- [A user selects an accent that has poor visibility on one theme surface] → choose black or white contrast foreground for exact-accent fills; verify representative light, dark, very light, and very dark accents.
- [A stock Material widget reads a role Alice has not deliberately mapped] → construct and test the complete scheme, and add explicit aliases for every role used by Alice or common stock controls.
- [Existing widget-local opacity produces double-tinting] → audit consumers of `primary`, `secondary`, and container roles; replace accent-tint usages with named Alice tokens where needed.
- [Fixed blend percentages feel too weak or strong] → centralize the values as theme constants and adjust them as a single visual-system decision after screenshots/widget coverage.

## Migration Plan

1. Add the token model and explicit light/dark palette construction beside the existing theme builder.
2. Replace the seeded scheme with the explicit `ColorScheme` projection and expose Alice tokens to widgets.
3. Update Alice widgets that currently use derived scheme roles or local opacity to use the corresponding token/role.
4. Add theme and widget coverage for exact accents, surface-blended variants, fixed semantic colors, interaction states, and existing duotone behavior.
5. Roll back by restoring the previous seeded theme builder; configuration files remain compatible because no schema changes are made.
