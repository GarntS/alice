## 1. Semantic Identifier Type

- [x] 1.1 Move private `StatusNotifierItemRef` before registration helpers if required and add one parser for empty, service-only, service/path, and sender-relative object-path inputs.
- [x] 1.2 Add canonical formatting on `StatusNotifierItemRef` that produces the existing `<service><object_path>` watcher ID exactly.
- [x] 1.3 Preserve trimming, first-slash splitting, non-empty sender requirements, and `DEFAULT_ITEM_PATH` behavior.

## 2. Route Both Call Paths Through One Parser

- [x] 2.1 Update `register_sni_item` to parse into `StatusNotifierItemRef`, derive the canonical string, and insert that string into the existing `HashSet`.
- [x] 2.2 Update `registered_items_from_single_watcher` to use the same parser for watcher property values.
- [x] 2.3 Remove `canonical_sni_item_id` and `parse_item_identifier` as separate grammars, including now-unused imports/helpers, without changing watcher state, sorting, signals, triggers, snapshots, or actions.

## 3. Protocol-Preservation Tests

- [x] 3.1 Add table-driven tests for empty input, empty sender, whitespace, service-only, service/path, and relative-path-with-sender forms, asserting fields and exact canonical output.
- [x] 3.2 Retain registration deduplication and host-registration tests and assert existing canonical signal/property strings.
- [x] 3.3 Run `cargo test --manifest-path native/Cargo.toml -p alice_platform tray::tests` and `cargo test --manifest-path native/Cargo.toml -p alice_platform`.
- [x] 3.4 Search active `tray.rs` code and require one identifier parser/canonicalizer; confirm no unregistration/name-owner lifecycle behavior was added.
- [x] 3.5 Run `openspec validate unify-sni-item-parsing --strict`.
