## Context

See proposal.md for the reported bug. The subscription-feed parser is handwritten and separate from CalDAV's `icalendar` path. `parse_ics_time` resolves IANA names through `chrono-tz`, then embedded VTIMEZONE offsets, then host-local time. Embedded zones currently retain only their first TZOFFSETTO. Named zones already resolve an offset for each occurrence's wall date/time.

ICU4X `icu_time` 2.3.0 exposes WindowsParser with compiled CLDR mapping data. It returns an ICU BCP-47 timezone identity; IanaParserExtended exposes identity/canonical-IANA pairs. The inspected version requires Rust 1.88. The current shell reports Rust 1.92.0; Nix development/packaging and distribution-based release CI must also be checked during implementation.

## Goals / Non-Goals

**Goals:** Reuse upstream-maintained mappings and the existing named-zone machinery without introducing project-owned mapping data or per-event network requests. Keep date-aware resolution consistent across event and alarm properties.

**Non-Goals:** Full VTIMEZONE transition evaluation; parser replacement with ikal or icalendar; CalDAV changes; configurable territories; changes to unknown-zone fallback policy; new UI or configuration fields.

## Decisions

### Use focused ICU4X dependencies with compiled data

Prefer `icu_time` 2.3.x with default features disabled and `compiled_data` enabled over the entire `icu` umbrella. This is the relevant ICU Rust component, avoids unrelated internationalization features, and embeds the maintained mappings for offline operation. Record resolved versions in the native lockfile. Do not vendor CLDR XML or hand-maintain Windows aliases.

Alternative: custom mappings are smaller initially but transfer data maintenance to Alice; full VTIMEZONE evaluation has a substantially larger correctness surface and neither inspected calendar crate supplies the evaluator.

### Bridge Windows identity to chrono-tz once

Use WindowsParser with no region (CLDR `001` worldwide default). Build a process-wide immutable lookup of ICU timezone identity to canonical IANA name from IanaParserExtended's iterator, resolving the names through chrono-tz. This avoids scanning IANA entries for every property. If any canonical name is unavailable in the selected chrono-tz version, treat that mapping as unresolved and preserve the existing fallback; cover the production identifiers in tests.

Resolution order: explicit UTC suffix; existing IANA parsing; ICU Windows mapping to an IANA named zone; embedded fixed offset; host-local fallback. A mapped Windows zone must become Zone::Named, not a fixed offset computed from the master event. Existing recurrence processing can then resolve each occurrence at its own date.

### Apply the same resolver to absolute alarms

Event properties already share parse_ics_time. Absolute alarms also use that parser but currently pass an empty embedded-zone map; Windows lookup must remain available independently of the map. Confirm timezone-qualified VALUE=DATE-TIME triggers, as well as relative alarms derived from resolved starts. Preserve current ambiguous/nonexistent-time behavior rather than inventing a different DST policy for Windows zones.

### Upgrade Rust only if compatibility requires it

Verify the selected crate's MSRV and all Rust build environments. The current 1.92 shell exceeds the inspected dependency's 1.88 minimum, so no unconditional upgrade is planned. Update insufficient development, Nix packaging, or CI toolchains coherently if needed; document the resulting minimum where appropriate. Avoid unrelated flake or toolchain churn.

### Test normalized instants without depending on the host timezone

Use synthetic Outlook-style definitions and generic event identities, never private feed URLs or titles. Assert UTC starts/ends and explicit America/New_York conversion for the reported regression. Exercise Eastern, GMT, and Pacific Windows IDs, winter/summer dates, absent embedded definitions, recurrence crossing DST, exclusion/exception matching, and absolute/relative alarms. Include existing representation/fallback regressions.

## Risks / Trade-offs

- [Embedded definitions can differ from IANA rules] → Explicitly scope this to recognized Windows identifiers, prefer maintained IANA behavior for them, and leave arbitrary-zone evaluation for another change.
- [Windows names vary by territory] → Use the documented worldwide default, not the host location; defer territorial configuration.
- [ICU canonical names and chrono-tz data can diverge] → Check conversion failures safely and test the feed's identifiers; update dependency data together when needed.
- [Additional compiled data increases binary/build size] → Use focused features, one immutable index, and assess build impact during verification.
- [Release environments use different Rust versions] → Audit actual development, packaging, and CI toolchains rather than assuming the interactive shell proves compatibility.

## Recurrence end-time correction

Regression coverage exposed that generated occurrences reused the master's absolute DTEND. Preserve the elapsed duration between the master's normalized DTSTART and DTEND for each generated timed occurrence, adding it to that occurrence's resolved start. Detached exceptions use their own start/end pair. This also handles start and end expressed in different zones without applying a wall-time shift in the wrong zone.

## Relative alarm duration correction

Alarm regression coverage also exposed that the duration parser attempted to parse an empty numeric field at the `T` separator, dropping standard triggers such as `-PT15M`. Handle the separator before numeric parsing and reject unfinished numeric fields. Include direct duration tests and normalized relative/absolute reminder tests.

## Migration Plan

No configuration or persisted-data migration is required. Ship the native parser and dependency changes together; the next source refresh replaces normalized occurrences using corrected instants. Restart the running Flutter application after rebuilding the native library, because hot reload alone does not replace native code. Rollback consists of reverting the parser/dependency changes and any directly required tooling updates.
