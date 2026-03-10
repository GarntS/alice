//! Native platform service boundary for Alice.
//!
//! This crate aggregates Linux data providers such as sway IPC, MPRIS,
//! network status, and system statistics behind a UI-facing API.

pub mod clock;
pub mod config;
pub mod mpris;
pub mod network;
pub mod providers;
pub mod state;
pub mod stats;
pub mod sway;
pub mod tray;

use std::ffi::{CString, c_char};
use std::ptr;

use clock::LocalClockProvider;
use config::{AliceConfig, PowerCommandConfig, ThemeMode, TimeZoneConfig};
use mpris::{MediaControlAction, MprisMediaProvider, send_media_action};
use network::SysNetworkProvider;
use providers::{
    ClockProvider, MediaProvider, NetworkProvider, StatsProvider, TrayProvider, WorkspaceProvider,
};
use state::{
    BarSnapshot, ClockSnapshot, MediaSnapshot, NetworkKind, NetworkSnapshot, WorkspaceSnapshot,
};
use stats::ProcStatsProvider;
use sway::SwayWorkspaceProvider;
use tray::StatusNotifierTrayProvider;

/// Aggregates provider implementations into a single snapshot-oriented service.
pub struct AlicePlatformService<W, M, S, N, C, T> {
    workspace_provider: W,
    media_provider: M,
    stats_provider: S,
    network_provider: N,
    clock_provider: C,
    tray_provider: T,
}

impl<W, M, S, N, C, T> AlicePlatformService<W, M, S, N, C, T>
where
    W: WorkspaceProvider,
    M: MediaProvider,
    S: StatsProvider,
    N: NetworkProvider,
    C: ClockProvider,
    T: TrayProvider,
{
    pub fn new(
        workspace_provider: W,
        media_provider: M,
        stats_provider: S,
        network_provider: N,
        clock_provider: C,
        tray_provider: T,
    ) -> Self {
        Self {
            workspace_provider,
            media_provider,
            stats_provider,
            network_provider,
            clock_provider,
            tray_provider,
        }
    }

    pub fn snapshot(&self) -> Result<BarSnapshot, PlatformError> {
        let stats = self.stats_provider.read_stats()?;

        Ok(BarSnapshot {
            workspaces: self.workspace_provider.read_workspaces()?,
            media: self.media_provider.read_media()?,
            memory_usage_percent: stats.memory_usage_percent,
            cpu_usage_cores: stats.cpu_usage_cores,
            network: self.network_provider.read_network()?,
            clock: self.clock_provider.read_clock()?,
            tray_items: self.tray_provider.read_tray_items()?,
        })
    }
}

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

fn parse_media_action(action: &str) -> Option<MediaControlAction> {
    match action {
        "previous" => Some(MediaControlAction::Previous),
        "playPause" => Some(MediaControlAction::PlayPause),
        "next" => Some(MediaControlAction::Next),
        _ => None,
    }
}

fn load_native_config() -> AliceConfig {
    match config::default_config_path().and_then(|path| AliceConfig::load_or_create_default(&path))
    {
        Ok(config) => config,
        Err(_) => AliceConfig::default(),
    }
}

#[repr(C)]
pub struct AliceTimeZoneFFI {
    pub label: *mut c_char,
    pub offset_hours: i32,
}

impl From<TimeZoneConfig> for AliceTimeZoneFFI {
    fn from(value: TimeZoneConfig) -> Self {
        Self {
            label: string_into_raw(value.label),
            offset_hours: value.offset_hours,
        }
    }
}

#[repr(C)]
pub struct AlicePowerCommandsFFI {
    pub lock: *mut c_char,
    pub lock_and_suspend: *mut c_char,
    pub restart: *mut c_char,
    pub poweroff: *mut c_char,
}

impl From<PowerCommandConfig> for AlicePowerCommandsFFI {
    fn from(value: PowerCommandConfig) -> Self {
        Self {
            lock: string_into_raw(value.lock),
            lock_and_suspend: string_into_raw(value.lock_and_suspend),
            restart: string_into_raw(value.restart),
            poweroff: string_into_raw(value.poweroff),
        }
    }
}

#[repr(C)]
pub struct AliceConfigFFI {
    pub theme_mode: u8,
    pub accent_color: *mut c_char,
    pub show_network_label: bool,
    pub max_visible_tray_items: u32,
    pub time_zones: *mut AliceTimeZoneFFI,
    pub time_zone_count: usize,
    pub power_commands: AlicePowerCommandsFFI,
}

impl From<AliceConfig> for AliceConfigFFI {
    fn from(value: AliceConfig) -> Self {
        let time_zones: Vec<AliceTimeZoneFFI> =
            value.time_zones.into_iter().map(Into::into).collect();
        let (time_zones_ptr, time_zone_count) = vec_into_raw(time_zones);

        Self {
            theme_mode: match value.theme_mode {
                ThemeMode::System => 0,
                ThemeMode::Light => 1,
                ThemeMode::Dark => 2,
            },
            accent_color: string_into_raw(value.accent_color),
            show_network_label: value.show_network_label,
            max_visible_tray_items: value.max_visible_tray_items,
            time_zones: time_zones_ptr,
            time_zone_count,
            power_commands: value.power_commands.into(),
        }
    }
}

#[repr(C)]
pub struct WorkspaceFFI {
    pub label: *mut c_char,
    pub is_focused: bool,
    pub is_visible: bool,
}

impl From<WorkspaceSnapshot> for WorkspaceFFI {
    fn from(value: WorkspaceSnapshot) -> Self {
        Self {
            label: string_into_raw(value.label),
            is_focused: value.is_focused,
            is_visible: value.is_visible,
        }
    }
}

#[repr(C)]
pub struct MediaFFI {
    pub title: *mut c_char,
    pub artist: *mut c_char,
    pub position_label: *mut c_char,
    pub length_label: *mut c_char,
    pub is_playing: bool,
}

impl From<MediaSnapshot> for MediaFFI {
    fn from(value: MediaSnapshot) -> Self {
        Self {
            title: string_into_raw(value.title),
            artist: string_into_raw(value.artist),
            position_label: string_into_raw(value.position_label),
            length_label: string_into_raw(value.length_label),
            is_playing: value.is_playing,
        }
    }
}

#[repr(C)]
pub struct NetworkFFI {
    pub kind: u8,
    pub label: *mut c_char,
}

impl From<NetworkSnapshot> for NetworkFFI {
    fn from(value: NetworkSnapshot) -> Self {
        Self {
            kind: match value.kind {
                NetworkKind::Wifi => 0,
                NetworkKind::Wired => 1,
                NetworkKind::Disconnected => 2,
            },
            label: string_into_raw(value.label),
        }
    }
}

#[repr(C)]
pub struct ClockFFI {
    pub time_zone_code: *mut c_char,
    pub date_label: *mut c_char,
    pub time_label: *mut c_char,
}

impl From<ClockSnapshot> for ClockFFI {
    fn from(value: ClockSnapshot) -> Self {
        Self {
            time_zone_code: string_into_raw(value.time_zone_code),
            date_label: string_into_raw(value.date_label),
            time_label: string_into_raw(value.time_label),
        }
    }
}

#[repr(C)]
pub struct TrayItemFFI {
    pub id: *mut c_char,
    pub label: *mut c_char,
}

impl From<crate::state::TrayItemSnapshot> for TrayItemFFI {
    fn from(value: crate::state::TrayItemSnapshot) -> Self {
        Self {
            id: string_into_raw(value.id),
            label: string_into_raw(value.label),
        }
    }
}

#[repr(C)]
pub struct AliceSnapshotFFI {
    pub workspaces: *mut WorkspaceFFI,
    pub workspace_count: usize,
    pub media: *mut MediaFFI,
    pub network: NetworkFFI,
    pub clock: ClockFFI,
    pub tray_items: *mut TrayItemFFI,
    pub tray_item_count: usize,
    pub memory_usage_percent: f64,
    pub cpu_usage_cores: f64,
}

fn string_into_raw(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new("").expect("empty CString"))
        .into_raw()
}

unsafe fn string_from_raw(value: *mut c_char) {
    if !value.is_null() {
        let _ = unsafe { CString::from_raw(value) };
    }
}

fn vec_into_raw<T>(mut values: Vec<T>) -> (*mut T, usize) {
    let len = values.len();
    let ptr = values.as_mut_ptr();
    std::mem::forget(values);
    (ptr, len)
}

unsafe fn vec_from_raw<T>(ptr: *mut T, len: usize) -> Vec<T> {
    if ptr.is_null() {
        Vec::new()
    } else {
        unsafe { Vec::from_raw_parts(ptr, len, len) }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn alice_platform_load_config() -> *mut AliceConfigFFI {
    Box::into_raw(Box::new(load_native_config().into()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_platform_free_config(config: *mut AliceConfigFFI) {
    if config.is_null() {
        return;
    }

    let config = unsafe { Box::from_raw(config) };
    unsafe { string_from_raw(config.accent_color) };
    let time_zones = unsafe { vec_from_raw(config.time_zones, config.time_zone_count) };
    for time_zone in time_zones {
        unsafe { string_from_raw(time_zone.label) };
    }
    unsafe { string_from_raw(config.power_commands.lock) };
    unsafe { string_from_raw(config.power_commands.lock_and_suspend) };
    unsafe { string_from_raw(config.power_commands.restart) };
    unsafe { string_from_raw(config.power_commands.poweroff) };
}

#[unsafe(no_mangle)]
pub extern "C" fn alice_platform_read_snapshot() -> *mut AliceSnapshotFFI {
    let workspace_provider = SwayWorkspaceProvider::new();
    let media_provider = MprisMediaProvider::new();
    let stats_provider = ProcStatsProvider::new();

    let workspaces = workspace_provider.read_workspaces().unwrap_or_default();
    let media = media_provider.read_media().unwrap_or(None);
    let network = SysNetworkProvider::new()
        .read_network()
        .unwrap_or(NetworkSnapshot {
            kind: NetworkKind::Disconnected,
            label: "Disconnected".into(),
        });
    let clock = LocalClockProvider::new()
        .read_clock()
        .unwrap_or(ClockSnapshot {
            time_zone_code: "UTC".into(),
            date_label: "-- ---".into(),
            time_label: "--:--".into(),
        });
    let tray_items = StatusNotifierTrayProvider::new()
        .read_tray_items()
        .unwrap_or_default();
    let stats = stats_provider.read_stats().unwrap_or(providers::Stats {
        memory_usage_percent: 0.0,
        cpu_usage_cores: 0.0,
    });

    let (workspaces_ptr, workspace_count) = vec_into_raw(
        workspaces
            .into_iter()
            .map(WorkspaceFFI::from)
            .collect::<Vec<_>>(),
    );

    let (tray_items_ptr, tray_item_count) = vec_into_raw(
        tray_items
            .into_iter()
            .map(TrayItemFFI::from)
            .collect::<Vec<_>>(),
    );

    Box::into_raw(Box::new(AliceSnapshotFFI {
        workspaces: workspaces_ptr,
        workspace_count,
        media: media
            .map(MediaFFI::from)
            .map(Box::new)
            .map(Box::into_raw)
            .unwrap_or(ptr::null_mut()),
        network: network.into(),
        clock: clock.into(),
        tray_items: tray_items_ptr,
        tray_item_count,
        memory_usage_percent: stats.memory_usage_percent,
        cpu_usage_cores: stats.cpu_usage_cores,
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_platform_free_snapshot(snapshot: *mut AliceSnapshotFFI) {
    if snapshot.is_null() {
        return;
    }

    let snapshot = unsafe { Box::from_raw(snapshot) };
    let workspaces = unsafe { vec_from_raw(snapshot.workspaces, snapshot.workspace_count) };
    for workspace in workspaces {
        unsafe { string_from_raw(workspace.label) };
    }

    if !snapshot.media.is_null() {
        let media = unsafe { Box::from_raw(snapshot.media) };
        unsafe { string_from_raw(media.title) };
        unsafe { string_from_raw(media.artist) };
        unsafe { string_from_raw(media.position_label) };
        unsafe { string_from_raw(media.length_label) };
    }
    unsafe { string_from_raw(snapshot.network.label) };
    unsafe { string_from_raw(snapshot.clock.time_zone_code) };
    unsafe { string_from_raw(snapshot.clock.date_label) };
    unsafe { string_from_raw(snapshot.clock.time_label) };
    let tray_items = unsafe { vec_from_raw(snapshot.tray_items, snapshot.tray_item_count) };
    for tray_item in tray_items {
        unsafe { string_from_raw(tray_item.id) };
        unsafe { string_from_raw(tray_item.label) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn alice_platform_send_media_action(action: *const c_char) -> bool {
    if action.is_null() {
        return false;
    }

    let action = match unsafe { std::ffi::CStr::from_ptr(action) }.to_str() {
        Ok(action) => action,
        Err(_) => return false,
    };
    let Some(action) = parse_media_action(action) else {
        return false;
    };

    send_media_action(action).is_ok()
}

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
        fn read_workspaces(&self) -> Result<Vec<WorkspaceSnapshot>, PlatformError> {
            Ok(vec![WorkspaceSnapshot {
                label: "1".into(),
                is_focused: true,
                is_visible: true,
            }])
        }
    }
    impl MediaProvider for StubMediaProvider {
        fn read_media(&self) -> Result<Option<MediaSnapshot>, PlatformError> {
            Ok(Some(MediaSnapshot {
                title: "Song".into(),
                artist: "Artist".into(),
                position_label: "0:10".into(),
                length_label: "1:00".into(),
                is_playing: true,
            }))
        }
    }
    impl StatsProvider for StubStatsProvider {
        fn read_stats(&self) -> Result<Stats, PlatformError> {
            Ok(Stats {
                memory_usage_percent: 42.0,
                cpu_usage_cores: 1.5,
            })
        }
    }
    impl NetworkProvider for StubNetworkProvider {
        fn read_network(&self) -> Result<NetworkSnapshot, PlatformError> {
            Ok(NetworkSnapshot {
                kind: NetworkKind::Wifi,
                label: "testnet".into(),
            })
        }
    }
    impl ClockProvider for StubClockProvider {
        fn read_clock(&self) -> Result<ClockSnapshot, PlatformError> {
            Ok(ClockSnapshot {
                time_zone_code: "UTC".into(),
                date_label: "09 Mar".into(),
                time_label: "13:37".into(),
            })
        }
    }
    impl TrayProvider for StubTrayProvider {
        fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
            Ok(vec![TrayItemSnapshot {
                id: "discord".into(),
                label: "Discord".into(),
            }])
        }
    }

    #[test]
    fn combines_provider_output_into_snapshot() {
        let service = AlicePlatformService::new(
            StubWorkspaceProvider,
            StubMediaProvider,
            StubStatsProvider,
            StubNetworkProvider,
            StubClockProvider,
            StubTrayProvider,
        );
        let snapshot = service.snapshot().expect("snapshot should succeed");
        assert_eq!(snapshot.workspaces.len(), 1);
        assert_eq!(snapshot.media.expect("media expected").title, "Song");
        assert_eq!(snapshot.memory_usage_percent, 42.0);
        assert_eq!(snapshot.cpu_usage_cores, 1.5);
        assert_eq!(snapshot.network.label, "testnet");
        assert_eq!(snapshot.tray_items.len(), 1);
    }

    #[test]
    fn ffi_config_allocates() {
        let ptr = alice_platform_load_config();
        assert!(!ptr.is_null());
        unsafe { alice_platform_free_config(ptr) };
    }

    #[test]
    fn ffi_snapshot_allocates() {
        let ptr = alice_platform_read_snapshot();
        assert!(!ptr.is_null());
        unsafe { alice_platform_free_snapshot(ptr) };
    }
}
