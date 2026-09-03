## Context

See `proposal.md` for motivation and the change specs for behavior. Today, Rust assembles a `BarSnapshot` from synchronous providers on the one-second metrics trigger, passes it over flutter_rust_bridge, and Flutter distributes each field through granular `ValueNotifier` slices. Existing CPU and memory modules establish the compact metric-pill visual pattern. Configuration is parsed in Rust and mapped through a secret-free UI configuration contract.

Battery state is Linux sysfs data rather than a service or panel: the source has a device directory containing `type`, `capacity`, and `status` files. Desktop machines can contain AC adapters or no power supplies, so the absence case is a normal state, not an error UI.

## Goals / Non-Goals

**Goals:**
- Preserve a single native source of truth for selecting and reading battery state.
- Add battery data without weakening snapshot failure tolerance or rebuild isolation.
- Keep auto-discovery portable across systems whose battery is not named `BAT0`.
- Reuse Alice's existing metric-pill and configurable Phosphor icon conventions.

**Non-Goals:**
- A battery details panel, estimated time remaining, power profiles, notifications, or suspend thresholds.
- Multiple-battery aggregation.
- Runtime configuration-file watching; configuration continues to apply at application startup.
- Support for non-Linux battery APIs.

## Decisions

### Add a native optional battery snapshot and sysfs provider

Define an optional battery state in the Rust snapshot contract with integer capacity and status. A dedicated provider reads `/sys/class/power_supply`; snapshot assembly receives it through the existing testable provider boundary and falls back to `None` on any discovery or parsing failure. Flutter receives the generated model, stores it in its own optional granular slice, and the top bar listens only to that slice.

This keeps sysfs I/O out of Dart, makes behavior directly testable from temporary filesystem fixtures, and avoids app-wide rebuilding on each capacity refresh. A Dart-side reader was rejected because it would split hardware semantics across the bridge and make filesystem tests less hermetic.

### Select the device deterministically

When `battery.device_name` is non-blank, use that directory name. Otherwise, enumerate power-supply entries in stable lexical order and choose the first whose `type` file is `Battery`. The selected entry must provide a valid integer capacity in the inclusive 0–100 range and a readable status; otherwise no battery state is emitted.

Lexical ordering makes auto-selection predictable when a machine exposes multiple batteries. Aggregating multiple devices was rejected because capacity aggregation requires energy/charge units and policy beyond this small module.

### Treat absence as optional state, not an error

The configured `battery.enable` default is true, but disabled, missing, unreadable, invalid, and auto-discovery-empty states all map to absent battery data and no module. The runtime's existing one-second metric trigger refreshes this state; no additional watcher is necessary for a percentage indicator.

An unavailable placeholder was rejected because the agreed behavior is to keep desktop bars free of non-actionable hardware errors.

### Map display state in Flutter from stable raw data

The module uses capacity and status to choose its icon: `Charging` and `Full` always select `battery-charging`; all other statuses use 0–10 warning, 11–33 low, 34–55 medium, 56–77 high, and 78–100 full. The raw snapshot deliberately retains status so the presentation rule is explicit and can be tested independently. Semantic `AliceIcons` descriptors supply regular and duotone horizontal Phosphor variants, and the module uses the existing metric pill layout with `<capacity>%` text.

Sending a preselected icon identifier from Rust was rejected because icon presentation and its regular/duotone policy are Flutter UI concerns.

### Propagate configuration through both existing consumers

Battery configuration is added to the Rust typed config and documented default template, then exposed in `AliceUiConfig` and Flutter's `AliceConfig`. The snapshot runtime uses its native loaded config for source selection and enablement; the top bar uses the Flutter config to gate rendering. This matches the existing startup config model and ensures disabled modules neither read nor display battery state.

## Risks / Trade-offs

- [Some systems expose multiple batteries] → Stable first-device selection is predictable; users can select a specific device with `battery.device_name`.
- [Sysfs entries can disappear during read] → Treat every read error as absent state and re-evaluate on the next one-second trigger.
- [A `Full` state can be reported differently by hardware] → Follow the explicit `Charging`/`Full` status contract; all other status values use capacity icons.
- [Bridge model changes require generated-code updates] → Regenerate flutter_rust_bridge bindings and cover Rust/Dart snapshot construction in tests.

## Migration Plan

1. Ship the new default-enabled `battery` section in the commented template.
2. Existing user configuration files remain valid because omitted settings use typed defaults.
3. If a user encounters unexpected multi-battery selection, they can set `battery.device_name` to the desired sysfs directory name.
4. Rollback consists of setting `battery.enable: false` or reverting the release; no stored data or schema migration is involved.
