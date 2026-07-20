## 1. Shared Typed Defaults

- [x] 1.1 Refactor `native/alice_platform/src/config.rs::RawConfig::into_config` to obtain omitted theme mode, booleans, tray count, panel gap, power, notification, weather, and time-zone values from one typed defaults value rather than repeated literals.
- [x] 1.2 Preserve color normalization, optional-label trimming, empty-command fallback, tray minimum 1, weather minimum 300, optional calendar behavior, and calendar poll minimum/default.
- [x] 1.3 Search `RawConfig::into_config` for repeated scalar defaults and document any retained literal whose owning typed default cannot represent it, such as optional-calendar poll interval.

## 2. Dynamic Sydney Default

- [x] 2.1 Extract/reuse a small `chrono-tz` IANA resolver so both raw `tz_name` entries and the second built-in world-clock default resolve `Australia/Sydney` consistently.
- [x] 2.2 Change `AliceConfig::default().time_zones[1]` from fixed `AEST`/UTC+10 to the current Sydney abbreviation/offset (AEST/10 or AEDT/11), without changing the shipped template.
- [x] 2.3 Make resolution/parity testing deterministic across a daylight-saving transition, preferably by sharing a captured UTC instant in testable helper logic.

## 3. Contract and Regression Tests

- [x] 3.1 Replace the manual template-intent test with a test that parses `DEFAULT_CONFIG_TEMPLATE` and compares the complete effective result with `AliceConfig::default()`.
- [x] 3.2 Add deterministic resolver tests proving Sydney standard-time and daylight-time abbreviation/offset behavior at fixed instants.
- [x] 3.3 Retain focused tests for documented scalar defaults, invalid accent/commands, tray/weather clamps, explicit overrides, and hermetic file creation.
- [x] 3.4 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform config::tests` and `cargo test --manifest-path native/Cargo.toml -p alice_platform`.
- [x] 3.5 Confirm only `native/alice_platform/src/config.rs` changed; do not modify `assets/config/default_config.yaml`, generated files, Dart models, or YAML keys.
- [x] 3.6 Run `openspec validate centralize-config-defaults --strict`.
