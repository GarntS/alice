## Why

Configuration defaults are repeated between `AliceConfig::default`, hard-coded parser fallbacks, and the shipped first-run template. Making typed defaults authoritative and testing template parity reduces drift without changing the YAML contract or any effective value.

## What Changes

- Refactor `RawConfig::into_config` so omitted optional values consistently come from `AliceConfig::default()` (or nested typed defaults) rather than repeated literals.
- Preserve validation and normalization rules such as minimum tray count, weather interval clamping, color normalization, and empty-command fallback.
- Replace the manual “template intent” assertions with a contract test that parses `DEFAULT_CONFIG_TEMPLATE` and compares its effective typed values with `AliceConfig::default()`.
- **BREAKING**: Align the second typed world-clock default with the template’s `Australia/Sydney` IANA zone, so its effective label/offset follows daylight saving instead of remaining fixed at `AEST`/UTC+10. The user explicitly selected this behavior over preserving the mismatch.
- Keep the shipped template and every other current default unchanged.

## Capabilities

### New Capabilities

### Modified Capabilities
- `configuration`: Establish typed defaults as the authoritative source for omitted values and require effective parity with the shipped default template.

## Impact

- Affected implementation and tests: `native/alice_platform/src/config.rs`.
- Validation input only: `assets/config/default_config.yaml`; it must not change unless a discovered mismatch makes parity impossible, in which case implementation must stop for an explicit behavior decision.
- Public API and data format: unchanged Rust/FRB types, YAML keys, and fallback semantics; `AliceConfig::default().time_zones[1]` intentionally changes from fixed AEST/UTC+10 to the template-equivalent current Sydney abbreviation/offset.
- Dependencies and generated files: unchanged.
