## Why

StatusNotifier registration and watcher reads independently parse the same three identifier forms into different representations. Parsing once into `StatusNotifierItemRef` and formatting its canonical ID from that value removes duplicate protocol grammar and edge-case drift.

## What Changes

- Define one parser for service-only, service-plus-object-path, and sender-relative object-path identifiers.
- Make registration canonicalization and watcher item reads use the same parsed `StatusNotifierItemRef`.
- Derive the canonical watcher ID string from the parsed semantic value.
- Replace overlapping parser tests with a table that proves both call paths agree for valid and invalid forms.
- Preserve both KDE and freedesktop watcher interfaces and all D-Bus payload behavior.

## Capabilities

### New Capabilities

### Modified Capabilities
- `status-notifier-tray`: Require registration and watcher reads to share one identifier interpretation while preserving canonical IDs and accepted forms.

## Impact

- Affected implementation and tests: `native/alice_platform/src/tray.rs`.
- Public behavior: watcher bus names, interfaces, properties, signals, canonical strings, item ordering, default object path, snapshots, and actions remain unchanged.
- Explicit non-goal: adding item-unregistration/name-owner lifecycle handling.
- Dependencies, FRB types, and generated files: unchanged.
