#[derive(Debug, Clone, PartialEq)]
pub struct BarSnapshot {
    pub workspaces: Vec<WorkspaceSnapshot>,
    pub media: Option<MediaSnapshot>,
    pub memory_usage_percent: f64,
    pub cpu_usage_cores: f64,
    pub network: NetworkSnapshot,
    pub clock: ClockSnapshot,
    pub tray_items: Vec<TrayItemSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceSnapshot {
    pub label: String,
    pub is_focused: bool,
    pub is_visible: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MediaSnapshot {
    pub title: String,
    pub artist: String,
    pub album_title: String,
    pub art_url: String,
    pub position_label: String,
    pub length_label: String,
    pub position_micros: i64,
    pub length_micros: i64,
    pub is_playing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetworkSnapshot {
    pub kind: NetworkKind,
    pub label: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkKind {
    Wifi,
    Wired,
    Disconnected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClockSnapshot {
    pub time_zone_code: String,
    pub date_label: String,
    pub time_label: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayItemSnapshot {
    pub id: String,
    pub label: String,
    pub service_name: String,
    pub object_path: String,
    pub icon_png_bytes: Option<Vec<u8>>,
}
