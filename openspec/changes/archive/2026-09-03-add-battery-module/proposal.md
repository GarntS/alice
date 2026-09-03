## Why

Alice's bar exposes several machine-status metrics but provides no laptop battery state. Users need an at-a-glance capacity and charging indication that works by default on battery-powered systems without cluttering desktops that have no usable battery.

## What Changes

- Add an optional battery status bar module, enabled by default.
- Discover a usable battery from Linux sysfs automatically, while allowing users to enable or disable the module and select a named device in `config.yaml`.
- Read the selected device's capacity and charging status from `/sys/class/power_supply` and send an optional battery snapshot to Flutter.
- Render the current integer percentage beside a semantic horizontal Phosphor battery icon; use the charging icon for `Charging` and `Full` states.
- Hide the module when disabled, no battery can be selected, or the selected battery data is unavailable.

## Capabilities

### New Capabilities
- `battery-status`: Linux sysfs battery discovery, capacity/status snapshots, and top-bar battery presentation.

### Modified Capabilities
- `configuration`: Add typed and documented battery enablement and device-selection settings.
- `snapshot-runtime`: Include optional battery state in snapshot assembly and refresh it with the metric polling trigger.
- `snapshot-state`: Ingest battery state as an independently listenable Flutter snapshot slice.
- `phosphor-icon-system`: Provide semantic Phosphor battery icon descriptors in both supported styles.

## Impact

- Rust configuration, sysfs provider, runtime snapshot contract, and flutter_rust_bridge generated bindings.
- Flutter configuration mapping, snapshot state, icon catalog, and right-side top-bar modules.
- Default `config.yaml`, README configuration documentation, and Rust/Dart/widget tests.
