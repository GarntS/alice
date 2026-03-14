//! Native platform library for Alice.
//!
//! This crate is consumed in two ways:
//!
//! 1. Via `flutter_rust_bridge` — the generated bridge code in
//!    `frb_generated.rs` calls the public functions in `api.rs` from Dart.
//!    Run `flutter_rust_bridge_codegen generate` to (re)produce that file.
//!
//! 2. Via two thin `extern "C"` functions used by the C++ panel-process socket
//!    listener to forward show/hide events into the Dart `StreamSink`.

pub mod api;
pub mod clock;
pub mod config;
pub mod mpris;
pub mod network;
pub mod providers;
pub mod runtime;
pub mod state;
pub mod stats;
pub mod sway;
pub mod tray;

// frb_generated.rs is produced by `flutter_rust_bridge_codegen generate`.
mod frb_generated;

use std::ffi::CStr;
use std::os::raw::c_char;

use config::AliceConfig;

// ---------------------------------------------------------------------------
// Shared error type (imported as `crate::PlatformError` throughout modules)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlatformError {
    message: String,
}

impl PlatformError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

pub(crate) fn load_native_config() -> AliceConfig {
    match config::default_config_path().and_then(|path| AliceConfig::load_or_create_default(&path))
    {
        Ok(config) => config,
        Err(_) => AliceConfig::default(),
    }
}

// ---------------------------------------------------------------------------
// C FFI — panel process socket bridge
//
// Called from `on_panel_socket_incoming` in alice_application.cc (panel side)
// after the C++ code has parsed the show/hide socket message and updated the
// GTK window geometry. These functions forward the command into the Dart-side
// `StreamSink<Option<PanelCommand>>` registered by `watch_panel_commands`.
// ---------------------------------------------------------------------------

/// Notify the Dart panel that it should show the given panel type.
///
/// # Safety
/// `panel_id` must be a valid, null-terminated C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_notify_panel_show(
    panel_id: *const c_char,
    include_icon_bytes: bool,
    anchor_x: f64,
    anchor_y: f64,
    width: f64,
    height: f64,
) {
    if panel_id.is_null() {
        return;
    }
    let id = match unsafe { CStr::from_ptr(panel_id) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return,
    };
    runtime::push_panel_show(id, include_icon_bytes, anchor_x, anchor_y, width, height);
}

/// Notify the Dart panel that it should hide.
#[unsafe(no_mangle)]
pub extern "C" fn alice_notify_panel_hide() {
    runtime::push_panel_hide();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::{
        ClockProvider, MediaProvider, NetworkProvider, Stats, StatsProvider, TrayProvider,
        WorkspaceProvider,
    };
    use crate::state::{
        ClockSnapshot, MediaSnapshot, NetworkKind, NetworkSnapshot, TrayItemSnapshot,
        WorkspaceSnapshot,
    };

    struct StubWorkspaceProvider;
    struct StubMediaProvider;
    struct StubStatsProvider;
    struct StubNetworkProvider;
    struct StubClockProvider;
    struct StubTrayProvider;

    impl WorkspaceProvider for StubWorkspaceProvider {
        fn read_workspaces(&self) -> Result<Vec<WorkspaceSnapshot>, crate::PlatformError> {
            Ok(vec![WorkspaceSnapshot {
                label: "1".into(),
                is_focused: true,
                is_visible: true,
            }])
        }
    }
    impl MediaProvider for StubMediaProvider {
        fn read_media(&self) -> Result<Option<MediaSnapshot>, crate::PlatformError> {
            Ok(Some(MediaSnapshot {
                title: "Song".into(),
                artist: "Artist".into(),
                album_title: "Album".into(),
                art_url: "".into(),
                position_label: "0:10".into(),
                length_label: "1:00".into(),
                is_playing: true,
            }))
        }
    }
    impl StatsProvider for StubStatsProvider {
        fn read_stats(&self) -> Result<Stats, crate::PlatformError> {
            Ok(Stats {
                memory_usage_percent: 42.0,
                cpu_usage_cores: 1.5,
            })
        }
    }
    impl NetworkProvider for StubNetworkProvider {
        fn read_network(&self) -> Result<NetworkSnapshot, crate::PlatformError> {
            Ok(NetworkSnapshot {
                kind: NetworkKind::Wifi,
                label: "testnet".into(),
            })
        }
    }
    impl ClockProvider for StubClockProvider {
        fn read_clock(&self) -> Result<ClockSnapshot, crate::PlatformError> {
            Ok(ClockSnapshot {
                time_zone_code: "UTC".into(),
                date_label: "09 Mar".into(),
                time_label: "13:37".into(),
            })
        }
    }
    impl TrayProvider for StubTrayProvider {
        fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, crate::PlatformError> {
            Ok(vec![TrayItemSnapshot {
                id: "discord".into(),
                label: "Discord".into(),
                service_name: "org.kde.StatusNotifierItem.discord".into(),
                object_path: "/StatusNotifierItem".into(),
                icon_png_bytes: None,
            }])
        }
    }

    #[test]
    fn load_native_config_succeeds() {
        let config = load_native_config();
        assert_eq!(config.accent_color, "#4C956C");
    }
}
