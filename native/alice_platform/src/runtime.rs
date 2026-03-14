//! Tokio async runtime: drives all event subscriptions and snapshot streaming.

use std::sync::{Mutex, OnceLock};

use crate::frb_generated::StreamSink;
use tokio::sync::mpsc;

use crate::api::PanelCommand;
use crate::state::BarSnapshot;

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

    rt.block_on(async {
        let (tx, mut rx) = mpsc::channel::<Trigger>(32);

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

        // Initial snapshot immediately
        let _ = tx.send(Trigger::Event).await;

        // Main loop with 50 ms debounce
        while let Some(_) = rx.recv().await {
            tokio::time::sleep(tokio::time::Duration::from_millis(50)).await;
            while rx.try_recv().is_ok() {}

            let snapshot = build_snapshot();
            if sink.add(snapshot).is_err() {
                break;
            }
        }
    });
}

fn build_snapshot() -> BarSnapshot {
    use crate::clock::LocalClockProvider;
    use crate::mpris::MprisMediaProvider;
    use crate::network::SysNetworkProvider;
    use crate::providers::{
        ClockProvider, MediaProvider, NetworkProvider, StatsProvider, TrayProvider,
        WorkspaceProvider,
    };
    use crate::state::{ClockSnapshot, NetworkKind, NetworkSnapshot};
    use crate::stats::ProcStatsProvider;
    use crate::sway::SwayWorkspaceProvider;
    use crate::tray::StatusNotifierTrayProvider;

    let workspaces = SwayWorkspaceProvider::new()
        .read_workspaces()
        .unwrap_or_default();
    let media = MprisMediaProvider::new().read_media().unwrap_or(None);
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
    let stats = ProcStatsProvider::new()
        .read_stats()
        .unwrap_or(crate::providers::Stats {
            memory_usage_percent: 0.0,
            cpu_usage_cores: 0.0,
        });

    BarSnapshot {
        workspaces,
        media,
        memory_usage_percent: stats.memory_usage_percent,
        cpu_usage_cores: stats.cpu_usage_cores,
        network,
        clock,
        tray_items,
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
