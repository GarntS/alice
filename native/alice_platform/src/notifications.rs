//! Freedesktop desktop notifications server (org.freedesktop.Notifications v1.2).
//!
//! Registers on the session bus as `org.freedesktop.Notifications`, stores
//! incoming notifications in memory, and feeds them into the `BarSnapshot`
//! stream via the shared `Trigger` channel.

use std::{
    collections::HashMap,
    future::Future,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU32, Ordering},
    },
};

use tokio::sync::mpsc;
use zbus::zvariant::{OwnedValue, Value};

use crate::{
    runtime::Trigger,
    state::{NotificationActionSnapshot, NotificationSnapshot, NotificationUrgency},
};

const MAX_NOTIFICATION_IMAGE_DIMENSION: u32 = 2048;
const MAX_NOTIFICATION_IMAGE_BYTES: usize = 16 * 1024 * 1024;
const NOTIFICATION_ICON_THUMBNAIL_PX: u32 = 96;

#[derive(Debug, Clone)]
struct StoredNotification {
    snapshot: NotificationSnapshot,
    activation_identity: Option<String>,
}

// ---------------------------------------------------------------------------
// In-memory store
// ---------------------------------------------------------------------------

#[derive(Default)]
pub struct NotificationStore {
    notifications: Vec<StoredNotification>,
}

impl NotificationStore {
    fn add_or_replace(&mut self, notification: StoredNotification) -> u32 {
        let id = notification.snapshot.id;
        if let Some(pos) = self
            .notifications
            .iter()
            .position(|record| record.snapshot.id == id)
        {
            self.notifications[pos] = notification;
        } else {
            self.notifications.push(notification);
        }
        id
    }

    fn remove(&mut self, id: u32) -> bool {
        if let Some(pos) = self
            .notifications
            .iter()
            .position(|record| record.snapshot.id == id)
        {
            self.notifications.remove(pos);
            true
        } else {
            false
        }
    }

    fn remove_all(&mut self) {
        self.notifications.clear();
    }

    pub fn get_all(&self) -> Vec<NotificationSnapshot> {
        self.notifications
            .iter()
            .map(|record| record.snapshot.clone())
            .collect()
    }

    fn activation_identity(&self, id: u32) -> Option<String> {
        self.notifications
            .iter()
            .find(|record| record.snapshot.id == id)
            .and_then(|record| record.activation_identity.clone())
    }

    pub fn mark_read(&mut self, id: u32) {
        if let Some(record) = self
            .notifications
            .iter_mut()
            .find(|record| record.snapshot.id == id)
        {
            record.snapshot.is_read = true;
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
        let activation_identity = parse_activation_identity(&hints);

        // actions vec is [key, label, key, label, ...]
        let parsed_actions: Vec<NotificationActionSnapshot> = actions
            .chunks(2)
            .filter(|c| c.len() == 2)
            .map(|c| NotificationActionSnapshot {
                key: c[0].clone(),
                label: c[1].clone(),
            })
            .collect();

        // Reuse replaces_id if the notification still exists; otherwise allocate new.
        let id = if replaces_id > 0 {
            let exists = self
                .store
                .lock()
                .map(|s| s.notifications.iter().any(|n| n.snapshot.id == replaces_id))
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
            snapshot: NotificationSnapshot {
                id,
                app_name: app_name.to_string(),
                app_icon: app_icon.to_string(),
                summary: summary.to_string(),
                body: body.to_string(),
                urgency,
                actions: parsed_actions,
                category,
                is_read: false,
                received_at_unix_secs,
                image_data,
                image_path,
            },
            activation_identity,
        };

        let _effective_timeout_ms = if expire_timeout < 0 {
            self.default_timeout_ms
        } else {
            expire_timeout as u32
        };

        if let Ok(mut store) = self.store.lock() {
            store.add_or_replace(notification);
        }

        let _ = self.trigger.send(Trigger::Event).await;
        id
    }

    /// Close a notification on behalf of the sending application.
    async fn close_notification(&self, id: u32) {
        let removed = self.store.lock().map(|mut s| s.remove(id)).unwrap_or(false);
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
        let _ = NotificationServer::notification_closed(iface.signal_emitter(), id, reason).await;
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

    let conn = zbus::connection::Builder::session()?.build().await?;
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

pub fn get_notifications() -> Vec<NotificationSnapshot> {
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
    let activation_identity = NOTIFICATION_STORE
        .get()
        .and_then(|store| store.lock().ok())
        .and_then(|store| store.activation_identity(id));

    if let Some(conn) = NOTIFICATION_CONNECTION.get().cloned() {
        if let Some(handle) = crate::runtime::tokio_handle() {
            handle.spawn(async move {
                if let Ok(iface) = conn
                    .object_server()
                    .interface::<_, NotificationServer>("/org/freedesktop/Notifications")
                    .await
                {
                    let result = deliver_action_then_activate(
                        activation_identity,
                        || {
                            NotificationServer::action_invoked(
                                iface.signal_emitter(),
                                id,
                                &action_key,
                            )
                        },
                        |identity| {
                            crate::foreign_toplevel::ForeignToplevelActivationService::request_global_activation(
                                identity,
                            );
                        },
                    )
                    .await;
                    if let Err(error) = result {
                        eprintln!(
                            "alice: failed to emit notification action id={id} key={action_key}: {error}"
                        );
                    }
                } else {
                    eprintln!("alice: notification interface unavailable for action id={id}");
                }
            });
        }
    }
}

async fn deliver_action_then_activate<Emit, EmitFuture, Activate>(
    activation_identity: Option<String>,
    emit: Emit,
    activate: Activate,
) -> zbus::Result<()>
where
    Emit: FnOnce() -> EmitFuture,
    EmitFuture: Future<Output = zbus::Result<()>>,
    Activate: FnOnce(String),
{
    emit().await?;
    if let Some(identity) = activation_identity {
        activate(identity);
    }
    Ok(())
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

fn parse_urgency(hints: &HashMap<String, OwnedValue>) -> NotificationUrgency {
    hints
        .get("urgency")
        .and_then(|v| match &**v {
            Value::U8(0) => Some(NotificationUrgency::Low),
            Value::U8(2) => Some(NotificationUrgency::Critical),
            Value::U8(_) => Some(NotificationUrgency::Normal),
            _ => None,
        })
        .unwrap_or(NotificationUrgency::Normal)
}

fn parse_activation_identity(hints: &HashMap<String, OwnedValue>) -> Option<String> {
    hints.get("desktop-entry").and_then(|value| match &**value {
        Value::Str(identity) => normalize_activation_identity(identity.as_str()),
        _ => None,
    })
}

pub(crate) fn normalize_activation_identity(identity: &str) -> Option<String> {
    let identity = identity.trim().to_lowercase();
    let identity = identity
        .strip_suffix(".desktop")
        .unwrap_or(&identity)
        .trim();
    (!identity.is_empty()).then(|| identity.to_string())
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
    let v = hints.get("image-data").or_else(|| hints.get("icon_data"))?;
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
    img.write_to(&mut std::io::Cursor::new(&mut buf), image::ImageFormat::Png)
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

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::Str;

    fn string_hint(value: &str) -> OwnedValue {
        OwnedValue::from(Str::from(value))
    }

    fn snapshot(id: u32, summary: &str) -> NotificationSnapshot {
        NotificationSnapshot {
            id,
            app_name: "test-app".into(),
            app_icon: "test-icon".into(),
            summary: summary.into(),
            body: "test body".into(),
            urgency: NotificationUrgency::Critical,
            actions: vec![NotificationActionSnapshot {
                key: "open".into(),
                label: "Open".into(),
            }],
            category: Some("email".into()),
            is_read: false,
            received_at_unix_secs: 1_234_567,
            image_data: Some(vec![1, 2, 3]),
            image_path: Some("file:///tmp/test.png".into()),
        }
    }

    #[tokio::test]
    async fn successful_action_emission_precedes_activation() {
        let events = Arc::new(Mutex::new(Vec::new()));
        let emitted_events = events.clone();
        let activated_events = events.clone();

        let result = deliver_action_then_activate(
            Some("org.example.chat".to_string()),
            || async move {
                emitted_events.lock().expect("events").push("emitted");
                Ok(())
            },
            move |identity| {
                assert_eq!(identity, "org.example.chat");
                activated_events.lock().expect("events").push("activated");
            },
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(*events.lock().expect("events"), ["emitted", "activated"]);
    }

    #[tokio::test]
    async fn failed_action_emission_suppresses_activation() {
        let activated = Arc::new(Mutex::new(false));
        let activation_observer = activated.clone();

        let result = deliver_action_then_activate(
            Some("org.example.chat".to_string()),
            || async { Err(zbus::Error::Failure("signal failed".to_string())) },
            move |_| *activation_observer.lock().expect("activation state") = true,
        )
        .await;

        assert!(result.is_err());
        assert!(!*activated.lock().expect("activation state"));
    }

    #[tokio::test]
    async fn unavailable_or_ambiguous_activation_does_not_fail_action_delivery() {
        let attempts = Arc::new(Mutex::new(Vec::new()));
        let activation_attempts = attempts.clone();

        let result = deliver_action_then_activate(
            Some("ambiguous.app".to_string()),
            || async { Ok(()) },
            move |identity| {
                // The worker may decline this request as unsupported or
                // ambiguous; enqueue outcome is intentionally not propagated.
                activation_attempts
                    .lock()
                    .expect("activation attempts")
                    .push(identity);
            },
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(
            *attempts.lock().expect("activation attempts"),
            ["ambiguous.app"]
        );
    }

    #[tokio::test]
    async fn missing_identity_still_delivers_action_without_activation() {
        let activated = Arc::new(Mutex::new(false));
        let activation_observer = activated.clone();

        let result = deliver_action_then_activate(
            None,
            || async { Ok(()) },
            move |_| *activation_observer.lock().expect("activation state") = true,
        )
        .await;

        assert!(result.is_ok());
        assert!(!*activated.lock().expect("activation state"));
    }

    #[test]
    fn store_add_replace_mark_read_remove_and_extract_exact_snapshot() {
        let mut store = NotificationStore::default();
        let initial = snapshot(7, "initial");

        assert_eq!(
            store.add_or_replace(StoredNotification {
                snapshot: initial.clone(),
                activation_identity: None,
            }),
            7
        );
        assert_eq!(store.get_all(), vec![initial]);

        let replacement = snapshot(7, "replacement");
        store.add_or_replace(StoredNotification {
            snapshot: replacement.clone(),
            activation_identity: None,
        });
        assert_eq!(store.get_all(), vec![replacement.clone()]);

        store.mark_read(7);
        let mut expected_read = replacement;
        expected_read.is_read = true;
        assert_eq!(store.get_all(), vec![expected_read]);

        assert!(store.remove(7));
        assert!(store.get_all().is_empty());
        assert!(!store.remove(7));
    }

    #[test]
    fn desktop_entry_hint_is_normalized_when_present() {
        let hints = HashMap::from([(
            "desktop-entry".to_string(),
            string_hint("  Org.Example.Chat.Desktop  "),
        )]);

        assert_eq!(
            parse_activation_identity(&hints),
            Some("org.example.chat".to_string())
        );
    }

    #[test]
    fn desktop_entry_hint_absence_and_malformed_values_are_ignored() {
        assert_eq!(parse_activation_identity(&HashMap::new()), None);

        let wrong_type = HashMap::from([("desktop-entry".to_string(), OwnedValue::from(7_u32))]);
        assert_eq!(parse_activation_identity(&wrong_type), None);

        for value in ["", "   ", ".desktop", " .DESKTOP "] {
            let hints = HashMap::from([("desktop-entry".to_string(), string_hint(value))]);
            assert_eq!(parse_activation_identity(&hints), None, "value={value:?}");
        }
    }

    #[test]
    fn normalization_removes_only_one_suffix_and_matches_case_insensitively() {
        assert_eq!(
            normalize_activation_identity(" Example.App.DESKTOP.desktop "),
            Some("example.app.desktop".to_string())
        );
        assert_eq!(
            normalize_activation_identity(" EXAMPLE.APP "),
            normalize_activation_identity("example.app.desktop")
        );
    }

    #[test]
    fn replacement_updates_internal_identity_without_changing_snapshot_extraction() {
        let mut store = NotificationStore::default();
        store.add_or_replace(StoredNotification {
            snapshot: snapshot(11, "initial"),
            activation_identity: Some("old.app".to_string()),
        });

        let replacement = snapshot(11, "replacement");
        store.add_or_replace(StoredNotification {
            snapshot: replacement.clone(),
            activation_identity: Some("new.app".to_string()),
        });

        assert_eq!(store.activation_identity(11).as_deref(), Some("new.app"));
        assert_eq!(store.get_all(), vec![replacement]);
    }

    #[test]
    fn store_only_metadata_does_not_change_snapshot_payload() {
        let payload = snapshot(9, "same payload");
        let earlier_record = StoredNotification {
            snapshot: payload.clone(),
            activation_identity: None,
        };
        let recent_record = StoredNotification {
            snapshot: payload.clone(),
            activation_identity: Some("internal.app".to_string()),
        };
        assert_ne!(
            earlier_record.activation_identity,
            recent_record.activation_identity
        );

        let mut earlier_store = NotificationStore::default();
        earlier_store.add_or_replace(earlier_record);
        let mut recent_store = NotificationStore::default();
        recent_store.add_or_replace(recent_record);

        assert_eq!(earlier_store.get_all(), vec![payload]);
        assert_eq!(earlier_store.get_all(), recent_store.get_all());
    }
}
