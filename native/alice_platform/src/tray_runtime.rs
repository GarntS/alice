//! Runtime-owned SNI subscriptions. Snapshot consumers only clone cached values.
use super::*;
use futures_util::StreamExt;
use std::time::{Duration, Instant};

#[derive(Default)]
struct RuntimeSnapshots {
    ready: bool,
    items: Vec<TrayItemSnapshot>,
}
fn snapshots() -> &'static Mutex<Option<RuntimeSnapshots>> {
    static SNAPSHOTS: OnceLock<Mutex<Option<RuntimeSnapshots>>> = OnceLock::new();
    SNAPSHOTS.get_or_init(|| Mutex::new(None))
}
pub(super) fn cached_snapshots() -> Option<Vec<TrayItemSnapshot>> {
    let state = snapshots().lock().ok()?;
    state.as_ref().map(|state| {
        if state.ready {
            state.items.clone()
        } else {
            vec![]
        }
    })
}

struct Entry {
    item: StatusNotifierItemRef,
    owner: String,
    generation: u64,
    dirty: bool,
    reading: bool,
    snapshot: Option<TrayItemSnapshot>,
    retry_at: Instant,
    refresh_at: Instant,
    metadata_key: String,
    read_task: Option<tokio::task::JoinHandle<()>>,
    alive: Arc<std::sync::atomic::AtomicBool>,
    subscription: tokio::task::JoinHandle<()>,
}
impl Drop for Entry {
    fn drop(&mut self) {
        self.alive
            .store(false, std::sync::atomic::Ordering::Release);
        self.subscription.abort();
        if let Some(task) = &self.read_task {
            task.abort();
        }
        if let Ok(mut cache) = item_metadata_cache().lock() {
            cache.remove(&self.metadata_key);
        }
        if let Ok(mut cache) = tray_item_cache().lock() {
            cache.remove(&self.item.canonical_id());
        }
    }
}
fn next_generation() -> u64 {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

enum Event {
    Reconcile,
    Dirty(String),
    Read {
        key: String,
        owner: String,
        generation: u64,
        snapshot: Option<TrayItemSnapshot>,
    },
}

async fn item_subscription(
    connection: &zbus::Connection,
    item: &StatusNotifierItemRef,
    owner: &str,
    tx: mpsc::Sender<Event>,
) -> zbus::Result<tokio::task::JoinHandle<()>> {
    // Install the bus match before the first property read. Filtering by unique
    // owner and object path prevents unrelated publishers from invalidating it.
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(owner)?
        .path(item.object_path.as_str())?
        .build();
    let mut stream = zbus::MessageStream::for_match_rule(rule, connection, Some(64)).await?;
    let key = item.canonical_id();
    Ok(tokio::spawn(async move {
        while let Some(Ok(message)) = stream.next().await {
            let header = message.header();
            let member = header.member().map(|member| member.as_str()).unwrap_or("");
            let interface = header
                .interface()
                .map(|interface| interface.as_str())
                .unwrap_or("");
            let item_change = matches!(interface, ITEM_INTERFACE_KDE | ITEM_INTERFACE_FREEDESKTOP)
                && matches!(
                    member,
                    "NewIcon" | "NewAttentionIcon" | "NewIconThemePath" | "NewTitle" | "NewStatus"
                );
            let property_change = interface == "org.freedesktop.DBus.Properties"
                && member == "PropertiesChanged"
                && message
                    .body()
                    .deserialize::<(
                        String,
                        HashMap<String, zbus::zvariant::OwnedValue>,
                        Vec<String>,
                    )>()
                    .is_ok_and(|(interface, changed, invalidated)| {
                        matches!(
                            interface.as_str(),
                            ITEM_INTERFACE_KDE | ITEM_INTERFACE_FREEDESKTOP
                        ) && changed.keys().chain(invalidated.iter()).any(|property| {
                            matches!(
                                property.as_str(),
                                "IconName"
                                    | "IconPixmap"
                                    | "AttentionIconName"
                                    | "AttentionIconPixmap"
                                    | "IconThemePath"
                                    | "Title"
                                    | "Id"
                                    | "Status"
                                    | "Menu"
                                    | "ItemIsMenu"
                            )
                        })
                    });
            if (item_change || property_change) && tx.send(Event::Dirty(key.clone())).await.is_err()
            {
                break;
            }
        }
    }))
}

async fn lifecycle_subscription(
    connection: &zbus::Connection,
    interface: &str,
    tx: mpsc::Sender<Event>,
) -> zbus::Result<tokio::task::JoinHandle<()>> {
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(interface)?
        .build();
    let mut stream = zbus::MessageStream::for_match_rule(rule, connection, Some(64)).await?;
    Ok(tokio::spawn(async move {
        while let Some(Ok(message)) = stream.next().await {
            let header = message.header();
            let member = header.member().map(|member| member.as_str()).unwrap_or("");
            if matches!(
                member,
                "NameOwnerChanged"
                    | "StatusNotifierItemRegistered"
                    | "StatusNotifierItemUnregistered"
            ) && tx.send(Event::Reconcile).await.is_err()
            {
                break;
            }
        }
    }))
}

fn publish(entries: &HashMap<String, Entry>, trigger: &mpsc::Sender<crate::runtime::Trigger>) {
    let mut items: Vec<_> = entries
        .values()
        .filter_map(|entry| entry.snapshot.clone())
        .collect();
    items.sort_by(|a, b| (&a.service_name, &a.object_path).cmp(&(&b.service_name, &b.object_path)));
    if let Ok(mut state) = snapshots().lock() {
        *state = Some(RuntimeSnapshots { ready: true, items });
    }
    let _ = trigger.try_send(crate::runtime::Trigger::Event);
}

async fn reconcile(
    connection: &zbus::Connection,
    entries: &mut HashMap<String, Entry>,
    tx: &mpsc::Sender<Event>,
) -> zbus::Result<()> {
    let connection_for_read = connection.clone();
    let refs = tokio::task::spawn_blocking(move || {
        let connection = Connection::from(connection_for_read);
        let refs = registered_items_from_watcher(&connection)
            .or_else(|_| fallback_items_from_bus(&connection))
            .unwrap_or_default();
        let dbus = Proxy::new(&connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE).ok();
        refs.into_iter()
            .filter_map(|item| {
                let owner: String = dbus
                    .as_ref()?
                    .call("GetNameOwner", &(item.service_name.as_str(),))
                    .ok()?;
                Some((item, owner))
            })
            .collect::<Vec<_>>()
    })
    .await
    .map_err(|error| zbus::Error::Failure(error.to_string()))?;
    let present: HashSet<_> = refs.iter().map(|(item, _)| item.canonical_id()).collect();
    entries.retain(|key, _| present.contains(key));
    for (item, owner) in refs {
        let key = item.canonical_id();
        if entries.get(&key).is_some_and(|entry| entry.owner == owner) {
            continue;
        }
        entries.remove(&key);
        let subscription = item_subscription(connection, &item, &owner, tx.clone()).await?;
        let generation = next_generation();
        let metadata_key = item_metadata_key(&Connection::from(connection.clone()), &item);
        entries.insert(
            key,
            Entry {
                item,
                owner,
                generation,
                dirty: true,
                reading: false,
                snapshot: None,
                retry_at: Instant::now() + Duration::from_secs(5),
                refresh_at: Instant::now(),
                metadata_key,
                read_task: None,
                alive: Arc::new(std::sync::atomic::AtomicBool::new(true)),
                subscription,
            },
        );
    }
    Ok(())
}

pub async fn run(trigger: mpsc::Sender<crate::runtime::Trigger>) -> zbus::Result<()> {
    let connection = zbus::connection::Builder::session()?
        .method_timeout(Duration::from_secs(5))
        .build()
        .await?;
    run_on_connection(connection, trigger).await
}

pub(super) async fn run_on_connection(
    connection: zbus::Connection,
    trigger: mpsc::Sender<crate::runtime::Trigger>,
) -> zbus::Result<()> {
    *snapshots().lock().unwrap() = Some(RuntimeSnapshots::default());
    struct SnapshotGuard;
    impl Drop for SnapshotGuard {
        fn drop(&mut self) {
            if let Ok(mut state) = snapshots().lock() {
                *state = Some(RuntimeSnapshots {
                    ready: true,
                    items: vec![],
                });
            }
        }
    }
    let _snapshot_guard = SnapshotGuard;
    let (tx, mut rx) = mpsc::channel(256);
    // Owned handles are aborted even if setup or the service itself is cancelled.
    struct Tasks(Vec<tokio::task::JoinHandle<()>>);
    impl Drop for Tasks {
        fn drop(&mut self) {
            for task in &self.0 {
                task.abort();
            }
        }
    }
    let mut tasks = Tasks(Vec::new());
    for interface in [
        DBUS_INTERFACE,
        WATCHER_INTERFACE_KDE,
        WATCHER_INTERFACE_FREEDESKTOP,
    ] {
        tasks
            .0
            .push(lifecycle_subscription(&connection, interface, tx.clone()).await?);
    }
    let mut entries = HashMap::new();
    reconcile(&connection, &mut entries, &tx).await?;
    loop {
        for (key, entry) in &mut entries {
            if !entry.dirty || entry.reading || entry.refresh_at > Instant::now() {
                continue;
            }
            entry.dirty = false;
            entry.reading = true;
            let key = key.clone();
            let owner = entry.owner.clone();
            let generation = entry.generation;
            let item = entry.item.clone();
            let tx = tx.clone();
            let connection = connection.clone();
            let alive = entry.alive.clone();
            let expected_owner = owner.clone();
            let metadata_key = entry.metadata_key.clone();
            entry.read_task = Some(tokio::spawn(async move {
                let snapshot = tokio::task::spawn_blocking(move || {
                    let connection = Connection::from(connection);
                    let dbus =
                        Proxy::new(&connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE).ok()?;
                    let owner_before: String = dbus
                        .call("GetNameOwner", &(item.service_name.as_str(),))
                        .ok()?;
                    if owner_before != expected_owner {
                        return None;
                    }
                    let snapshot = read_item_snapshot(&connection, &item).ok().flatten();
                    let owner_after: Option<String> = dbus
                        .call("GetNameOwner", &(item.service_name.as_str(),))
                        .ok();
                    if !alive.load(std::sync::atomic::Ordering::Acquire)
                        || owner_after.as_deref() != Some(expected_owner.as_str())
                    {
                        if let Ok(mut cache) = item_metadata_cache().lock()
                            && cache.get(&metadata_key).is_some_and(|entries| {
                                entries
                                    .first()
                                    .is_some_and(|metadata| metadata.owner == expected_owner)
                            })
                        {
                            cache.remove(&metadata_key);
                        }
                        None
                    } else {
                        snapshot
                    }
                })
                .await
                .ok()
                .flatten();
                let _ = tx
                    .send(Event::Read {
                        key,
                        owner,
                        generation,
                        snapshot,
                    })
                    .await;
            }));
        }
        let retry_at = entries
            .values()
            .filter(|entry| {
                entry
                    .snapshot
                    .as_ref()
                    .is_none_or(|snapshot| snapshot.icon_png_bytes.is_none())
            })
            .map(|entry| entry.retry_at)
            .min()
            .unwrap_or_else(|| Instant::now() + Duration::from_secs(3600));
        tokio::select! {
            _ = tokio::time::sleep(Duration::from_millis(25)) => {}
            _ = tokio::time::sleep_until(tokio::time::Instant::from_std(retry_at)) => {
                for entry in entries.values_mut() {
                    if entry.snapshot.as_ref().is_none_or(|snapshot| snapshot.icon_png_bytes.is_none())
                        && entry.retry_at <= Instant::now() {
                        entry.dirty = true;
                        entry.retry_at = Instant::now() + Duration::from_secs(5);
                    }
                }
            }
            event = rx.recv() => {
                match event {
                    Some(Event::Reconcile) => {
                        reconcile(&connection, &mut entries, &tx).await?;
                        publish(&entries, &trigger);
                    }
                    Some(Event::Dirty(key)) => {
                        if let Some(entry) = entries.get_mut(&key) {
                            entry.generation = next_generation();
                            entry.dirty = true;
                            entry.refresh_at = Instant::now() + Duration::from_millis(25);
                            if let Ok(mut cache) = item_metadata_cache().lock() {
                                cache.remove(&item_metadata_key(&Connection::from(connection.clone()), &entry.item));
                            }
                        }
                        // A short quiet window coalesces bursts; queued signals still
                        // increment the generation while any property read is in flight.
                    }
                    Some(Event::Read { key, owner, generation, snapshot }) => {
                        if let Some(entry) = entries.get_mut(&key)
                            && entry.owner == owner {
                            entry.reading = false;
                            if entry.generation == generation {
                                entry.snapshot = snapshot;
                                entry.retry_at = Instant::now() + Duration::from_secs(5);
                                publish(&entries, &trigger);
                            } else { entry.dirty = true; }
                        }
                    }
                    None => break,
                }
            }
        }
    }
    Ok(())
}
