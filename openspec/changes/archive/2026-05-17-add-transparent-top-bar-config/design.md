## Context

Alice's configuration is parsed in Rust from `$XDG_CONFIG_HOME/alice/config.yaml`, exposed through flutter_rust_bridge, mapped into a Flutter `AliceConfig`, and then consumed by widgets such as `TopBar`. The current top bar shell always draws a semi-opaque themed surface and a primary/accent-tinted border around the full 44 px bar.

The requested change is a narrow visual option: make only the outer top bar shell transparent while leaving child module styling intact.

## Goals / Non-Goals

**Goals:**

- Add `theme.transparent_top_bar` as an optional boolean config field.
- Preserve existing behavior by defaulting the field to `false` when omitted.
- Carry the typed value from Rust config into Flutter's `AliceConfig`.
- Use the value only for the outer `TopBar` container's background and border.
- Document the option in the default config template.

**Non-Goals:**

- Do not alter workspace chip, pill, metric, tray, notification, power, or media module styling.
- Do not alter panel window styling or panel gap behavior.
- Do not introduce compositor/window-level transparency changes; the app/window background is already transparent.
- Do not rename or restructure existing theme options beyond adding this field.

## Decisions

### Use `theme.transparent_top_bar`

The option belongs under `theme` because it controls visual presentation alongside `mode`, `accent`, and `panel_top_gap_px`. The key uses snake_case with explicit word boundaries: `transparent_top_bar`.

Alternative considered: top-level `transparent_top_bar`. This was rejected because existing visual options are grouped under `theme`, and keeping it there avoids adding a new top-level styling concept.

### Default to current styling

Missing or omitted `transparent_top_bar` values will resolve to `false`. This preserves existing configs and avoids surprising first-run users.

### Scope transparency to the outer shell only

When enabled, `TopBar` should render the outer container with no background fill and no outer accent border. Child widgets continue to render their current backgrounds, borders, highlights, hover/tap states, and text styles.

Conceptually:

```text
transparent_top_bar: false
┌──────────────────────────────────────────────┐
│ surface bg + accent-tinted outer border      │
│ [workspaces]      [media]      [modules]     │
└──────────────────────────────────────────────┘

transparent_top_bar: true
  [workspaces]      [media]      [modules]
```

Implementation should avoid pushing this flag into every child module; the decision belongs at the shell decoration boundary.

### Regenerate bridge bindings after native model change

Because `AliceConfig` is exported through flutter_rust_bridge, adding the Rust field requires regenerating generated bridge files so Dart receives the new typed value.

## Risks / Trade-offs

- **Generated bridge drift** → Regenerate and review the generated config bindings as part of implementation.
- **Accidental child styling changes** → Keep the conditional logic localized to `TopBar`'s outer `BoxDecoration` and cover with a widget test.
- **Existing user configs omit the new field** → Default to `false` in Rust and Flutter fallback config.
- **Ambiguity around border removal** → Specify that only the outer accent-colored border is removed; module/chip borders remain unchanged.
