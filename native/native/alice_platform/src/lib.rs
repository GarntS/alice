//! Native platform service boundary for Alice.
//!
//! This crate will aggregate Linux data providers such as sway IPC, MPRIS,
//! network status, and system statistics behind a UI-facing API.

pub mod providers;
pub mod state;

use providers::{ClockProvider, MediaProvider, NetworkProvider, StatsProvider, TrayProvider, WorkspaceProvider};
use state::BarSnapshot;

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
    /// Creates a new platform service from individual providers.
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

    /// Reads a point-in-time snapshot from each provider.
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
}
