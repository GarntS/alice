//! Public API exposed to Dart via flutter_rust_bridge.
//!
//! Run `flutter_rust_bridge_codegen generate` after modifying this file to
//! regenerate `frb_generated.rs` and the Dart bindings in `lib/rust_gen/`.

pub use crate::config::{
    CalendarConfig, NotificationConfig, PowerCommandConfig, ThemeMode, TimeZoneConfig,
    WeatherConfig,
};

/// Secret-free configuration contract returned to Flutter.
pub struct AliceUiConfig {
    pub theme_mode: ThemeMode,
    pub accent_color: String,
    pub transparent_top_bar: bool,
    pub show_network_label: bool,
    pub max_visible_tray_items: u32,
    pub local_time_zone_label: Option<String>,
    pub time_zones: Vec<TimeZoneConfig>,
    pub power_commands: PowerCommandConfig,
    pub panel_top_gap_px: u32,
    pub calendar: Option<CalendarConfig>,
    pub caldav: Option<CalDavUiConfig>,
    pub notifications: NotificationConfig,
    pub weather: WeatherConfig,
}

/// Non-secret CalDAV settings needed to decide whether and how to render UI.
pub struct CalDavUiConfig {
    pub principal_url: String,
    pub allow_http: bool,
    pub username: String,
    pub collection_hrefs: Vec<String>,
    pub poll_interval_secs: u32,
    pub ca_certificate_path: Option<String>,
}

impl From<crate::config::AliceConfig> for AliceUiConfig {
    fn from(config: crate::config::AliceConfig) -> Self {
        let caldav = config
            .caldav
            .as_ref()
            .and_then(|value| value.validated_for_runtime().ok())
            .map(|value| CalDavUiConfig {
                principal_url: value.principal_url.to_string(),
                allow_http: value.allow_http,
                username: value.username,
                collection_hrefs: value.collection_urls.into_iter().map(Into::into).collect(),
                poll_interval_secs: value.poll_interval_secs,
                ca_certificate_path: value
                    .ca_certificate_path
                    .map(|path| path.to_string_lossy().into_owned()),
            });

        Self {
            theme_mode: config.theme_mode,
            accent_color: config.accent_color,
            transparent_top_bar: config.transparent_top_bar,
            show_network_label: config.show_network_label,
            max_visible_tray_items: config.max_visible_tray_items,
            local_time_zone_label: config.local_time_zone_label,
            time_zones: config.time_zones,
            power_commands: config.power_commands,
            panel_top_gap_px: config.panel_top_gap_px,
            calendar: config.calendar,
            caldav,
            notifications: config.notifications,
            weather: config.weather,
        }
    }
}
pub use crate::caldav::{
    CalDavFreshness, CalDavSyncState, NormalizedTask, TaskPriority, TaskResourceIdentity,
    TaskStatus,
};
pub use crate::state::{
    BarSnapshot, CalendarEvent, CalendarFetchResult, ClockSnapshot, MediaSnapshot, NetworkKind,
    NetworkSnapshot, NotificationActionSnapshot, NotificationSnapshot, NotificationUrgency,
    TrayItemSnapshot, WeatherAlert, WeatherDay, WeatherPoint, WeatherSnapshot, WorkspaceSnapshot,
};

/// Called once at process startup via FRB's `executeRustInitializers`.
/// Installs ring as the default rustls CryptoProvider so that any
/// subsequent TLS calls (e.g. hyper-rustls in the calendar module) do
/// not panic in `get_default_or_install_from_crate_features`.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Ignore Err — means another component already installed a provider,
    // which is fine.
    let _ = rustls::crypto::ring::default_provider().install_default();
}

/// A command forwarded to Dart via `watch_panel_commands` whenever a panel
/// should be shown. `view_id` identifies the Flutter view to render into.
pub struct PanelCommand {
    pub panel_id: String,
    pub view_id: i64,
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

/// Register the Dart-side sink for panel show/hide commands.
///
/// The C++ showPanel/hidePanel MethodChannel handler calls
/// `alice_notify_panel_show` / `alice_notify_panel_hide` (see `lib.rs`),
/// which push to this sink.
pub fn watch_panel_commands(
    sink: crate::frb_generated::StreamSink<Option<PanelCommand>>,
) -> anyhow::Result<()> {
    crate::runtime::set_panel_command_sink(sink);
    Ok(())
}

/// Load the user's config file (or defaults if missing / unreadable).
pub fn load_config() -> anyhow::Result<AliceUiConfig> {
    Ok(crate::load_native_config().into())
}

/// Coalesce a panel-open or manual CalDAV refresh into the runtime service.
pub fn request_caldav_refresh() -> anyhow::Result<bool> {
    Ok(crate::caldav::service::request_global_refresh())
}

/// Complete or un-complete a stable CalDAV task resource identity.
pub async fn set_caldav_task_completed(
    identity: TaskResourceIdentity,
    completed: bool,
) -> anyhow::Result<()> {
    crate::caldav::service::mutate_global_task(identity, completed)
        .await
        .map_err(|error| anyhow::anyhow!(error.to_string()))
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

/// Remove a single notification by ID and trigger a snapshot update.
///
/// Emits the `NotificationClosed` D-Bus signal with reason 2 (dismissed by user).
pub fn dismiss_notification(id: u32) -> anyhow::Result<()> {
    crate::notifications::dismiss_notification_by_id(id);
    Ok(())
}

/// Remove all notifications and trigger a snapshot update.
pub fn dismiss_all_notifications() -> anyhow::Result<()> {
    crate::notifications::dismiss_all_notifications_impl();
    Ok(())
}

/// Mark a notification as read and trigger a snapshot update.
///
/// Use this when the notification panel opens so the unread badge count updates.
pub fn mark_notification_read(id: u32) -> anyhow::Result<()> {
    crate::notifications::mark_notification_read_impl(id);
    Ok(())
}

/// Emit the `ActionInvoked` D-Bus signal for a notification action button.
///
/// This notifies the originating application that the user clicked an action.
pub fn invoke_notification_action(id: u32, action_key: String) -> anyhow::Result<()> {
    crate::notifications::invoke_action_impl(id, action_key);
    Ok(())
}

/// Fetch Google Calendar events for the given date (`"YYYY-MM-DD"`).
///
/// Returns immediately. On first call without a stored token this initiates
/// a device-flow: `status == "needs_auth"` with `auth_url` / `auth_code`.
/// Subsequent calls while the user is completing auth return `status ==
/// "polling"`. Once authorised, `status == "ready"` with the events list.
/// If calendar is not configured in the user's config, returns
/// `status == "not_configured"` and the events section stays hidden.
pub fn fetch_calendar_events(date: String) -> CalendarFetchResult {
    let config = crate::load_native_config();
    match config.calendar {
        None => CalendarFetchResult {
            status: "not_configured".into(),
            ..Default::default()
        },
        Some(cal_config) => crate::calendar::fetch_events(&date, &cal_config),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flutter_config_contains_only_valid_non_secret_caldav_settings() {
        let native = crate::config::AliceConfig::from_yaml_str(
            r##"
caldav:
  principal_url: https://tasks.example.test/dav/principals/alice/
  allow_http: false
  username: alice
  token: never-cross-the-bridge
  collection_hrefs: [/dav/calendars/alice/work/]
  poll_interval_secs: 75
  ca_certificate_path: /etc/alice/ca.pem
"##,
        )
        .unwrap();
        let ui = AliceUiConfig::from(native);
        let caldav = ui.caldav.expect("valid CalDAV config should enable UI");

        assert_eq!(caldav.username, "alice");
        assert!(!caldav.allow_http);
        assert_eq!(caldav.poll_interval_secs, 75);
        assert_eq!(
            caldav.collection_hrefs,
            ["https://tasks.example.test/dav/calendars/alice/work/"]
        );
        assert_eq!(
            caldav.ca_certificate_path.as_deref(),
            Some("/etc/alice/ca.pem")
        );

        let invalid = crate::config::AliceConfig::from_yaml_str("caldav: {}\n").unwrap();
        assert!(AliceUiConfig::from(invalid).caldav.is_none());
    }
}
