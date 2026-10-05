# Verification

## Automated checks (2026-10-05)

Run in the project Nix development environment:

- `cargo test --manifest-path native/Cargo.toml -p alice_platform --lib`: **173 passed**. Includes isolated-bus action, artwork/lifecycle, menu payload/update/cancellation, malformed-publisher, optional-method, and timeout checks.
- `flutter analyze`: **no issues**.
- `flutter test`: **143 passed**. Includes input routing, anchors, popup replacement, request-scoped stale dismissal, conventional menu rows, submenu bounds, scrolling, keyboard navigation, live updates, and complete dismissal.
- `flutter_rust_bridge_codegen generate`: successful; two consecutive runs produce identical Dart/Rust/C binding hashes.
- `flutter build linux --debug`: successful.
- `openspec validate fix-tray-icon-and-menu-compatibility --strict`: valid.
- `git diff --check`: clean.

The global Rust linker initially referenced an unavailable Nix store wrapper; using `nix develop` resolves the build environment. Tests exposed and fixed private-bus capability-cache collisions, a missing-artwork retry deadline race, and popup keyboard focus acquisition.

## Approved implementation design adjustment

Native show/hide commands and popup notifications now carry request identity. Previously a bare `None` hide could cancel a newer popup. The shared bridge change was approved interactively, documented in `design.md`, and covered by regression tests.

## Live verification and accepted limitations

The user performed live verification with the rebuilt Alice and Handy 0.9.1 and reported that the published menu entries work, while Secondary action appears to do nothing. This is recorded as user-performed verification, not an automated GUI check.

Secondary action investigation:

- Live Handy registration: `:1.13975/org/ayatana/NotificationItem/tray_icon_tray_app_66661_1`.
- Introspection confirms KDE `SecondaryActivate(ii)` and a published D-Bus menu; no `Activate` or `ContextMenu` is advertised.
- A direct, bounded `SecondaryActivate` call receives a successful reply (exit status 0).
- Handy loads libayatana-appindicator 0.5.92. Its handler returns success even when no enabled/visible secondary activation target exists. Source: https://github.com/AyatanaIndicators/libayatana-appindicator/blob/0.5.92/src/app-indicator.c (SecondaryActivate handler).
- Handy's executable contains `app_indicator_new` but no reference to `app_indicator_set_secondary_activate_target` or its getter. Together with the observed successful no-op, this supports an unassigned application-side target, not an Alice dispatch failure.
- The entry remains generic and protocol-defined. No Handy-specific Settings mapping or destructive menu selection was introduced. Backend and widget tests independently verify synthetic dispatch through SecondaryActivate rather than a menu Event.

The current desktop has one active output (HDMI-A-1, 3840x2160, scale 1.0). The user explicitly requested marking monitor verification done rather than testing another configuration. Task 6.3 is therefore accepted with the physical multi-monitor/mixed-scale live check **waived**, not claimed as executed. Conventional KDE/freedesktop activation, icon changes, owner loss, focus/navigation, and dismissal are covered by automated fake-publisher and widget/controller tests; no additional real Activate-capable application was launched for this check.

No desktop output configuration changes or agent-driven destructive menu selections were made. The absence of a visible Handy secondary action is an application-side limitation; cross-monitor/mixed-scale live placement remains an accepted verification limitation.
