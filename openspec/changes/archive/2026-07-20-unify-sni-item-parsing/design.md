## Context

`tray.rs::canonical_sni_item_id` parses registration input into a string stored in `WatcherState.registered_items`. Later, `parse_item_identifier` independently parses watcher property strings into `StatusNotifierItemRef { service_name, object_path }`. Both handle service-only, service/path, and sender-relative path forms. The semantic type is currently declared after watcher service code.

## Goals / Non-Goals

**Goals:**
- Parse every accepted form through one semantic function.
- Derive watcher canonical strings from the parsed value.
- Keep all accepted/rejected cases and D-Bus outputs unchanged.

**Non-Goals:**
- Implementing item unregistration or owner-loss tracking.
- Changing watcher interfaces, duplicate suppression, ordering, trigger timing, icon behavior, snapshots, or actions.
- Introducing a protocol dependency or generic parser framework.

## Decisions

### Make `StatusNotifierItemRef` own parsing and canonical formatting

Move the private type before registration helpers if needed and add private methods conceptually shaped as:

```rust
fn parse(identifier: &str, sender: Option<&str>) -> Option<Self>;
fn canonical_id(&self) -> String;
```

`parse` trims input; sender-relative object paths require a non-empty sender; service/path splits at the first slash; service-only uses `DEFAULT_ITEM_PATH`. `canonical_id` concatenates service and object path exactly as current watcher state expects.

Alternative: make `canonical_sni_item_id` call `parse_item_identifier` while retaining both free functions. Rejected because it leaves two names for one grammar and obscures the semantic owner.

### Route both call sites through the type

`register_sni_item` parses then canonicalizes before inserting into the `HashSet<String>`. `registered_items_from_single_watcher` parses each watcher string directly. Keep the string set because D-Bus properties/signals expose canonical strings and sorting is already defined over them.

### Table-test grammar equivalence

Cover empty input, empty sender, service only, service/path, and relative path with sender. For each valid case assert semantic fields and canonical output. Retain registration deduplication tests.

## Risks / Trade-offs

- **Whitespace behavior drifts** → Preserve current trimming at input boundaries and test it.
- **Slash splitting changes unusual service/path values** → Split at the first slash exactly as current `parse_item_identifier` does.
- **Refactor accidentally changes D-Bus payload** → Assert exact canonical strings in registration tests.

## Migration Plan

This changes only private in-process parsing. Refactor atomically, run tray/Rust tests, and revert if any accepted form changes. No data or rollout migration exists.

## Open Questions

Dynamic unregistration remains a separate correctness concern and is explicitly excluded.
