# Layer Shell Windowing Specification

## Purpose
Define native window creation, layer-shell integration, panel placement, and GTK fallback behavior.

## Requirements

### Requirement: Layer-shell capability detection
Alice SHALL detect whether the Wayland compositor advertises `zwlr_layer_shell_v1` through the Rust layer-shell library.

#### Scenario: Application activates
- **WHEN** the GTK application activates
- **THEN** Alice SHALL call the Rust FFI capability probe
- **AND** Alice SHALL use layer-shell configuration when both the Rust probe and `gtk-layer-shell` support are available

### Requirement: Bar window configuration
Alice SHALL configure the main bar window as a top layer-shell surface when layer-shell is supported.

#### Scenario: Layer-shell bar is created
- **WHEN** the main window is created on a supported compositor
- **THEN** Alice SHALL anchor it to the top, left, and right edges
- **AND** Alice SHALL set a top-layer namespace for the bar
- **AND** Alice SHALL reserve an exclusive zone for the 44 px bar height

### Requirement: Panel window configuration
Alice SHALL create floating panel windows lazily and position them relative to captured bar anchors.

#### Scenario: Panel is shown
- **WHEN** Flutter sends `showPanel` with a panel id, anchor, alignment, size, and gap
- **THEN** the C++ runner SHALL create or reuse a panel `FlView`
- **AND** the runner SHALL size and position the panel on the monitor containing the anchor
- **AND** the runner SHALL notify Dart of the secondary view id after the native window is shown

### Requirement: Single visible native panel
Alice SHALL ensure only one native panel window is visible at a time.

#### Scenario: A second panel is opened
- **WHEN** `showPanel` is called for one panel id
- **THEN** the runner SHALL hide any other visible panel windows
- **AND** the runner SHALL record the requested panel as current

### Requirement: Dismiss overlay
Alice SHALL provide a native click target that dismisses the current panel when the user clicks outside the panel.

#### Scenario: Dismiss overlay is clicked
- **WHEN** the dismiss overlay receives a button press
- **THEN** Alice SHALL hide the current panel and dismiss overlay
- **AND** Alice SHALL notify Dart that the panel has hidden

### Requirement: Fallback GTK windows
Alice SHALL fall back to non-layer-shell GTK window configuration when layer-shell support is unavailable.

#### Scenario: Layer-shell is unavailable
- **WHEN** layer-shell support is not detected or `gtk-layer-shell` is unavailable
- **THEN** Alice SHALL configure undecorated GTK windows with keep-above behavior where implemented
