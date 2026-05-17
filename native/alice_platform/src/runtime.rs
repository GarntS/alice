//! Tokio async runtime: drives all event subscriptions and snapshot streaming.

use std::sync::{Arc, Mutex, OnceLock};

use crate::frb_generated::StreamSink;
use tokio::sync::mpsc;

use crate::api::PanelCommand;
use crate::state::BarSnapshot;

// ---------------------------------------------------------------------------
// Shared tokio handle (used by sync API helpers to spawn async tasks)
// ---------------------------------------------------------------------------

static TOKIO_HANDLE: OnceLock<tokio::runtime::Handle> = OnceLock::new();

pub(crate) fn tokio_handle() -> Option<tokio::runtime::Handle> {
    TOKIO_HANDLE.get().cloned()
}

// ---------------------------------------------------------------------------
// Panel command sink (panel process only)
// ---------------------------------------------------------------------------

static PANEL_SINK: OnceLock<Mutex<Option<StreamSink<Option<PanelCommand>>>>> = OnceLock::new();

pub fn set_panel_command_sink(sink: StreamSink<Option<PanelCommand>>) {
    let cell = PANEL_SINK.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = cell.lock() {
        *guard = Some(sink);
    }
}

pub fn push_panel_show(
    panel_id: String,
    view_id: i64,
    include_icon_bytes: bool,
    anchor_x: f64,
    anchor_y: f64,
    width: f64,
    height: f64,
) {
    if let Some(cell) = PANEL_SINK.get() {
        if let Ok(guard) = cell.lock() {
            if let Some(sink) = guard.as_ref() {
                let _ = sink.add(Some(PanelCommand {
                    panel_id,
                    view_id,
                    include_icon_bytes,
                    anchor_x,
                    anchor_y,
                    width,
                    height,
                }));
            }
        }
    }
}

pub fn push_panel_hide() {
    if let Some(cell) = PANEL_SINK.get() {
        if let Ok(guard) = cell.lock() {
            if let Some(sink) = guard.as_ref() {
                let _ = sink.add(None);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Snapshot streaming
// ---------------------------------------------------------------------------

pub enum Trigger {
    Event,
}

pub fn start_bar_snapshot_stream(sink: StreamSink<BarSnapshot>) {
    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(error) => {
            eprintln!("alice: failed to create tokio runtime: {error}");
            return;
        }
    };

    let _ = TOKIO_HANDLE.set(rt.handle().clone());

    let config = crate::load_native_config();

    rt.block_on(async {
        let (tx, mut rx) = mpsc::channel::<Trigger>(32);
        let mpris_cache = crate::mpris::MprisCache::new();
        crate::mpris::MprisCache::install_global(mpris_cache.clone());

        // --- 1 s stats timer ---
        let tx_stats = tx.clone();
        tokio::spawn(async move {
            let mut interval =
                tokio::time::interval(tokio::time::Duration::from_secs(1));
            loop {
                interval.tick().await;
                if tx_stats.send(Trigger::Event).await.is_err() {
                    break;
                }
            }
        });

        // --- 30 s clock timer ---
        let tx_clock = tx.clone();
        tokio::spawn(async move {
            let mut interval =
                tokio::time::interval(tokio::time::Duration::from_secs(30));
            loop {
                interval.tick().await;
                if tx_clock.send(Trigger::Event).await.is_err() {
                    break;
                }
            }
        });

        // --- Sway workspace events (blocking subscription in thread pool) ---
        let tx_sway = tx.clone();
        tokio::task::spawn_blocking(move || {
            sway_event_watcher(tx_sway);
        });

        // --- Network change watcher (notify / inotify) ---
        let tx_net = tx.clone();
        std::thread::Builder::new()
            .name("alice-net-watcher".into())
            .spawn(move || network_watcher(tx_net))
            .ok();

        // --- SNI watcher (async zbus service) ---
        let tx_sni = tx.clone();
        tokio::spawn(async move {
            if let Err(error) = crate::tray::run_status_notifier_watcher(tx_sni).await {
                eprintln!("alice: SNI watcher error: {error}");
            }
        });

        // --- Freedesktop notifications server (async zbus service) ---
        let tx_notif = tx.clone();
        let notif_timeout_ms = config.notifications.default_timeout_ms;
        tokio::spawn(async move {
            if let Err(error) =
                crate::notifications::run_notification_server(tx_notif, notif_timeout_ms).await
            {
                eprintln!("alice: notification server error: {error}");
            }
        });

        // --- MPRIS lifecycle/property watcher and position refresh ---
        let tx_mpris = tx.clone();
        let mpris_watcher_cache = mpris_cache.clone();
        tokio::spawn(async move {
            if let Err(error) = crate::mpris::run_mpris_runtime_service(mpris_watcher_cache, tx_mpris).await {
                eprintln!("alice: MPRIS watcher error: {error:?}");
            }
        });

        let tx_mpris_position = tx.clone();
        let mpris_position_cache = mpris_cache.clone();
        tokio::spawn(async move {
            crate::mpris::media_position_trigger(mpris_position_cache, tx_mpris_position).await;
        });

        // Initial snapshot immediately
        let _ = tx.send(Trigger::Event).await;

        // Main loop with 50 ms debounce
        while let Some(_) = rx.recv().await {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            while rx.try_recv().is_ok() {}

            let snapshot = build_snapshot(mpris_cache.clone());
            if sink.add(snapshot).is_err() {
                break;
            }
        }
    });
}

fn build_snapshot(mpris_cache: Arc<crate::mpris::MprisCache>) -> BarSnapshot {
    use crate::clock::LocalClockProvider;
    use crate::mpris::CachedMprisMediaProvider;
    use crate::network::SysNetworkProvider;
    use crate::stats::ProcStatsProvider;
    use crate::sway::SwayWorkspaceProvider;
    use crate::tray::StatusNotifierTrayProvider;

    build_snapshot_from_providers(
        &SwayWorkspaceProvider::new(),
        &CachedMprisMediaProvider::new(mpris_cache),
        &ProcStatsProvider::new(),
        &SysNetworkProvider::new(),
        &LocalClockProvider::new(),
        &StatusNotifierTrayProvider::new(),
        notification_snapshots(),
    )
}

fn notification_snapshots() -> Vec<crate::state::NotificationSnapshot> {
    use crate::state::{
        NotificationActionSnapshot, NotificationSnapshot, NotificationUrgency,
    };

    crate::notifications::get_notifications()
        .into_iter()
        .map(|n| NotificationSnapshot {
            id: n.id,
            app_name: n.app_name,
            app_icon: n.app_icon,
            summary: n.summary,
            body: n.body,
            urgency: match n.urgency {
                crate::notifications::Urgency::Low => NotificationUrgency::Low,
                crate::notifications::Urgency::Normal => NotificationUrgency::Normal,
                crate::notifications::Urgency::Critical => NotificationUrgency::Critical,
            },
            actions: n
                .actions
                .into_iter()
                .map(|a| NotificationActionSnapshot {
                    key: a.key,
                    label: a.label,
                })
                .collect(),
            category: n.category,
            is_read: n.is_read,
            received_at_unix_secs: n.received_at_unix_secs,
            image_data: n.image_data,
            image_path: n.image_path,
        })
        .collect()
}

pub(crate) fn build_snapshot_from_providers<W, M, S, N, C, T>(
    workspace_provider: &W,
    media_provider: &M,
    stats_provider: &S,
    network_provider: &N,
    clock_provider: &C,
    tray_provider: &T,
    notifications: Vec<crate::state::NotificationSnapshot>,
) -> BarSnapshot
where
    W: crate::providers::WorkspaceProvider,
    M: crate::providers::MediaProvider,
    S: crate::providers::StatsProvider,
    N: crate::providers::NetworkProvider,
    C: crate::providers::ClockProvider,
    T: crate::providers::TrayProvider,
{
    use crate::state::{ClockSnapshot, NetworkKind, NetworkSnapshot};

    let workspaces = workspace_provider.read_workspaces().unwrap_or_default();
    let media = media_provider.read_media().unwrap_or(None);
    let stats = stats_provider
        .read_stats()
        .unwrap_or(crate::providers::Stats {
            memory_usage_percent: 0.0,
            cpu_usage_cores: 0.0,
        });
    let network = network_provider
        .read_network()
        .unwrap_or(NetworkSnapshot {
            kind: NetworkKind::Disconnected,
            label: "Disconnected".into(),
        });
    let clock = clock_provider.read_clock().unwrap_or(ClockSnapshot {
        time_zone_code: "UTC".into(),
        date_label: "-- ---".into(),
        time_label: "--:--".into(),
    });
    let tray_items = tray_provider.read_tray_items().unwrap_or_default();

    BarSnapshot {
        workspaces,
        media,
        memory_usage_percent: stats.memory_usage_percent,
        cpu_usage_cores: stats.cpu_usage_cores,
        network,
        clock,
        tray_items,
        notifications,
    }
}

fn sway_event_watcher(tx: mpsc::Sender<Trigger>) {
    use swayipc::{Connection, EventType};

    let events = match Connection::new()
        .and_then(|conn| conn.subscribe(&[EventType::Workspace]))
    {
        Ok(events) => events,
        Err(error) => {
            eprintln!("alice: sway event subscription failed: {error}");
            return;
        }
    };

    for _event in events {
        if tx.blocking_send(Trigger::Event).is_err() {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::{
        ClockProvider, MediaProvider, NetworkProvider, Stats, StatsProvider, TrayProvider,
        WorkspaceProvider,
    };
    use crate::state::{
        ClockSnapshot, MediaSnapshot, NetworkKind, NetworkSnapshot, NotificationSnapshot,
        NotificationUrgency, TrayItemSnapshot, WorkspaceSnapshot,
    };
    use crate::PlatformError;

    struct FakeWorkspaceProvider(Result<Vec<WorkspaceSnapshot>, PlatformError>);
    struct FakeMediaProvider(Result<Option<MediaSnapshot>, PlatformError>);
    struct FakeStatsProvider(Result<Stats, PlatformError>);
    struct FakeNetworkProvider(Result<NetworkSnapshot, PlatformError>);
    struct FakeClockProvider(Result<ClockSnapshot, PlatformError>);
    struct FakeTrayProvider(Result<Vec<TrayItemSnapshot>, PlatformError>);

    impl WorkspaceProvider for FakeWorkspaceProvider {
        fn read_workspaces(&self) -> Result<Vec<WorkspaceSnapshot>, PlatformError> {
            self.0.clone()
        }
    }

    impl MediaProvider for FakeMediaProvider {
        fn read_media(&self) -> Result<Option<MediaSnapshot>, PlatformError> {
            self.0.clone()
        }
    }

    impl StatsProvider for FakeStatsProvider {
        fn read_stats(&self) -> Result<Stats, PlatformError> {
            self.0.clone()
        }
    }

    impl NetworkProvider for FakeNetworkProvider {
        fn read_network(&self) -> Result<NetworkSnapshot, PlatformError> {
            self.0.clone()
        }
    }

    impl ClockProvider for FakeClockProvider {
        fn read_clock(&self) -> Result<ClockSnapshot, PlatformError> {
            self.0.clone()
        }
    }

    impl TrayProvider for FakeTrayProvider {
        fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
            self.0.clone()
        }
    }

    fn err<T>() -> Result<T, PlatformError> {
        Err(PlatformError::new("provider failed"))
    }

    fn media() -> MediaSnapshot {
        MediaSnapshot {
            title: "Song".into(),
            artist: "Artist".into(),
            album_title: "Album".into(),
            art_url: "".into(),
            position_label: "0:01".into(),
            length_label: "0:02".into(),
            position_micros: 1_000_000,
            length_micros: 2_000_000,
            is_playing: true,
        }
    }

    #[test]
    fn snapshot_aggregation_uses_fake_provider_values() {
        let notifications = vec![NotificationSnapshot {
            id: 7,
            app_name: "app".into(),
            app_icon: "".into(),
            summary: "summary".into(),
            body: "body".into(),
            urgency: NotificationUrgency::Normal,
            actions: vec![],
            category: None,
            is_read: false,
            received_at_unix_secs: 42,
            image_data: None,
            image_path: None,
        }];

        let snapshot = build_snapshot_from_providers(
            &FakeWorkspaceProvider(Ok(vec![WorkspaceSnapshot {
                label: "1".into(),
                is_focused: true,
                is_visible: true,
            }])),
            &FakeMediaProvider(Ok(Some(media()))),
            &FakeStatsProvider(Ok(Stats {
                memory_usage_percent: 64.0,
                cpu_usage_cores: 1.25,
            })),
            &FakeNetworkProvider(Ok(NetworkSnapshot {
                kind: NetworkKind::Wifi,
                label: "testnet".into(),
            })),
            &FakeClockProvider(Ok(ClockSnapshot {
                time_zone_code: "UTC".into(),
                date_label: "16 May".into(),
                time_label: "12:34".into(),
            })),
            &FakeTrayProvider(Ok(vec![TrayItemSnapshot {
                id: "tray".into(),
                label: "Tray".into(),
                service_name: "org.example.Tray".into(),
                object_path: "/StatusNotifierItem".into(),
                icon_png_bytes: None,
            }])),
            notifications.clone(),
        );

        assert_eq!(snapshot.workspaces.len(), 1);
        assert_eq!(snapshot.media, Some(media()));
        assert_eq!(snapshot.memory_usage_percent, 64.0);
        assert_eq!(snapshot.cpu_usage_cores, 1.25);
        assert_eq!(snapshot.network.label, "testnet");
        assert_eq!(snapshot.clock.time_label, "12:34");
        assert_eq!(snapshot.tray_items.len(), 1);
        assert_eq!(snapshot.notifications, notifications);
    }

    #[test]
    fn snapshot_aggregation_falls_back_when_fake_providers_fail() {
        let snapshot = build_snapshot_from_providers(
            &FakeWorkspaceProvider(err()),
            &FakeMediaProvider(err()),
            &FakeStatsProvider(err()),
            &FakeNetworkProvider(err()),
            &FakeClockProvider(err()),
            &FakeTrayProvider(err()),
            vec![],
        );

        assert!(snapshot.workspaces.is_empty());
        assert_eq!(snapshot.media, None);
        assert_eq!(snapshot.memory_usage_percent, 0.0);
        assert_eq!(snapshot.cpu_usage_cores, 0.0);
        assert_eq!(snapshot.network.kind, NetworkKind::Disconnected);
        assert_eq!(snapshot.network.label, "Disconnected");
        assert_eq!(snapshot.clock.time_zone_code, "UTC");
        assert_eq!(snapshot.clock.date_label, "-- ---");
        assert_eq!(snapshot.clock.time_label, "--:--");
        assert!(snapshot.tray_items.is_empty());
        assert!(snapshot.notifications.is_empty());
    }
}

fn network_watcher(tx: mpsc::Sender<Trigger>) {
    use notify::{RecursiveMode, Watcher};
    use std::path::Path;
    use std::sync::mpsc as std_mpsc;

    let (watch_tx, watch_rx) = std_mpsc::channel();
    let mut watcher = match notify::recommended_watcher(move |res: notify::Result<_>| {
        let _ = watch_tx.send(res);
    }) {
        Ok(w) => w,
        Err(error) => {
            eprintln!("alice: network watcher creation failed: {error}");
            return;
        }
    };

    if let Err(error) =
        watcher.watch(Path::new("/sys/class/net"), RecursiveMode::NonRecursive)
    {
        eprintln!("alice: failed to watch /sys/class/net: {error}");
        return;
    }

    for _event in watch_rx.iter() {
        if tx.blocking_send(Trigger::Event).is_err() {
            break;
        }
    }
}
