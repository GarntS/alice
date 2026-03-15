use std::{
    collections::{HashMap, HashSet},
    fs,
    sync::{Arc, Mutex, OnceLock},
};

use tokio::sync::mpsc;
use zbus::blocking::{Connection, Proxy};

use crate::{PlatformError, providers::TrayProvider, state::TrayItemSnapshot};

const DBUS_SERVICE: &str = "org.freedesktop.DBus";
const DBUS_PATH: &str = "/org/freedesktop/DBus";
const DBUS_INTERFACE: &str = "org.freedesktop.DBus";
const KDE_SNI_PREFIX: &str = "org.kde.StatusNotifierItem";
const FREEDESKTOP_SNI_PREFIX: &str = "org.freedesktop.StatusNotifierItem";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const WATCHER_BUS_NAME_KDE: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_BUS_NAME_FREEDESKTOP: &str = "org.freedesktop.StatusNotifierWatcher";
const WATCHER_INTERFACE_KDE: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_INTERFACE_FREEDESKTOP: &str = "org.freedesktop.StatusNotifierWatcher";
const ITEM_INTERFACE_KDE: &str = "org.kde.StatusNotifierItem";
const ITEM_INTERFACE_FREEDESKTOP: &str = "org.freedesktop.StatusNotifierItem";
const DEFAULT_ITEM_PATH: &str = "/StatusNotifierItem";
const AYATANA_SNI_PATH_PREFIX: &str = "/org/ayatana/NotificationItem/";

const TRAY_ICON_SIZE_PX: u32 = 16;

// ---------------------------------------------------------------------------
// Public tray action type
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayItemAction {
    Activate,
    SecondaryActivate,
    ContextMenu,
}

// ---------------------------------------------------------------------------
// Shared SNI watcher state (used by both the watcher service and the trigger)
// ---------------------------------------------------------------------------

#[derive(Default)]
struct WatcherState {
    registered_items: HashSet<String>,
    host_registered: bool,
}

static SNI_WATCHER_STATE: OnceLock<Arc<Mutex<WatcherState>>> = OnceLock::new();

fn sni_watcher_state() -> Arc<Mutex<WatcherState>> {
    SNI_WATCHER_STATE
        .get_or_init(|| Arc::new(Mutex::new(WatcherState::default())))
        .clone()
}

// ---------------------------------------------------------------------------
// Async SNI watcher D-Bus service
// ---------------------------------------------------------------------------

struct KdeSniWatcher {
    state: Arc<Mutex<WatcherState>>,
    trigger: mpsc::Sender<crate::runtime::Trigger>,
}

struct FreedesktopSniWatcher {
    state: Arc<Mutex<WatcherState>>,
    trigger: mpsc::Sender<crate::runtime::Trigger>,
}

fn canonical_sni_item_id(sender: Option<&str>, service_or_path: &str) -> Option<String> {
    let s = service_or_path.trim();
    if s.is_empty() {
        return None;
    }
    if s.starts_with('/') {
        let sender = sender?.trim();
        if sender.is_empty() {
            return None;
        }
        return Some(format!("{sender}{s}"));
    }
    if s.contains('/') {
        return Some(s.to_string());
    }
    Some(format!("{s}{DEFAULT_ITEM_PATH}"))
}

async fn handle_register_item(
    state: &Arc<Mutex<WatcherState>>,
    trigger: &mpsc::Sender<crate::runtime::Trigger>,
    sender: Option<&str>,
    service_or_path: &str,
) {
    if let Some(id) = canonical_sni_item_id(sender, service_or_path) {
        let added = state
            .lock()
            .map(|mut s| s.registered_items.insert(id))
            .unwrap_or(false);
        if added {
            let _ = trigger.send(crate::runtime::Trigger::Event).await;
        }
    }
}

async fn handle_register_host(
    state: &Arc<Mutex<WatcherState>>,
    trigger: &mpsc::Sender<crate::runtime::Trigger>,
) {
    let changed = state
        .lock()
        .map(|mut s| {
            if !s.host_registered {
                s.host_registered = true;
                true
            } else {
                false
            }
        })
        .unwrap_or(false);
    if changed {
        let _ = trigger.send(crate::runtime::Trigger::Event).await;
    }
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl KdeSniWatcher {
    async fn register_status_notifier_item(
        &self,
        service_or_path: &str,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<()> {
        let sender = header.sender().map(|s| s.to_string());
        handle_register_item(&self.state, &self.trigger, sender.as_deref(), service_or_path)
            .await;
        Ok(())
    }

    async fn register_status_notifier_host(&self, _service: &str) -> zbus::fdo::Result<()> {
        handle_register_host(&self.state, &self.trigger).await;
        Ok(())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.state
            .lock()
            .map(|s| {
                let mut items: Vec<String> = s.registered_items.iter().cloned().collect();
                items.sort();
                items
            })
            .unwrap_or_default()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        self.state
            .lock()
            .map(|s| s.host_registered)
            .unwrap_or(false)
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;
}

#[zbus::interface(name = "org.freedesktop.StatusNotifierWatcher")]
impl FreedesktopSniWatcher {
    async fn register_status_notifier_item(
        &self,
        service_or_path: &str,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> zbus::fdo::Result<()> {
        let sender = header.sender().map(|s| s.to_string());
        handle_register_item(&self.state, &self.trigger, sender.as_deref(), service_or_path)
            .await;
        Ok(())
    }

    async fn register_status_notifier_host(&self, _service: &str) -> zbus::fdo::Result<()> {
        handle_register_host(&self.state, &self.trigger).await;
        Ok(())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.state
            .lock()
            .map(|s| {
                let mut items: Vec<String> = s.registered_items.iter().cloned().collect();
                items.sort();
                items
            })
            .unwrap_or_default()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        self.state
            .lock()
            .map(|s| s.host_registered)
            .unwrap_or(false)
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_unregistered(
        emitter: &zbus::object_server::SignalEmitter<'_>,
    ) -> zbus::Result<()>;
}

/// Run the StatusNotifierWatcher D-Bus service on both KDE and Freedesktop bus names.
///
/// Should be spawned as a tokio task inside the bar-process runtime.
pub async fn run_status_notifier_watcher(
    trigger: mpsc::Sender<crate::runtime::Trigger>,
) -> zbus::Result<()> {
    let state = sni_watcher_state();

    let conn = zbus::connection::Builder::session()?
        .build()
        .await?;

    conn.object_server()
        .at(
            WATCHER_PATH,
            KdeSniWatcher {
                state: state.clone(),
                trigger: trigger.clone(),
            },
        )
        .await?;

    conn.object_server()
        .at(
            WATCHER_PATH,
            FreedesktopSniWatcher {
                state: state.clone(),
                trigger,
            },
        )
        .await?;

    conn.request_name(WATCHER_BUS_NAME_KDE).await?;
    conn.request_name(WATCHER_BUS_NAME_FREEDESKTOP).await?;

    // Keep the watcher alive; resolved items accumulate until the runtime stops.
    std::future::pending::<()>().await;
    Ok(())
}

// ---------------------------------------------------------------------------
// Tray item ref & cache
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
struct StatusNotifierItemRef {
    service_name: String,
    object_path: String,
}

pub struct StatusNotifierTrayProvider;

impl StatusNotifierTrayProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_from_connection(
        connection: &Connection,
    ) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
        let item_refs = registered_items_from_watcher(connection)
            .or_else(|_| fallback_items_from_bus(connection))
            .unwrap_or_default();

        let mut tray_items = Vec::new();
        let mut seen_cache_keys = HashSet::new();
        for item_ref in item_refs {
            let cache_key = tray_item_cache_key(&item_ref);
            seen_cache_keys.insert(cache_key.clone());

            if let Some(cached) = cached_tray_item(&cache_key) {
                tray_items.push(cached);
                continue;
            }

            if let Some(item) = read_item_snapshot(connection, &item_ref)? {
                store_cached_tray_item(&cache_key, &item);
                tray_items.push(item);
            }
        }
        prune_cached_tray_items(&seen_cache_keys);

        Ok(tray_items)
    }
}

impl TrayProvider for StatusNotifierTrayProvider {
    fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
        let connection = Connection::session().map_err(|error| {
            PlatformError::new(format!("failed to connect to session bus: {error}"))
        })?;
        Self::read_from_connection(&connection)
    }
}

pub fn send_tray_action(
    service_name: &str,
    object_path: &str,
    action: TrayItemAction,
    x: i32,
    y: i32,
) -> Result<(), PlatformError> {
    let service_name = service_name.trim();
    let object_path = object_path.trim();
    if service_name.is_empty() {
        return Err(PlatformError::new("tray service name is empty"));
    }
    if object_path.is_empty() {
        return Err(PlatformError::new("tray object path is empty"));
    }

    let connection = Connection::session().map_err(|error| {
        PlatformError::new(format!("failed to connect to session bus: {error}"))
    })?;
    let method_name = match action {
        TrayItemAction::Activate => "Activate",
        TrayItemAction::SecondaryActivate => "SecondaryActivate",
        TrayItemAction::ContextMenu => "ContextMenu",
    };

    let interfaces = [ITEM_INTERFACE_KDE, ITEM_INTERFACE_FREEDESKTOP];
    for interface in interfaces {
        let proxy = match Proxy::new(&connection, service_name, object_path, interface) {
            Ok(proxy) => proxy,
            Err(_) => continue,
        };

        if proxy.call_noreply(method_name, &(x, y)).is_ok() {
            return Ok(());
        }
    }

    Err(PlatformError::new(format!(
        "failed to send tray action '{method_name}'"
    )))
}

// ---------------------------------------------------------------------------
// Watcher queries
// ---------------------------------------------------------------------------

fn registered_items_from_watcher(
    connection: &Connection,
) -> Result<Vec<StatusNotifierItemRef>, PlatformError> {
    let watchers = [
        (WATCHER_BUS_NAME_KDE, WATCHER_INTERFACE_KDE),
        (WATCHER_BUS_NAME_FREEDESKTOP, WATCHER_INTERFACE_FREEDESKTOP),
    ];

    for (bus_name, interface_name) in watchers {
        if let Ok(items) =
            registered_items_from_single_watcher(connection, bus_name, interface_name)
            && !items.is_empty()
        {
            return Ok(items);
        }
    }

    Err(PlatformError::new(
        "no StatusNotifierWatcher registrations found",
    ))
}

fn registered_items_from_single_watcher(
    connection: &Connection,
    watcher_bus_name: &str,
    watcher_interface: &str,
) -> Result<Vec<StatusNotifierItemRef>, PlatformError> {
    let proxy = Proxy::new(
        connection,
        watcher_bus_name,
        WATCHER_PATH,
        watcher_interface,
    )
    .map_err(|error| {
        PlatformError::new(format!(
            "failed to create watcher proxy '{watcher_bus_name}': {error}"
        ))
    })?;
    let registered: Vec<String> = proxy
        .get_property("RegisteredStatusNotifierItems")
        .map_err(|error| {
            PlatformError::new(format!(
                "failed to read RegisteredStatusNotifierItems from '{watcher_bus_name}': {error}"
            ))
        })?;

    let mut parsed = Vec::new();
    for item in registered {
        if let Some(item_ref) = parse_item_identifier(&item, None) {
            parsed.push(item_ref);
        }
    }
    Ok(parsed)
}

fn fallback_items_from_bus(
    connection: &Connection,
) -> Result<Vec<StatusNotifierItemRef>, PlatformError> {
    let proxy = Proxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE)
        .map_err(|error| PlatformError::new(format!("failed to create DBus proxy: {error}")))?;
    let names: Vec<String> = proxy
        .call("ListNames", &())
        .map_err(|error| PlatformError::new(format!("failed to list DBus names: {error}")))?;

    Ok(filter_status_notifier_names(&names)
        .into_iter()
        .map(|service_name| StatusNotifierItemRef {
            service_name,
            object_path: DEFAULT_ITEM_PATH.into(),
        })
        .collect())
}

// ---------------------------------------------------------------------------
// Item snapshot reading
// ---------------------------------------------------------------------------

fn read_item_snapshot(
    connection: &Connection,
    item_ref: &StatusNotifierItemRef,
) -> Result<Option<TrayItemSnapshot>, PlatformError> {
    let proxy = match item_proxy(connection, item_ref) {
        Some(proxy) => proxy,
        None => return Ok(None),
    };

    let service_name = item_ref.service_name.clone();
    let title = read_item_text_property(&proxy, "Title");
    let item_id = read_item_text_property(&proxy, "Id")
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| service_name.clone());
    let status = read_item_text_property(&proxy, "Status");
    let icon_name = select_icon_name(
        read_item_text_property(&proxy, "IconName"),
        read_item_text_property(&proxy, "AttentionIconName"),
        status.as_deref(),
    );
    let icon_theme_path = read_item_text_property(&proxy, "IconThemePath");
    let process_name = connection_process_name(connection, &service_name);

    let label = title
        .filter(|value| !value.is_empty())
        .or_else(|| humanize_status_notifier_identifier(&item_id))
        .or_else(|| {
            process_name
                .as_deref()
                .and_then(humanize_status_notifier_identifier)
        })
        .unwrap_or_else(|| simplify_status_notifier_label(&service_name));

    let icon_png_bytes =
        read_sni_icon_png(connection, &item_ref.service_name, &item_ref.object_path)
            .or_else(|| {
                let name = if !icon_name.is_empty() {
                    icon_name.as_str()
                } else {
                    ayatana_icon_name_from_path(&item_ref.object_path)?
                };
                resolve_icon_name_to_png(name, icon_theme_path.as_deref())
            });

    Ok(Some(TrayItemSnapshot {
        id: item_id,
        label,
        service_name: item_ref.service_name.clone(),
        object_path: item_ref.object_path.clone(),
        icon_png_bytes,
    }))
}

fn item_proxy<'a>(
    connection: &'a Connection,
    item_ref: &'a StatusNotifierItemRef,
) -> Option<Proxy<'a>> {
    let interfaces = [ITEM_INTERFACE_KDE, ITEM_INTERFACE_FREEDESKTOP];
    for interface in interfaces {
        if let Ok(proxy) = Proxy::new(
            connection,
            item_ref.service_name.as_str(),
            item_ref.object_path.as_str(),
            interface,
        ) {
            return Some(proxy);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// PNG encoding from SNI IconPixmap (ARGB → RGBA → PNG via `image` crate)
// ---------------------------------------------------------------------------

fn read_sni_icon_png(
    connection: &Connection,
    service_name: &str,
    object_path: &str,
) -> Option<Vec<u8>> {
    for interface in [ITEM_INTERFACE_KDE, ITEM_INTERFACE_FREEDESKTOP] {
        if let Some(png) =
            try_read_sni_icon_png_for_interface(connection, service_name, object_path, interface)
        {
            return Some(png);
        }
    }
    None
}

fn try_read_sni_icon_png_for_interface(
    connection: &Connection,
    service_name: &str,
    object_path: &str,
    interface: &str,
) -> Option<Vec<u8>> {
    let proxy = Proxy::new(connection, service_name, object_path, interface).ok()?;

    // a(iiay) — array of (width, height, argb_bytes)
    let pixmaps: Vec<(i32, i32, Vec<u8>)> = proxy.get_property("IconPixmap").ok()?;

    let best = pixmaps
        .into_iter()
        .filter(|(w, h, _)| *w > 0 && *h > 0)
        .max_by_key(|(w, h, _)| (w * h) as i64)?;

    argb_pixmap_to_png(best.0 as u32, best.1 as u32, &best.2)
}

fn argb_pixmap_to_png(width: u32, height: u32, argb_data: &[u8]) -> Option<Vec<u8>> {
    use image::{DynamicImage, RgbaImage};

    let expected = (width * height * 4) as usize;
    if argb_data.len() < expected || width == 0 || height == 0 {
        return None;
    }

    // Convert ARGB (D-Bus network byte order, big-endian within each pixel)
    // to RGBA as expected by the image crate.
    let mut rgba = Vec::with_capacity(expected);
    for chunk in argb_data[..expected].chunks_exact(4) {
        let a = chunk[0];
        let r = chunk[1];
        let g = chunk[2];
        let b = chunk[3];
        rgba.extend_from_slice(&[r, g, b, a]);
    }

    let img = RgbaImage::from_raw(width, height, rgba)?;
    let dynamic = DynamicImage::ImageRgba8(img);

    let dynamic = if width != TRAY_ICON_SIZE_PX || height != TRAY_ICON_SIZE_PX {
        dynamic.resize(
            TRAY_ICON_SIZE_PX,
            TRAY_ICON_SIZE_PX,
            image::imageops::FilterType::Lanczos3,
        )
    } else {
        dynamic
    };

    let mut buf = Vec::new();
    dynamic
        .write_to(
            &mut std::io::Cursor::new(&mut buf),
            image::ImageFormat::Png,
        )
        .ok()?;

    Some(buf)
}

// ---------------------------------------------------------------------------
// Ayatana / libappindicator path → icon name
// ---------------------------------------------------------------------------

fn ayatana_icon_name_from_path(object_path: &str) -> Option<&str> {
    let name = object_path.strip_prefix(AYATANA_SNI_PATH_PREFIX)?;
    // Guard against sub-paths like /org/ayatana/NotificationItem/steam/Menu
    if name.is_empty() || name.contains('/') {
        return None;
    }
    Some(name)
}

// ---------------------------------------------------------------------------
// XDG icon theme filesystem lookup (no GTK required)
// ---------------------------------------------------------------------------

fn resolve_icon_name_to_png(icon_name: &str, icon_theme_path: Option<&str>) -> Option<Vec<u8>> {
    // 1. IconThemePath set by the item itself (e.g. Steam bundles its own icons).
    //    Items may store icons flat in this directory without hicolor subdirectories.
    if let Some(theme_path) = icon_theme_path {
        const SIZES: &[u32] = &[256, 128, 64, 48, 32, 22, 16];
        // Flat: {IconThemePath}/{icon_name}.png
        let flat = std::path::Path::new(theme_path).join(format!("{icon_name}.png"));
        if let Some(bytes) = load_and_scale_png(&flat) {
            return Some(bytes);
        }
        // hicolor subdirs inside IconThemePath
        for &size in SIZES {
            let path = std::path::Path::new(theme_path)
                .join(format!("hicolor/{size}x{size}/apps/{icon_name}.png"));
            if let Some(bytes) = load_and_scale_png(&path) {
                return Some(bytes);
            }
        }
    }

    // 2. System XDG icon theme (hicolor).
    const SIZES: &[u32] = &[256, 128, 64, 48, 32, 22, 16];
    for base in &xdg_icon_base_dirs() {
        for &size in SIZES {
            let path = base.join(format!("hicolor/{size}x{size}/apps/{icon_name}.png"));
            if let Some(bytes) = load_and_scale_png(&path) {
                return Some(bytes);
            }
        }
    }

    // 3. /usr/share/pixmaps fallback.
    for dir in ["/usr/share/pixmaps", "/usr/local/share/pixmaps"] {
        let path = std::path::Path::new(dir).join(format!("{icon_name}.png"));
        if let Some(bytes) = load_and_scale_png(&path) {
            return Some(bytes);
        }
    }

    None
}

fn xdg_icon_base_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(home) = std::env::var("HOME") {
        dirs.push(std::path::PathBuf::from(home).join(".local/share/icons"));
    }
    let data_dirs = std::env::var("XDG_DATA_DIRS")
        .unwrap_or_else(|_| "/usr/local/share:/usr/share".to_string());
    for dir in data_dirs.split(':') {
        if !dir.is_empty() {
            dirs.push(std::path::PathBuf::from(dir).join("icons"));
        }
    }
    dirs
}

fn load_and_scale_png(path: &std::path::Path) -> Option<Vec<u8>> {
    let raw = fs::read(path).ok()?;
    let img = image::load_from_memory_with_format(&raw, image::ImageFormat::Png).ok()?;
    let scaled = if img.width() == TRAY_ICON_SIZE_PX && img.height() == TRAY_ICON_SIZE_PX {
        img
    } else {
        img.resize(
            TRAY_ICON_SIZE_PX,
            TRAY_ICON_SIZE_PX,
            image::imageops::FilterType::Lanczos3,
        )
    };
    let mut buf = Vec::new();
    scaled
        .write_to(
            &mut std::io::Cursor::new(&mut buf),
            image::ImageFormat::Png,
        )
        .ok()?;
    Some(buf)
}

// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------

fn tray_item_cache() -> &'static Mutex<HashMap<String, TrayItemSnapshot>> {
    static CACHE: OnceLock<Mutex<HashMap<String, TrayItemSnapshot>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn tray_item_cache_key(item_ref: &StatusNotifierItemRef) -> String {
    format!("{}{}", item_ref.service_name, item_ref.object_path)
}

fn cached_tray_item(cache_key: &str) -> Option<TrayItemSnapshot> {
    let cache = tray_item_cache().lock().ok()?;
    cache.get(cache_key).cloned()
}

fn store_cached_tray_item(cache_key: &str, item: &TrayItemSnapshot) {
    if let Ok(mut cache) = tray_item_cache().lock() {
        cache.insert(cache_key.to_string(), item.clone());
    }
}

fn prune_cached_tray_items(seen_cache_keys: &HashSet<String>) {
    if let Ok(mut cache) = tray_item_cache().lock() {
        cache.retain(|key, _| seen_cache_keys.contains(key));
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn read_item_text_property(proxy: &Proxy<'_>, name: &str) -> Option<String> {
    let value: String = proxy.get_property(name).ok()?;
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn select_icon_name(
    icon_name: Option<String>,
    attention_icon_name: Option<String>,
    status: Option<&str>,
) -> String {
    let wants_attention = matches!(status, Some("NeedsAttention"));
    if wants_attention && let Some(attention_icon_name) = attention_icon_name {
        return attention_icon_name;
    }
    icon_name.unwrap_or_default()
}

fn parse_item_identifier(
    identifier: &str,
    sender_service: Option<&str>,
) -> Option<StatusNotifierItemRef> {
    let identifier = identifier.trim();
    if identifier.is_empty() {
        return None;
    }

    if identifier.starts_with('/') {
        let sender = sender_service?.trim();
        if sender.is_empty() {
            return None;
        }
        return Some(StatusNotifierItemRef {
            service_name: sender.to_string(),
            object_path: identifier.to_string(),
        });
    }

    if let Some(slash_index) = identifier.find('/') {
        if slash_index > 0 {
            let service_name = identifier[..slash_index].trim();
            let object_path = &identifier[slash_index..];
            if !service_name.is_empty() && !object_path.is_empty() {
                return Some(StatusNotifierItemRef {
                    service_name: service_name.to_string(),
                    object_path: object_path.to_string(),
                });
            }
        }
    }

    Some(StatusNotifierItemRef {
        service_name: identifier.to_string(),
        object_path: DEFAULT_ITEM_PATH.to_string(),
    })
}

fn filter_status_notifier_names(names: &[String]) -> Vec<String> {
    let mut filtered = names
        .iter()
        .filter(|name| {
            name.starts_with(KDE_SNI_PREFIX) || name.starts_with(FREEDESKTOP_SNI_PREFIX)
        })
        .cloned()
        .collect::<Vec<_>>();
    filtered.sort();
    filtered
}

fn simplify_status_notifier_label(name: &str) -> String {
    let suffix = name
        .strip_prefix(KDE_SNI_PREFIX)
        .or_else(|| name.strip_prefix(FREEDESKTOP_SNI_PREFIX))
        .unwrap_or(name)
        .trim_start_matches('.');

    if suffix.is_empty() {
        return "Tray Item".into();
    }

    suffix
        .split(['-', '.', '_'])
        .filter(|segment| !segment.is_empty())
        .map(|segment| {
            let mut chars = segment.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn humanize_status_notifier_identifier(identifier: &str) -> Option<String> {
    let trimmed = identifier.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.starts_with(':') {
        return None;
    }

    let base = trimmed.rsplit('.').next().unwrap_or(trimmed);
    let normalized = base.replace('-', " ").replace('_', " ");
    if normalized.is_empty() {
        return None;
    }

    let label = normalized
        .split_whitespace()
        .filter(|segment| !segment.is_empty())
        .map(|segment| {
            let mut chars = segment.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ");
    if label.is_empty() { None } else { Some(label) }
}

fn connection_process_name(connection: &Connection, service_name: &str) -> Option<String> {
    if !service_name.starts_with(':') {
        return None;
    }

    let dbus = Proxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE).ok()?;
    let pid: u32 = dbus
        .call("GetConnectionUnixProcessID", &(service_name))
        .ok()?;
    read_process_name(pid)
}

fn read_process_name(pid: u32) -> Option<String> {
    let path = format!("/proc/{pid}/comm");
    let name = fs::read_to_string(path).ok()?;
    let trimmed = name.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::{
        DEFAULT_ITEM_PATH, TrayItemAction, argb_pixmap_to_png, filter_status_notifier_names,
        humanize_status_notifier_identifier, parse_item_identifier, select_icon_name,
        simplify_status_notifier_label,
    };

    #[test]
    fn filters_status_notifier_services() {
        let names = vec![
            "org.freedesktop.DBus".to_string(),
            "org.kde.StatusNotifierItem-1-1".to_string(),
            "org.freedesktop.StatusNotifierItem.discord".to_string(),
        ];

        let filtered = filter_status_notifier_names(&names);
        assert_eq!(filtered.len(), 2);
        assert!(filtered.contains(&"org.kde.StatusNotifierItem-1-1".to_string()));
        assert!(filtered.contains(&"org.freedesktop.StatusNotifierItem.discord".to_string()));
    }

    #[test]
    fn simplifies_service_name_to_human_label() {
        assert_eq!(
            simplify_status_notifier_label("org.freedesktop.StatusNotifierItem.discord"),
            "Discord"
        );
        assert_eq!(
            simplify_status_notifier_label("org.kde.StatusNotifierItem-nm_applet-1"),
            "Nm Applet 1"
        );
    }

    #[test]
    fn parses_registered_item_identifier_with_path() {
        let parsed =
            parse_item_identifier("org.kde.StatusNotifierItem-2-1/StatusNotifierItem", None)
                .expect("item should parse");

        assert_eq!(parsed.service_name, "org.kde.StatusNotifierItem-2-1");
        assert_eq!(parsed.object_path, "/StatusNotifierItem");
    }

    #[test]
    fn parses_registered_item_identifier_without_path() {
        let parsed = parse_item_identifier("org.kde.StatusNotifierItem-2-1", None)
            .expect("item should parse");

        assert_eq!(parsed.service_name, "org.kde.StatusNotifierItem-2-1");
        assert_eq!(parsed.object_path, DEFAULT_ITEM_PATH);
    }

    #[test]
    fn parses_registered_item_identifier_as_object_path() {
        let parsed =
            parse_item_identifier("/StatusNotifierItem", Some(":1.42")).expect("item should parse");

        assert_eq!(parsed.service_name, ":1.42");
        assert_eq!(parsed.object_path, "/StatusNotifierItem");
    }

    #[test]
    fn prefers_attention_icon_when_item_needs_attention() {
        let _icon_name = select_icon_name(
            Some("normal-icon".into()),
            Some("attention-icon".into()),
            Some("NeedsAttention"),
        );
        assert_eq!(icon_name, "attention-icon");

        let normal = select_icon_name(
            Some("normal-icon".into()),
            Some("attention-icon".into()),
            Some("Active"),
        );
        assert_eq!(normal, "normal-icon");
    }

    #[test]
    fn tray_item_action_variants_exist() {
        let _ = TrayItemAction::Activate;
        let _ = TrayItemAction::SecondaryActivate;
        let _ = TrayItemAction::ContextMenu;
    }

    #[test]
    fn humanizes_item_identifier_to_label() {
        assert_eq!(
            humanize_status_notifier_identifier("discord").as_deref(),
            Some("Discord")
        );
        assert_eq!(
            humanize_status_notifier_identifier("com.discordapp.Discord").as_deref(),
            Some("Discord")
        );
        assert_eq!(humanize_status_notifier_identifier(":1.22"), None);
    }

    #[test]
    fn argb_pixmap_converts_to_png() {
        // 1×1 white pixel in ARGB format
        let argb = &[0xFFu8, 0xFF, 0xFF, 0xFF];
        let png = argb_pixmap_to_png(1, 1, argb);
        assert!(png.is_some());
        let bytes = png.unwrap();
        // PNG magic bytes
        assert_eq!(&bytes[0..4], &[0x89, 0x50, 0x4E, 0x47]);
    }

    #[test]
    fn argb_pixmap_returns_none_for_bad_input() {
        assert!(argb_pixmap_to_png(0, 0, &[]).is_none());
        assert!(argb_pixmap_to_png(2, 2, &[0xFF; 4]).is_none()); // too small
    }
}
