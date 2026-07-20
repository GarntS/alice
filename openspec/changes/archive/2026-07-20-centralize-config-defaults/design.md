## Context

`AliceConfig::default()` defines typed defaults, while `RawConfig::into_config` repeats literals for theme mode, top-bar transparency, network label visibility, tray count, and panel gap. The shipped template is parsed on first run. Its second world clock is `Australia/Sydney`, while the typed default is fixed `AEST`/UTC+10; the user explicitly chose to align the typed default to dynamic Sydney behavior.

## Goals / Non-Goals

**Goals:**
- Use typed defaults for omitted raw fields.
- Make the shipped template and typed defaults effective-value equivalent.
- Preserve normalization, validation, and every default except the authorized Sydney alignment.

**Non-Goals:**
- Changing YAML keys, deserialization strictness, weather validation, command execution, or FRB shapes.
- Editing the template, because it already expresses the selected IANA-zone behavior.
- Refactoring unrelated configuration models.

## Decisions

### Centralize fallbacks through one defaults value

In `RawConfig::into_config`, create one `AliceConfig::default()` value and use its fields for omitted theme mode, booleans, tray count, panel gap, power commands, notification settings, weather settings, and time-zone fallback. Preserve `.max(1)`, `.max(300)`, color normalization, trimming, and other transformations after fallback selection.

Calendar poll interval remains a `CalendarConfig`-specific default because calendar itself is optional and has no default instance.

### Resolve the typed Sydney default through the existing IANA mechanism

Construct the second typed default from `Australia/Sydney` using the same `chrono-tz` current abbreviation/offset policy used by `resolve_time_zone_config`, preferably through a small shared helper rather than duplicating timezone resolution. This intentionally changes `AliceConfig::default().time_zones[1]` from fixed AEST/10 to AEST/10 or AEDT/11 according to current date.

Alternative: preserve the mismatch or change the template to fixed AEST. Both were offered and rejected by the user.

### Compare effective template and typed defaults

Parse `DEFAULT_CONFIG_TEMPLATE` with `from_yaml_str` and compare the complete effective `AliceConfig` to `AliceConfig::default()`. Replace, rather than supplement, manual value-by-value “intent” assertions where the parity assertion provides stronger coverage. Keep focused tests for exact documented values and invalid-value fallbacks.

## Risks / Trade-offs

- **Time-dependent Sydney result** → Both paths must call the same resolver closely enough to produce the same current period; test around one captured UTC instant if needed.
- **A DST transition occurs between evaluations** → Prefer a helper accepting a captured `DateTime<Utc>` used by both values in the parity test, without changing production semantics.
- **Moving fallback ownership changes clamping** → Assert minimum tray/weather and empty-command cases explicitly.

## Migration Plan

No persisted files are rewritten. Existing user YAML is unchanged. Only fallback behavior after failed/unavailable config and direct `AliceConfig::default()` consumers gain dynamic Sydney DST behavior. Roll back the helper/default change if parity cannot be made deterministic without broad redesign.

## Open Questions

None; the behavior choice was explicitly made during proposal creation.
