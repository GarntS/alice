use crate::{state::{ClockSnapshot, MediaSnapshot, NetworkSnapshot, TrayItemSnapshot, WorkspaceSnapshot}, PlatformError};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stats {
    pub memory_usage_percent: f64,
    pub cpu_usage_cores: f64,
}

pub trait WorkspaceProvider {
    fn read_workspaces(&self) -> Result<Vec<WorkspaceSnapshot>, PlatformError>;
}

pub trait MediaProvider {
    fn read_media(&self) -> Result<Option<MediaSnapshot>, PlatformError>;
}

pub trait StatsProvider {
    fn read_stats(&self) -> Result<Stats, PlatformError>;
}

pub trait NetworkProvider {
    fn read_network(&self) -> Result<NetworkSnapshot, PlatformError>;
}

pub trait ClockProvider {
    fn read_clock(&self) -> Result<ClockSnapshot, PlatformError>;
}

pub trait TrayProvider {
    fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, PlatformError>;
}
