## 1. Establish Direct Feature Requirements

- [x] 1.1 Re-scan non-generated `alice_platform` source for Tokio, Hyper, and Ring API use and record the direct Tokio needs: multi-thread runtime, macros/select, sync, task/runtime, and time.
- [x] 1.2 Capture baseline `cargo tree --manifest-path native/Cargo.toml -p alice_platform -e features` output for comparison without claiming transitive removals.

## 2. Right-Size the Manifest

- [x] 2.1 In `native/alice_platform/Cargo.toml`, replace Tokio `full` with `default-features = false` and the minimal verified features, initially `rt-multi-thread`, `macros`, `sync`, and `time`.
- [x] 2.2 Remove Hyper `full` and retain only features proven necessary for direct types/client compilation; keep current `hyper-util` and `hyper-rustls` HTTP/1, HTTP/2, Tokio, webpki-roots, and Ring behavior.
- [x] 2.3 Remove the direct `ring = "0.17"` declaration while preserving `rustls` Ring support and `api.rs::init_app` provider installation.
- [x] 2.4 Run Cargo locked first; modify `native/Cargo.lock` only if resolution requires it, and verify no package version changed.

## 3. Compile and Graph Verification

- [x] 3.1 Run `cargo check --locked --manifest-path native/Cargo.toml --workspace --all-targets`; add a direct feature only when the compiler demonstrates it is required and document the reason.
- [x] 3.2 Run `cargo test --locked --manifest-path native/Cargo.toml -p alice_platform`.
- [x] 3.3 Run `cargo tree --manifest-path native/Cargo.toml -p alice_platform -e features -i tokio`, `-i hyper`, and `-i ring`; verify direct `full` activations and the direct Ring edge are gone while Ring remains available through rustls.
- [x] 3.4 Verify `weather.rs::fetch_weather`, calendar hub/OAuth construction, HTTP/1/HTTP/2 client setup, and Ring provider initialization all compile without source edits.
- [x] 3.5 Confirm no dependency version, TLS provider, public API, application source, generated file, or packaging file changed; report actual feature-graph effects.
- [x] 3.6 Run `openspec validate right-size-rust-dependencies --strict`.
