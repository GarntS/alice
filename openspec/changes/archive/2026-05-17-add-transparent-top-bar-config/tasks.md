## 1. Configuration Model

- [x] 1.1 Add `transparent_top_bar: bool` to the native Rust `AliceConfig` model with default `false`.
- [x] 1.2 Parse optional `theme.transparent_top_bar` from YAML and preserve default behavior when omitted.
- [x] 1.3 Add Rust config tests for omitted, enabled, and disabled transparent top bar values.
- [x] 1.4 Document `transparent_top_bar` in `assets/config/default_config.yaml`.

## 2. Flutter Bridge and Mapping

- [x] 2.1 Regenerate flutter_rust_bridge bindings so Dart receives `transparentTopBar`.
- [x] 2.2 Add `transparentTopBar` to Flutter `AliceConfig` and fallback config.
- [x] 2.3 Map the generated Rust/Dart config field into Flutter's UI configuration model.

## 3. Top Bar Rendering

- [x] 3.1 Update `TopBar` shell decoration to omit background fill and outer border when `config.transparentTopBar` is true.
- [x] 3.2 Ensure child module styling remains unchanged when transparent top bar is enabled.

## 4. Verification

- [x] 4.1 Add or update widget tests covering transparent top bar decoration behavior.
- [x] 4.2 Run relevant Rust config tests and Flutter widget/unit tests.
- [x] 4.3 Run OpenSpec validation for `add-transparent-top-bar-config`.
