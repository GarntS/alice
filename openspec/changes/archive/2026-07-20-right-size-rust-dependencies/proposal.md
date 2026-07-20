## Why

`alice_platform` requests full Tokio and Hyper feature sets and directly declares `ring`, although inspected source uses a narrower Tokio API, only Hyper HTTP types directly, and reaches Ring through rustls. Right-sizing direct declarations makes build requirements explicit without changing versions, TLS policy, or runtime behavior.

## What Changes

- Replace Tokio `full` with the minimum direct features needed for the inspected runtime, macro/select, synchronization, task, and timer APIs.
- Remove Hyper `full`; retain only direct features proven necessary by compilation and the existing HTTP clients.
- Remove the unused direct `ring` dependency while retaining `rustls`/`hyper-rustls` Ring features and `init_app` provider installation.
- Allow `native/Cargo.lock` to change only if Cargo resolution requires it; do not upgrade package versions.
- Verify the resulting feature graph rather than claiming transitive packages disappear.

## Capabilities

### New Capabilities

### Modified Capabilities
- `build-packaging`: Require native dependency feature declarations to match direct code needs while preserving the existing Rust build, HTTP protocols, OAuth flow, and Ring TLS provider.

## Impact

- Affected manifest: `native/alice_platform/Cargo.toml`.
- Conditional generated resolution file: `native/Cargo.lock`, only if Cargo changes it during locked dependency resolution.
- Validation paths: all Rust targets/tests, Cargo feature-tree inspection, calendar OAuth compile path, and Pirate Weather HTTPS compile path.
- No application source, API, dependency version, TLS provider, protocol, or packaging behavior change is intended.
