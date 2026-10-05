## Verification

- ICU 2.3 timezone dependencies require Rust 1.88 (Cargo metadata). Interactive Rust: 1.92.0; pinned Nix dev/package toolchain: 1.97.1. Debian/Fedora packaging installs latest stable via rustup; Arch installs stable via rustup. No toolchain upgrades required.
- `nix develop --command cargo fmt --manifest-path native/Cargo.toml --all --check`: passed.
- `nix develop --command cargo test --manifest-path native/Cargo.toml --workspace --locked`: 162 platform tests and 4 layer-shell tests passed.
- Worldwide mapping test passed in separate processes with TZ=UTC, Asia/Tokyo, and America/Los_Angeles.
- `nix develop --command flutter build linux --release`: passed, including native release library.
- `nix eval --raw .#packages.x86_64-linux.default.drvPath`: passed. Full Nix/distribution package builds were not run; packaging paths use the audited Rust toolchains and native lockfile.
- `git diff --check`: passed.
- Focused ICU features avoid IXDTF, but ICU time transitively includes calendar and locale fallback compiled data. Lockfile adds 10 packages and updates 9 shared packages.
- Existing release executable before rebuild: 52,771,904 bytes; rebuilt executable: 53,690,088 bytes (+918,184 bytes, ~1.74%). Static library: 123,707,130 -> 125,338,108 bytes (+1,630,978 bytes, ~1.32%). These are comparisons with the previously built artifacts, not an isolated same-toolchain baseline, so other intervening changes can contribute.
- User restarted the Flutter-run application and confirmed the configured event now displays correctly at 12:30 rather than 13:30. No private feed data was inspected or retained.
