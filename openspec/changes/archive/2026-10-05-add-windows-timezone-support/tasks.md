## 1. Dependency and Rust compatibility

- [x] 1.1 Add the focused ICU4X `icu_time` dependency with compiled mapping data and minimal features; update the native Cargo lockfile.
- [x] 1.2 Verify selected ICU dependencies' MSRV against development, Nix packaging, and release CI Rust versions; update insufficient tooling and document the minimum only where necessary.

## 2. Timezone resolution

- [x] 2.1 Add a reusable ICU Windows-ID resolver using worldwide-default territory and a once-initialized BCP-47-to-canonical-IANA index, safely handling names unavailable in chrono-tz.
- [x] 2.2 Integrate Windows resolution after IANA parsing and before embedded-offset fallback in the ICS time parser, retaining named-zone semantics per occurrence.
- [x] 2.3 Verify all event/recurrence date properties and timezone-qualified absolute alarms use the same resolver; preserve existing UTC, floating, all-day, fallback, and DST ambiguity policies.

## 3. Regression coverage

- [x] 3.1 Add synthetic Outlook-style tests for the October 5, 2026 12:30 Eastern regression, including start/end UTC instants and explicit local conversion, winter dates, and missing embedded definitions.
- [x] 3.2 Test Eastern, GMT, and Pacific Windows mappings, worldwide-default behavior, and resolution independent of the host timezone.
- [x] 3.3 Test recurrence across DST, RDATE/EXDATE matching, and detached exception replacement without duplicate occurrences; correct generated end times to preserve the master event's elapsed duration.
- [x] 3.4 Correct duration parsing of the `T` separator and test relative reminders and Windows-zone absolute alarm instants, plus existing IANA/UTC/floating/all-day and unknown-zone fallback compatibility.

## 4. Verification

- [x] 4.1 Run native formatting, relevant calendar/reminder tests, and the native test suite; use `nix develop --command` where required.
- [x] 4.2 Verify native/application builds and affected packaging/CI toolchain paths, assessing added dependency and binary-size impact.
- [x] 4.3 Rebuild and restart the Flutter-run application with user coordination, then confirm the configured event displays at 12:30 rather than 13:30; do not retain private feed data in committed fixtures or logs.
