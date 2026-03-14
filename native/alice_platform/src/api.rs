//! Public API exposed to Dart via flutter_rust_bridge.
//!
//! Run `flutter_rust_bridge_codegen generate` after modifying this file to
//! regenerate `frb_generated.rs` and the Dart bindings in `lib/rust_gen/`.

pub use crate::config::{AliceConfig, PowerCommandConfig, ThemeMode, TimeZoneConfig};
pub use crate::state::{
    BarSnapshot, ClockSnapshot, MediaSnapshot, NetworkKind, NetworkSnapshot, TrayItemSnapshot,
    WorkspaceSnapshot,
};

/// A command sent from the bar process to the panel process over the Unix socket,
/// forwarded to Dart via `watch_panel_commands`.
pub struct PanelCommand {
    pub panel_id: String,
    pub include_icon_bytes: bool,
    pub anchor_x: f64,
    pub anchor_y: f64,
    pub width: f64,
    pub height: f64,
}

/// Start streaming `BarSnapshot` values to Dart.
///
/// Dart subscribes once; Rust pushes a new snapshot whenever system state
/// changes (workspaces, media, network, tray, stats, clock).
pub fn watch_bar_snapshots(
    sink: crate::frb_generated::StreamSink<BarSnapshot>,
) -> anyhow::Result<()> {
    std::thread::Builder::new()
        .name("alice-snapshot-stream".into())
        .spawn(move || {
            crate::runtime::start_bar_snapshot_stream(sink);
        })?;
    Ok(())
}

/// Register the Dart-side sink for panel show/hide commands (panel process only).
///
/// The panel process's C++ socket listener calls `alice_notify_panel_show` /
/// `alice_notify_panel_hide` (see `lib.rs`), which push to this sink.
pub fn watch_panel_commands(
    sink: crate::frb_generated::StreamSink<Option<PanelCommand>>,
) -> anyhow::Result<()> {
    crate::runtime::set_panel_command_sink(sink);
    Ok(())
}

/// Load the user's config file (or defaults if missing / unreadable).
pub fn load_config() -> anyhow::Result<AliceConfig> {
    Ok(crate::load_native_config())
}

/// Send an MPRIS media control action: `"previous"`, `"playPause"`, or `"next"`.
pub fn send_media_action(action: String) -> anyhow::Result<bool> {
    use crate::mpris::{MediaControlAction, send_media_action as do_send};
    let parsed = match action.as_str() {
        "previous" => MediaControlAction::Previous,
        "playPause" => MediaControlAction::PlayPause,
        "next" => MediaControlAction::Next,
        _ => return Ok(false),
    };
    Ok(do_send(parsed).is_ok())
}

/// Seek the active MPRIS player to the given absolute position in microseconds.
pub fn seek_media(position_micros: i64) -> anyhow::Result<bool> {
    Ok(crate::mpris::seek_to_position(position_micros).is_ok())
}

/// Focus the sway workspace with the given label.
pub fn focus_workspace(label: String) -> anyhow::Result<bool> {
    Ok(crate::sway::focus_workspace(&label).is_ok())
}

/// Send a StatusNotifier tray action (`"activate"`, `"secondaryActivate"`, `"contextMenu"`).
pub fn send_tray_action(
    service_name: String,
    object_path: String,
    action: String,
    x: i32,
    y: i32,
) -> anyhow::Result<bool> {
    use crate::tray::{TrayItemAction, send_tray_action as do_send};
    let parsed = match action.as_str() {
        "activate" => TrayItemAction::Activate,
        "secondaryActivate" => TrayItemAction::SecondaryActivate,
        "contextMenu" => TrayItemAction::ContextMenu,
        _ => return Ok(false),
    };
    Ok(do_send(&service_name, &object_path, parsed, x, y).is_ok())
}

/// Execute a power management action: `"lock"`, `"lockAndSuspend"`, `"restart"`, `"poweroff"`.
///
/// Reads the configured shell command from the user's config and runs it via `/bin/sh -c`.
pub fn execute_power_action(action: String) -> anyhow::Result<bool> {
    let config = crate::load_native_config();
    let command = match action.as_str() {
        "lock" => config.power_commands.lock,
        "lockAndSuspend" => config.power_commands.lock_and_suspend,
        "restart" => config.power_commands.restart,
        "poweroff" => config.power_commands.poweroff,
        _ => return Ok(false),
    };
    if command.trim().is_empty() {
        return Ok(false);
    }
    Ok(std::process::Command::new("/bin/sh")
        .arg("-c")
        .arg(&command)
        .spawn()
        .is_ok())
}
