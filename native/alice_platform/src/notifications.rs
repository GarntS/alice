//! Freedesktop desktop notifications server (org.freedesktop.Notifications v1.2).
//!
//! Registers on the session bus as `org.freedesktop.Notifications`, stores
//! incoming notifications in memory, and feeds them into the `BarSnapshot`
//! stream via the shared `Trigger` channel.

use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU32, Ordering},
    },
};

use tokio::sync::mpsc;
use zbus::zvariant::{OwnedValue, Value};

use crate::runtime::Trigger;

const MAX_NOTIFICATION_IMAGE_DIMENSION: u32 = 2048;
const MAX_NOTIFICATION_IMAGE_BYTES: usize = 16 * 1024 * 1024;
const NOTIFICATION_ICON_THUMBNAIL_PX: u32 = 96;

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Urgency {
    Low,
    Normal,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationAction {
    pub key: String,
    pub label: String,
}

#[derive(Debug, Clone)]
pub struct StoredNotification {
    pub id: u32,
    pub app_name: String,
    /// Icon name or file path from the D-Bus call; may be empty.
    pub app_icon: String,
    pub summary: String,
    pub body: String,
    pub urgency: Urgency,
    pub actions: Vec<NotificationAction>,
    pub category: Option<String>,
    pub is_read: bool,
    pub received_at: std::time::Instant,
    pub received_at_unix_secs: u64,
    /// PNG-encoded image bytes from the `image-data` hint, if present.
    pub image_data: Option<Vec<u8>>,
    /// File path or `file://` URI from the `image-path` hint, if present.
    pub image_path: Option<String>,
}

// ---------------------------------------------------------------------------
// In-memory store
// ---------------------------------------------------------------------------

#[derive(Default)]
pub struct NotificationStore {
    notifications: Vec<StoredNotification>,
}

impl NotificationStore {
    fn add_or_replace(&mut self, n: StoredNotification) -> u32 {
        let id = n.id;
        if let Some(pos) = self.notifications.iter().position(|x| x.id == id) {
            self.notifications[pos] = n;
        } else {
            self.notifications.push(n);
        }
        id
    }

    fn remove(&mut self, id: u32) -> bool {
        if let Some(pos) = self.notifications.iter().position(|x| x.id == id) {
            self.notifications.remove(pos);
            true
        } else {
            false
        }
    }

    fn remove_all(&mut self) {
        self.notifications.clear();
    }

    pub fn get_all(&self) -> Vec<StoredNotification> {
        self.notifications.clone()
    }

    pub fn mark_read(&mut self, id: u32) {
        if let Some(n) = self.notifications.iter_mut().find(|x| x.id == id) {
            n.is_read = true;
        }
    }
}

// ---------------------------------------------------------------------------
// Module-level statics (same pattern as calendar's AUTH_STATE)
// ---------------------------------------------------------------------------

static NOTIFICATION_STORE: OnceLock<Arc<Mutex<NotificationStore>>> = OnceLock::new();
static NOTIFICATION_TRIGGER: OnceLock<mpsc::Sender<Trigger>> = OnceLock::new();
static NOTIFICATION_CONNECTION: OnceLock<Arc<zbus::Connection>> = OnceLock::new();

// ---------------------------------------------------------------------------
// D-Bus server
// ---------------------------------------------------------------------------

struct NotificationServer {
    store: Arc<Mutex<NotificationStore>>,
    trigger: mpsc::Sender<Trigger>,
    next_id: Arc<AtomicU32>,
    default_timeout_ms: u32,
    connection: Arc<zbus::Connection>,
}

#[zbus::interface(name = "org.freedesktop.Notifications")]
impl NotificationServer {
    /// Receive a new notification from an application.
    ///
    /// Returns the assigned notification ID (≥ 1).
    async fn notify(
        &self,
        app_name: &str,
        replaces_id: u32,
        app_icon: &str,
        summary: &str,
        body: &str,
        actions: Vec<String>,
        hints: HashMap<String, OwnedValue>,
        expire_timeout: i32,
    ) -> u32 {
        let urgency = parse_urgency(&hints);
        let category = parse_category(&hints);
        let image_data = parse_image_data(&hints);
        let image_path = parse_image_path(&hints);

        // actions vec is [key, label, key, label, ...]
        let parsed_actions: Vec<NotificationAction> = actions
            .chunks(2)
            .filter(|c| c.len() == 2)
            .map(|c| NotificationAction {
                key: c[0].clone(),
                label: c[1].clone(),
            })
            .collect();

        // Reuse replaces_id if the notification still exists; otherwise allocate new.
        let id = if replaces_id > 0 {
            let exists = self
                .store
                .lock()
                .map(|s| s.notifications.iter().any(|n| n.id == replaces_id))
                .unwrap_or(false);
            if exists {
                replaces_id
            } else {
                self.next_id.fetch_add(1, Ordering::SeqCst)
            }
        } else {
            self.next_id.fetch_add(1, Ordering::SeqCst)
        };

        let received_at_unix_secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let notification = StoredNotification {
            id,
            app_name: app_name.to_string(),
            app_icon: app_icon.to_string(),
            summary: summary.to_string(),
            body: body.to_string(),
            urgency,
            actions: parsed_actions,
            category,
            is_read: false,
            received_at: std::time::Instant::now(),
            received_at_unix_secs,
            image_data,
            image_path,
        };

        let _ = expire_timeout;

        if let Ok(mut store) = self.store.lock() {
            store.add_or_replace(notification);
        }

        let _ = self.trigger.send(Trigger::Event).await;
        id
    }

    /// Close a notification on behalf of the sending application.
    async fn close_notification(&self, id: u32) {
        let removed = self
            .store
            .lock()
            .map(|mut s| s.remove(id))
            .unwrap_or(false);
        if removed {
            // reason 3 = closed by CloseNotification D-Bus call
            emit_notification_closed(&self.connection, id, 3).await;
            let _ = self.trigger.send(Trigger::Event).await;
        }
    }

    fn get_capabilities(&self) -> Vec<String> {
        vec!["body".into(), "actions".into(), "persistence".into()]
    }

    fn get_server_information(&self) -> (&str, &str, &str, &str) {
        // (name, vendor, version, spec_version)
        ("alice", "alice", env!("CARGO_PKG_VERSION"), "1.2")
    }

    /// Emitted when a notification is closed for any reason.
    ///
    /// Reason codes: 1=expired, 2=dismissed by user, 3=closed by app, 4=other.
    #[zbus(signal)]
    async fn notification_closed(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        reason: u32,
    ) -> zbus::Result<()>;

    /// Emitted when an action button is invoked by the user.
    #[zbus(signal)]
    async fn action_invoked(
        emitter: &zbus::object_server::SignalEmitter<'_>,
        id: u32,
        action_key: &str,
    ) -> zbus::Result<()>;
}

/// Emit `NotificationClosed` via the interface's signal emitter.
async fn emit_notification_closed(conn: &Arc<zbus::Connection>, id: u32, reason: u32) {
    if let Ok(iface) = conn
        .object_server()
        .interface::<_, NotificationServer>("/org/freedesktop/Notifications")
        .await
    {
        let _ =
            NotificationServer::notification_closed(iface.signal_emitter(), id, reason).await;
    }
}

// ---------------------------------------------------------------------------
// Public runner (spawned in runtime.rs)
// ---------------------------------------------------------------------------

pub async fn run_notification_server(
    trigger: mpsc::Sender<Trigger>,
    default_timeout_ms: u32,
) -> zbus::Result<()> {
    let store = Arc::new(Mutex::new(NotificationStore::default()));
    let next_id = Arc::new(AtomicU32::new(1));

    let conn = zbus::connection::Builder::session()?
        .build()
        .await?;
    let connection = Arc::new(conn);

    let server = NotificationServer {
        store: store.clone(),
        trigger: trigger.clone(),
        next_id,
        default_timeout_ms,
        connection: connection.clone(),
    };

    connection
        .object_server()
        .at("/org/freedesktop/Notifications", server)
        .await?;

    connection
        .request_name("org.freedesktop.Notifications")
        .await?;

    NOTIFICATION_STORE.set(store).ok();
    NOTIFICATION_TRIGGER.set(trigger).ok();
    NOTIFICATION_CONNECTION.set(connection).ok();

    // Keep the server alive until the runtime stops.
    std::future::pending::<()>().await;
    Ok(())
}

// ---------------------------------------------------------------------------
// Public helpers — called from api.rs and runtime.rs
// ---------------------------------------------------------------------------

pub fn get_notifications() -> Vec<StoredNotification> {
    NOTIFICATION_STORE
        .get()
        .and_then(|s| s.lock().ok())
        .map(|s| s.get_all())
        .unwrap_or_default()
}

/// Remove one notification and notify listeners. Emits `NotificationClosed`
/// with reason 2 (dismissed by user).
pub fn dismiss_notification_by_id(id: u32) {
    let removed = NOTIFICATION_STORE
        .get()
        .and_then(|s| s.lock().ok())
        .map(|mut s| s.remove(id))
        .unwrap_or(false);
    if removed {
        spawn_signal_closed(id, 2);
        send_trigger();
    }
}

/// Remove all notifications and notify listeners.
pub fn dismiss_all_notifications_impl() {
    NOTIFICATION_STORE
        .get()
        .and_then(|s| s.lock().ok())
        .map(|mut s| s.remove_all());
    send_trigger();
}

/// Mark a notification as read and trigger a snapshot rebuild.
pub fn mark_notification_read_impl(id: u32) {
    NOTIFICATION_STORE
        .get()
        .and_then(|s| s.lock().ok())
        .map(|mut s| s.mark_read(id));
    send_trigger();
}

/// Emit the `ActionInvoked` signal for the given notification and action key.
pub fn invoke_action_impl(id: u32, action_key: String) {
    if let Some(conn) = NOTIFICATION_CONNECTION.get().cloned() {
        if let Some(handle) = crate::runtime::tokio_handle() {
            handle.spawn(async move {
                if let Ok(iface) = conn
                    .object_server()
                    .interface::<_, NotificationServer>("/org/freedesktop/Notifications")
                    .await
                {
                    let _ = NotificationServer::action_invoked(
                        iface.signal_emitter(),
                        id,
                        &action_key,
                    )
                    .await;
                }
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn spawn_signal_closed(id: u32, reason: u32) {
    if let Some(conn) = NOTIFICATION_CONNECTION.get().cloned() {
        if let Some(handle) = crate::runtime::tokio_handle() {
            handle.spawn(async move {
                emit_notification_closed(&conn, id, reason).await;
            });
        }
    }
}

fn send_trigger() {
    if let Some(tx) = NOTIFICATION_TRIGGER.get() {
        let _ = tx.try_send(Trigger::Event);
    }
}

// ---------------------------------------------------------------------------
// Hint parsing
// ---------------------------------------------------------------------------

fn parse_urgency(hints: &HashMap<String, OwnedValue>) -> Urgency {
    hints
        .get("urgency")
        .and_then(|v| match &**v {
            Value::U8(0) => Some(Urgency::Low),
            Value::U8(2) => Some(Urgency::Critical),
            Value::U8(_) => Some(Urgency::Normal),
            _ => None,
        })
        .unwrap_or(Urgency::Normal)
}

fn parse_category(hints: &HashMap<String, OwnedValue>) -> Option<String> {
    hints.get("category").and_then(|v| match &**v {
        Value::Str(s) => Some(s.to_string()),
        _ => None,
    })
}

fn parse_image_path(hints: &HashMap<String, OwnedValue>) -> Option<String> {
    hints
        .get("image-path")
        .or_else(|| hints.get("image_path"))
        .and_then(|v| match &**v {
            Value::Str(s) => Some(s.to_string()),
            _ => None,
        })
}

fn parse_image_data(hints: &HashMap<String, OwnedValue>) -> Option<Vec<u8>> {
    let v = hints
        .get("image-data")
        .or_else(|| hints.get("icon_data"))?;
    match &**v {
        Value::Structure(s) => encode_image_data_to_png(s),
        _ => None,
    }
}

/// Encode a raw pixel buffer from the `image-data` hint (D-Bus type `(iiibiiay)`)
/// into PNG bytes using the `image` crate.
fn encode_image_data_to_png(s: &zbus::zvariant::Structure<'_>) -> Option<Vec<u8>> {
    use image::{DynamicImage, RgbImage, RgbaImage};

    let fields = s.fields();
    if fields.len() < 7 {
        return None;
    }

    let width = extract_i32(&fields[0])? as u32;
    let height = extract_i32(&fields[1])? as u32;
    let rowstride = extract_i32(&fields[2])? as u32;
    let has_alpha = extract_bool(&fields[3])?;
    let _bits_per_sample = extract_i32(&fields[4])?;
    let channels = extract_i32(&fields[5])? as u32;
    let data = extract_bytes(&fields[6])?;

    if width == 0
        || height == 0
        || width > MAX_NOTIFICATION_IMAGE_DIMENSION
        || height > MAX_NOTIFICATION_IMAGE_DIMENSION
        || data.len() > MAX_NOTIFICATION_IMAGE_BYTES
        || !((has_alpha && channels == 4) || (!has_alpha && channels == 3))
    {
        return None;
    }

    let img: DynamicImage = if has_alpha {
        let mut rgba = Vec::with_capacity((width * height * 4) as usize);
        for row in 0..height {
            let start = (row * rowstride) as usize;
            let end = start + (width * 4) as usize;
            if end > data.len() {
                return None;
            }
            rgba.extend_from_slice(&data[start..end]);
        }
        DynamicImage::ImageRgba8(RgbaImage::from_raw(width, height, rgba)?)
    } else {
        let mut rgb = Vec::with_capacity((width * height * channels) as usize);
        for row in 0..height {
            let start = (row * rowstride) as usize;
            let end = start + (width * channels) as usize;
            if end > data.len() {
                return None;
            }
            rgb.extend_from_slice(&data[start..end]);
        }
        DynamicImage::ImageRgb8(RgbImage::from_raw(width, height, rgb)?)
    };

    let img = img.thumbnail(
        NOTIFICATION_ICON_THUMBNAIL_PX,
        NOTIFICATION_ICON_THUMBNAIL_PX,
    );

    let mut buf = Vec::new();
    img.write_to(
        &mut std::io::Cursor::new(&mut buf),
        image::ImageFormat::Png,
    )
    .ok()?;
    Some(buf)
}

fn extract_i32(val: &Value<'_>) -> Option<i32> {
    match val {
        Value::I32(v) => Some(*v),
        _ => None,
    }
}

fn extract_bool(val: &Value<'_>) -> Option<bool> {
    match val {
        Value::Bool(v) => Some(*v),
        _ => None,
    }
}

fn extract_bytes(val: &Value<'_>) -> Option<Vec<u8>> {
    if let Value::Array(arr) = val {
        arr.iter()
            .map(|v| match v {
                Value::U8(b) => Some(*b),
                _ => None,
            })
            .collect()
    } else {
        None
    }
}
