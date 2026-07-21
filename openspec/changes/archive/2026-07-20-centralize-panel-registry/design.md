## Context

`AlicePanel` has six variants. `lib/panel_controller.dart` repeats them in `alicePanelFromId`, six private `ValueNotifier<bool>` fields, six public getters, `openListenable`, `_setOpen`, and `dispose`. `lib/app.dart` repeats the inverse enum-to-string mapping in `_panelId`. The granular listenables are not removable: `lib/widgets/top_bar.dart` and `test/rebuild_isolation_test.dart` demonstrate that only prior/next highlight consumers may rebuild. Existing public parsing and named getter APIs must remain compatible.

## Goals / Non-Goals

**Goals:**
- Define each panel's native wire id once and make parsing round-trippable.
- Define granular notifier storage once for every `AlicePanel.values` member.
- Remove notifier-selection and reverse-id switches without changing notification behavior.
- Preserve all current callers and native payloads.

**Non-Goals:**
- Remove `PanelController`'s global `ChangeNotifier`, the granular listenables, named getters, or `alicePanelFromId`.
- Move visual sizes from `lib/widgets/panels/panel_sizes.dart` into the enum.
- Change panel ids, ordering, anchors, dimensions, method-channel payloads, panel rendering, or top-bar composition.
- Change native Rust, C++, generated files, dependencies, or persisted data.

## Decisions

### Store the wire id on the enhanced enum

Change `AlicePanel` to an enhanced enum whose six values carry these exact ids: `media`, `clock`, `weather`, `trayOverflow`, `power`, and `notifications`. Expose a read-only id field/getter. Implement `alicePanelFromId(String?)` by searching `AlicePanel.values` for an exact id match and returning null for null or unknown values. With only six values and low-frequency bridge commands, a linear lookup is the least-weight adequate structure.

Remove `_AliceAppState._panelId` and pass the canonical enum id from `_syncPanelState` to `AlicePlatform.showPanel`. Keep `AlicePlatform.watchPanelType` delegating to `alicePanelFromId`.

A generated map or separate metadata registry was rejected because it would preserve a second source of truth. Panel sizes remain separate because they are UI policy rather than bridge identity.

### Store open notifiers in one complete enum-keyed map

Replace the six private notifier fields with one map initialized by iterating `AlicePanel.values`, with one `ValueNotifier<bool>(false)` per enum value. `openListenable(panel)` and `_setOpen(panel, value)` use this map. Dispose every notifier by iterating the map values.

Retain `mediaOpen`, `clockOpen`, `weatherOpen`, `trayOverflowOpen`, `notificationsOpen`, and `powerOpen` with the same `ValueListenable<bool>` types, delegating each to `openListenable` for its enum value. This preserves source compatibility while ensuring storage and selection logic have one source.

A single `ValueNotifier<AlicePanel?>` was rejected because every highlight builder would be notified on every toggle, violating tested rebuild isolation.

### Preserve controller transition ordering

Do not change `toggle`, `close`, `_notifyGranular`, global `notifyListeners`, or anchor semantics except for routing notifier access through the registry. A switch from one panel to another must still notify the previous granular notifier false, the next granular notifier true, then global listeners once.

## Risks / Trade-offs

- [A missing enum map entry would fail at runtime] → Construct the map directly from `AlicePanel.values` and add a test iterating every value through `openListenable` and disposal.
- [Wire protocol drift] → Assert the exact six ids and enum/id round trips; retain the method-channel payload test for `trayOverflow`.
- [Compatibility façade retains some boilerplate] → Keep it deliberately; removing public named getters is outside scope and unnecessary for obtaining a single storage source.
- [Generated/native code may produce unknown ids] → Preserve null-on-unknown parsing and render no panel content, as today.
