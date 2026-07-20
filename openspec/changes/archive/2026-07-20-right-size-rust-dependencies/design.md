## Context

`native/alice_platform/Cargo.toml` directly enables Tokio `full`, Hyper `full`, and `ring`. Inspected source needs Tokio multi-thread runtime, macros/select, sync/mpsc, tasks, and time; direct Hyper use is `Request`, `Uri`, and HTTP URI errors in `weather.rs`; Ring is referenced only as `rustls::crypto::ring`. Cargo feature unification means transitive Google Calendar/OAuth crates may continue enabling features or retaining Ring.

## Goals / Non-Goals

**Goals:**
- Express only direct feature requirements.
- Remove the redundant direct Ring edge.
- Preserve compilation, TLS provider selection, HTTP protocol support, and package versions.

**Non-Goals:**
- Replacing HTTP/TLS/OAuth libraries, disabling Ring, forcing transitive graph removal, upgrading dependencies, or optimizing runtime code.
- Changing application source or generated bindings.

## Decisions

### Narrow Tokio deliberately

Start with `default-features = false` and `features = ["rt-multi-thread", "macros", "sync", "time"]`. These cover `Runtime::new`, the one-worker calendar runtime, `tokio::select!`, spawning/tasks, mpsc, intervals, and sleeps. Add a feature only if `cargo check --all-targets` identifies a verified direct requirement; document why in the manifest/change.

### Remove Hyper full without guessing protocol ownership

Direct Hyper type use does not require `full`; declare Hyper without `full` (and disable defaults if supported/appropriate). Keep existing `hyper-rustls` and `hyper-util` HTTP/1/HTTP/2 features because they construct actual clients. Do not remove protocol features merely because another dependency currently unifies them.

### Remove only the direct Ring declaration

Delete `ring = "0.17"`. Keep `rustls` with Ring, `hyper-rustls` Ring, and `api.rs::init_app` installing the Ring provider. `cargo tree -e features -i ring` must still show Ring through the TLS stack.

### Lockfile discipline

Run Cargo in locked mode first. If manifest feature changes require a lockfile rewrite, allow only resolution changes caused by this manifest and verify no version upgrade. Otherwise leave `native/Cargo.lock` untouched.

## Risks / Trade-offs

- **Feature needed only in a less common target** → Use `cargo check --all-targets` and compile the full workspace, not only unit tests.
- **Transitive feature unification masks an omitted direct requirement** → Inspect source-to-feature mapping and document direct needs; do not use transitive activation as the declaration rationale.
- **No graph-size reduction** → The primary gain is accurate ownership; report actual `cargo tree` output without overstating it.
- **TLS behavior changes** → Retain Ring features/provider initialization and compile both calendar and weather paths.

## Migration Plan

Change only the manifest, conditionally regenerate the lockfile, run checks/tests/tree inspection, and revert declarations if required behavior cannot compile without broad features. No runtime rollout or data migration exists.

## Open Questions

Exact post-change transitive reductions are intentionally left to measured Cargo output during implementation.
