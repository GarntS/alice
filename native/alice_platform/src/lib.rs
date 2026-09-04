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
pub mod battery;
pub mod caldav;
pub mod calendar;
pub(crate) mod calendar_sources;
pub mod clock;
pub mod config;
pub mod mpris;
pub mod network;
pub mod notifications;
pub mod providers;
pub mod runtime;
pub mod state;
pub mod stats;
pub mod sway;
pub mod tray;
pub mod weather;

// frb_generated.rs is produced by `flutter_rust_bridge_codegen generate`.
mod foreign_toplevel;
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
    config::default_config_path()
        .and_then(|path| AliceConfig::load_or_create_default(&path))
        .unwrap_or_default()
}

// ---------------------------------------------------------------------------
// C FFI — panel command bridge
//
// Called from the showPanel/hidePanel MethodChannel handler in
// alice_application.cc after the C++ code has created/updated the panel GTK
// window. These functions forward the command into the Dart-side
// `StreamSink<Option<PanelCommand>>` registered by `watch_panel_commands`.
// ---------------------------------------------------------------------------

/// Notify the Dart panel that it should show the given panel type.
///
/// # Safety
/// `panel_id` must be a valid, null-terminated C string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_notify_panel_show(
    panel_id: *const c_char,
    view_id: i64,
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
    runtime::push_panel_show(
        id,
        view_id,
        include_icon_bytes,
        anchor_x,
        anchor_y,
        width,
        height,
    );
}

/// Notify the Dart panel that it should hide.
#[unsafe(no_mangle)]
pub extern "C" fn alice_notify_panel_hide() {
    runtime::push_panel_hide();
}

/// Replace the retained native bar-view snapshot. Called after startup bars
/// have received their Flutter view IDs.
///
/// # Safety
/// When `count` is nonzero, `view_ids` must point to `count` initialized
/// `i64` values that remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_set_bar_view_ids(view_ids: *const i64, count: usize) {
    if view_ids.is_null() && count != 0 {
        return;
    }
    let ids = if count == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(view_ids, count) }.to_vec()
    };
    runtime::set_bar_view_ids(ids);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use crate::config::AliceConfig;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn config_load_test_uses_explicit_temp_path() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be monotonic enough for test")
            .as_nanos();
        let root = std::env::temp_dir().join(format!("alice-lib-config-test-{unique}"));
        let path = root.join("alice/config.yaml");

        let config = AliceConfig::load_or_create_default(&path)
            .expect("config should load from explicit temp path");
        assert_eq!(config.accent_color, "#4C956C");
        assert!(path.exists());

        std::fs::remove_dir_all(root).expect("temp config tree should be removable");
    }
}
