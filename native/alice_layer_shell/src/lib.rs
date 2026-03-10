//! Wayland layer-shell integration for Alice.
//!
//! This crate owns capability detection and, ultimately, creation and placement
//! of the bar surface and floating panel surfaces on wlroots compositors.

use wayland_client::{
    Connection, Dispatch, QueueHandle,
    globals::{GlobalListContents, registry_queue_init},
    protocol::wl_registry,
};

const LAYER_SHELL_INTERFACE: &str = "zwlr_layer_shell_v1";

/// Distinguishes the top bar surface from floating panel surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SurfaceRole {
    Bar,
    Panel,
}

/// Output-relative placement for a surface.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SurfacePlacement {
    pub width: u32,
    pub height: u32,
    pub anchor_top: bool,
    pub anchor_left: bool,
    pub anchor_right: bool,
}

/// Snapshot of the compositor capability relevant to Alice's shell surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LayerShellCapabilities {
    pub layer_shell_supported: bool,
}

/// Marker type for the layer-shell host.
pub struct LayerShellHost;

impl LayerShellHost {
    /// Creates an empty layer-shell host placeholder.
    pub fn new() -> Self {
        Self
    }

    /// Returns the intended placement for the bar or a floating panel.
    pub fn placement_for(role: SurfaceRole) -> SurfacePlacement {
        match role {
            SurfaceRole::Bar => SurfacePlacement {
                width: 0,
                height: 44,
                anchor_top: true,
                anchor_left: true,
                anchor_right: true,
            },
            SurfaceRole::Panel => SurfacePlacement {
                width: 320,
                height: 220,
                anchor_top: true,
                anchor_left: false,
                anchor_right: true,
            },
        }
    }

    /// Detects whether the current Wayland compositor advertises the wlr
    /// layer-shell global.
    pub fn detect_capabilities() -> LayerShellCapabilities {
        let supported = detect_layer_shell_support().unwrap_or(false);
        LayerShellCapabilities {
            layer_shell_supported: supported,
        }
    }
}

#[derive(Default)]
struct RegistryState;

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for RegistryState {
    fn event(
        _state: &mut Self,
        _proxy: &wl_registry::WlRegistry,
        _event: wl_registry::Event,
        _data: &GlobalListContents,
        _conn: &Connection,
        _qh: &QueueHandle<Self>,
    ) {
    }
}

fn detect_layer_shell_support() -> Result<bool, wayland_client::globals::GlobalError> {
    let connection = match Connection::connect_to_env() {
        Ok(connection) => connection,
        Err(_) => return Ok(false),
    };
    let (globals, _queue) = registry_queue_init::<RegistryState>(&connection)?;
    Ok(globals.contents().with_list(|list| {
        list.iter()
            .any(|global| global.interface == LAYER_SHELL_INTERFACE)
    }))
}

#[repr(C)]
pub struct AliceLayerShellCapabilitiesFFI {
    pub layer_shell_supported: bool,
}

#[repr(C)]
pub struct AliceSurfacePlacementFFI {
    pub width: u32,
    pub height: u32,
    pub anchor_top: bool,
    pub anchor_left: bool,
    pub anchor_right: bool,
}

impl From<SurfacePlacement> for AliceSurfacePlacementFFI {
    fn from(value: SurfacePlacement) -> Self {
        Self {
            width: value.width,
            height: value.height,
            anchor_top: value.anchor_top,
            anchor_left: value.anchor_left,
            anchor_right: value.anchor_right,
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn alice_layer_shell_detect_capabilities() -> AliceLayerShellCapabilitiesFFI {
    let capabilities = LayerShellHost::detect_capabilities();
    AliceLayerShellCapabilitiesFFI {
        layer_shell_supported: capabilities.layer_shell_supported,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn alice_layer_shell_bar_placement() -> AliceSurfacePlacementFFI {
    LayerShellHost::placement_for(SurfaceRole::Bar).into()
}

#[unsafe(no_mangle)]
pub extern "C" fn alice_layer_shell_panel_placement() -> AliceSurfacePlacementFFI {
    LayerShellHost::placement_for(SurfaceRole::Panel).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bar_is_full_width_and_top_anchored() {
        let placement = LayerShellHost::placement_for(SurfaceRole::Bar);

        assert_eq!(placement.width, 0);
        assert_eq!(placement.height, 44);
        assert!(placement.anchor_top);
        assert!(placement.anchor_left);
        assert!(placement.anchor_right);
    }

    #[test]
    fn panel_is_right_aligned_and_top_anchored() {
        let placement = LayerShellHost::placement_for(SurfaceRole::Panel);

        assert_eq!(placement.width, 320);
        assert_eq!(placement.height, 220);
        assert!(placement.anchor_top);
        assert!(!placement.anchor_left);
        assert!(placement.anchor_right);
    }

    #[test]
    fn ffi_bar_placement_matches_native_bar_placement() {
        let placement = alice_layer_shell_bar_placement();
        assert_eq!(placement.width, 0);
        assert_eq!(placement.height, 44);
        assert!(placement.anchor_top);
    }
}
