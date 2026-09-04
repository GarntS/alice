## Purpose

Define Alice's intentional, predictable color tokens without Material 3-generated accent tonal palettes.

## ADDED Requirements

### Requirement: Exact configured primary accent
Alice SHALL use the configured theme accent color unchanged as the primary accent in both light and dark themes.

#### Scenario: Theme with a valid configured accent
- **WHEN** Alice builds either theme from a valid `theme.accent` value
- **THEN** the theme primary accent SHALL equal the configured `#RRGGBB` color exactly
- **AND** accent-filled weather forecast cards SHALL use that exact color

### Requirement: Explicit accent variants
Alice SHALL expose opaque, precomputed accent-subtle, accent-border, accent-hover, and accent-pressed tokens for each theme brightness.

#### Scenario: Accent variants are built
- **WHEN** Alice builds a light or dark theme
- **THEN** it SHALL derive the accent variants by blending the exact configured accent into that theme's surface color
- **AND** it SHALL use accent blend strengths of 14 percent for subtle, 28 percent for border, 20 percent for hover, and 28 percent for pressed

### Requirement: Fixed neutral and semantic colors
Alice SHALL provide brightness-specific neutral surfaces and text colors, neutral raised-container colors, and fixed error and warning colors that are independent of the configured accent.

#### Scenario: Configured accent changes
- **WHEN** the configured accent changes
- **THEN** Alice's neutral surface, text, raised-container, error, and warning colors SHALL retain their defined values for the active brightness

### Requirement: Explicit interactive-state colors
Alice SHALL provide explicit focus, hover, and pressed visual-state tokens rather than deriving interactive-state colors from a Material seeded palette.

#### Scenario: Accent-bearing control changes state
- **WHEN** an accent-bearing Alice control is focused, hovered, or pressed
- **THEN** it SHALL use Alice's explicit focus, hover, or pressed token for that state
