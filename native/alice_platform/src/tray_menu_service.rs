//! Only the active tray menu owns bus subscriptions and selectable remote ids.
use crate::{
    PlatformError,
    tray::{MenuSource, TrayActionOutcome, TrayItemAction},
    tray_menu::{RawNode, TrayMenuNode, parse_layout},
};
use futures_util::StreamExt;
use std::{
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::Duration,
};
use zbus::zvariant::Value;
const INTERFACE: &str = "com.canonical.dbusmenu";

#[cfg(test)]
#[path = "tray_menu_service_tests.rs"]
mod tests;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrayMenuSnapshot {
    pub request_id: u64,
    pub revision: u32,
    pub root: TrayMenuNode,
    pub secondary_supported: bool,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TrayMenuSelection {
    Remote { id: i32 },
    Secondary,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TrayMenuUpdate {
    Unchanged,
    Updated { snapshot: TrayMenuSnapshot },
    Closed,
}

struct TrayMenuSession {
    id: u64,
    service: String,
    object_path: String,
    source: MenuSource,
    connection: zbus::Connection,
    snapshot: Option<TrayMenuSnapshot>,
    dirty: bool,
    reading: bool,
    subscriptions: Vec<tokio::task::JoinHandle<()>>,
}
impl Drop for TrayMenuSession {
    fn drop(&mut self) {
        for task in &self.subscriptions {
            task.abort();
        }
    }
}
struct State {
    request_id: u64,
    active: Option<TrayMenuSession>,
}
fn state() -> &'static Mutex<State> {
    static STATE: OnceLock<Mutex<State>> = OnceLock::new();
    STATE.get_or_init(|| {
        Mutex::new(State {
            request_id: 0,
            active: None,
        })
    })
}
pub fn begin_request() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let mut state = state().lock().unwrap();
    state.request_id = id;
    state.active = None;
    id
}
pub fn cancel(request_id: u64) {
    if let Ok(mut state) = state().lock()
        && state.request_id == request_id
    {
        state.active = None;
        state.request_id = 0;
    }
}
fn diagnostic(error: impl std::fmt::Display) -> PlatformError {
    PlatformError::new(format!("tray menu: {error}"))
}
async fn prepare_and_load(
    connection: &zbus::Connection,
    source: &MenuSource,
    parent_id: i32,
) -> Result<(u32, TrayMenuNode), PlatformError> {
    let proxy = zbus::Proxy::new(
        connection,
        source.owner.as_str(),
        source.menu_path.as_str(),
        INTERFACE,
    )
    .await
    .map_err(diagnostic)?;
    match proxy.call::<_, _, bool>("AboutToShow", &(parent_id,)).await {
        Ok(_) => {}
        Err(error) if crate::tray::unsupported_action_error(&error) => {}
        Err(error) => {
            return Err(diagnostic(format!(
                "destination={} method=AboutToShow: {error}",
                source.owner
            )));
        }
    }
    // Get the complete root after preparing a submenu, preserving unique-id validation
    // and replacing all stale children atomically rather than grafting unchecked nodes.
    let (revision, root): (u32, RawNode) = proxy
        .call("GetLayout", &(0i32, -1i32, Vec::<String>::new()))
        .await
        .map_err(|error| {
            diagnostic(format!(
                "destination={} method=GetLayout: {error}",
                source.owner
            ))
        })?;
    let root = parse_layout(root)?;
    if !root
        .children
        .iter()
        .any(|node| node.visible && !node.separator)
    {
        return Err(diagnostic("no usable published menu entries"));
    }
    Ok((revision, root))
}

pub async fn load(
    request_id: u64,
    service: String,
    object_path: String,
) -> Result<TrayMenuSnapshot, PlatformError> {
    let result = tokio::time::timeout(Duration::from_secs(5), async {
        let source = crate::tray::menu_source(service.clone(), object_path.clone()).await?;
        let connection = zbus::connection::Builder::session()
            .map_err(diagnostic)?
            .method_timeout(Duration::from_secs(5))
            .build()
            .await
            .map_err(diagnostic)?;
        load_on_connection(request_id, connection, service, object_path, source).await
    })
    .await
    .unwrap_or_else(|_| Err(diagnostic("load timed out")));
    if result.is_err() {
        cancel(request_id);
    }
    result
}

pub(crate) async fn load_on_connection(
    request_id: u64,
    connection: zbus::Connection,
    service: String,
    object_path: String,
    source: MenuSource,
) -> Result<TrayMenuSnapshot, PlatformError> {
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(source.owner.as_str())
        .map_err(diagnostic)?
        .path(source.menu_path.as_str())
        .map_err(diagnostic)?
        .interface(INTERFACE)
        .map_err(diagnostic)?
        .build();
    // Both matches exist before the initial AboutToShow/GetLayout round trip.
    let mut menu_signals = zbus::MessageStream::for_match_rule(rule, &connection, Some(64))
        .await
        .map_err(diagnostic)?;
    let owner_rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.DBus")
        .map_err(diagnostic)?
        .interface("org.freedesktop.DBus")
        .map_err(diagnostic)?
        .member("NameOwnerChanged")
        .map_err(diagnostic)?
        .build();
    let mut owners = zbus::MessageStream::for_match_rule(owner_rule, &connection, Some(64))
        .await
        .map_err(diagnostic)?;
    {
        let mut guard = state().lock().unwrap();
        if guard.request_id != request_id {
            return Err(diagnostic("superseded load"));
        }
        let owner = source.owner.clone();
        let service_for_owner = service.clone();
        let menu_task = tokio::spawn(async move {
            while let Some(Ok(message)) = menu_signals.next().await {
                let header = message.header();
                if matches!(
                    header.member().map(|member| member.as_str()),
                    Some("LayoutUpdated" | "ItemsPropertiesUpdated")
                ) {
                    if let Ok(mut state) = state().lock()
                        && let Some(session) = state.active.as_mut()
                        && session.id == request_id
                    {
                        // Selections are rejected while dirty; remote property updates
                        // are consumed by reloading the full, bounded tree.
                        session.dirty = true;
                    }
                }
            }
            cancel(request_id);
        });
        let owner_task = tokio::spawn(async move {
            while let Some(Ok(message)) = owners.next().await {
                if let Ok((name, _, new)) = message.body().deserialize::<(String, String, String)>()
                    && (name == owner || name == service_for_owner)
                    && new != owner
                {
                    cancel(request_id);
                    break;
                }
            }
        });
        guard.active = Some(TrayMenuSession {
            id: request_id,
            service,
            object_path,
            source: source.clone(),
            connection: connection.clone(),
            snapshot: None,
            dirty: false,
            reading: true,
            subscriptions: vec![menu_task, owner_task],
        });
    }
    // The well-known service may have changed owners between discovery and
    // subscription setup. Pinning calls alone is insufficient if the old owner lives.
    let dbus = zbus::Proxy::new(
        &connection,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )
    .await
    .map_err(diagnostic)?;
    let current_owner: Result<String, _> = dbus
        .call("GetNameOwner", &(service_name_for_request(request_id)?,))
        .await;
    if current_owner.ok().as_deref() != Some(source.owner.as_str()) {
        cancel(request_id);
        return Err(diagnostic("menu service owner changed"));
    }
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        prepare_and_load(&connection, &source, 0),
    )
    .await
    .unwrap_or_else(|_| Err(diagnostic("GetLayout timed out")));
    match result {
        Ok((revision, root)) => {
            let snapshot = TrayMenuSnapshot {
                request_id,
                revision,
                root,
                secondary_supported: source.secondary_supported,
            };
            let mut state = state().lock().unwrap();
            let session = state
                .active
                .as_mut()
                .filter(|session| session.id == request_id)
                .ok_or_else(|| diagnostic("cancelled load"))?;
            session.reading = false;
            session.snapshot = Some(snapshot.clone());
            Ok(snapshot)
        }
        Err(error) => {
            cancel(request_id);
            Err(error)
        }
    }
}

fn service_name_for_request(request_id: u64) -> Result<String, PlatformError> {
    state()
        .lock()
        .unwrap()
        .active
        .as_ref()
        .filter(|session| session.id == request_id)
        .map(|session| session.service.clone())
        .ok_or_else(|| diagnostic("cancelled request"))
}

fn find_node(root: &TrayMenuNode, id: i32) -> Option<&TrayMenuNode> {
    if !root.visible || !root.enabled {
        return None;
    }
    if root.id == id {
        Some(root)
    } else {
        root.children.iter().find_map(|child| find_node(child, id))
    }
}

pub async fn refresh(
    request_id: u64,
    submenu_id: Option<i32>,
) -> Result<TrayMenuUpdate, PlatformError> {
    let (connection, source) = {
        let mut state = state().lock().unwrap();
        let Some(session) = state
            .active
            .as_mut()
            .filter(|session| session.id == request_id)
        else {
            return Ok(TrayMenuUpdate::Closed);
        };
        if let Some(id) = submenu_id {
            let valid = session
                .snapshot
                .as_ref()
                .and_then(|snapshot| find_node(&snapshot.root, id))
                .is_some_and(|node| node.visible && node.enabled && node.submenu);
            if !valid || session.dirty || session.reading {
                return Err(diagnostic("stale submenu id"));
            }
        }
        if session.reading || (!session.dirty && submenu_id.is_none()) {
            return Ok(TrayMenuUpdate::Unchanged);
        }
        session.reading = true;
        session.dirty = false;
        (session.connection.clone(), session.source.clone())
    };
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        prepare_and_load(&connection, &source, submenu_id.unwrap_or(0)),
    )
    .await
    .map_err(|_| diagnostic("refresh timed out"));
    let (revision, root) = match result {
        Ok(Ok(layout)) => layout,
        Ok(Err(error)) | Err(error) => {
            cancel(request_id);
            return Err(error);
        }
    };
    let snapshot = TrayMenuSnapshot {
        request_id,
        revision,
        root,
        secondary_supported: source.secondary_supported,
    };
    let mut state = state().lock().unwrap();
    let Some(session) = state
        .active
        .as_mut()
        .filter(|session| session.id == request_id)
    else {
        return Ok(TrayMenuUpdate::Closed);
    };
    session.reading = false;
    session.snapshot = Some(snapshot.clone());
    Ok(TrayMenuUpdate::Updated { snapshot })
}

pub async fn select(
    request_id: u64,
    selection: TrayMenuSelection,
    x: i32,
    y: i32,
    timestamp: u32,
) -> Result<TrayActionOutcome, PlatformError> {
    let (connection, source, object_path) = {
        let state = state().lock().unwrap();
        let session = state
            .active
            .as_ref()
            .filter(|session| session.id == request_id)
            .ok_or_else(|| diagnostic("cancelled selection"))?;
        if session.dirty || session.reading {
            return Err(diagnostic("stale menu selection"));
        }
        match selection {
            TrayMenuSelection::Secondary if !session.source.secondary_supported => {
                return Err(diagnostic("unsupported secondary action"));
            }
            TrayMenuSelection::Remote { id } => {
                let node = session
                    .snapshot
                    .as_ref()
                    .and_then(|snapshot| find_node(&snapshot.root, id));
                if id == 0
                    || !node.is_some_and(|node| {
                        node.visible && node.enabled && !node.separator && !node.submenu
                    })
                {
                    return Err(diagnostic(
                        "disabled, hidden, removed, or non-actionable menu id",
                    ));
                }
            }
            _ => {}
        }
        (
            session.connection.clone(),
            session.source.clone(),
            session.object_path.clone(),
        )
    };
    // Cancellation only affects this request; it cannot close a newer popup.
    cancel(request_id);
    match selection {
        TrayMenuSelection::Secondary => {
            let owner = source.owner.clone();
            tokio::task::spawn_blocking(move || {
                crate::tray::send_tray_action_on_connection(
                    &zbus::blocking::Connection::from(connection),
                    &owner,
                    &object_path,
                    TrayItemAction::SecondaryActivate,
                    x,
                    y,
                )
            })
            .await
            .map_err(diagnostic)?
        }
        TrayMenuSelection::Remote { id } => {
            let proxy = zbus::Proxy::new(
                &connection,
                source.owner.as_str(),
                source.menu_path.as_str(),
                INTERFACE,
            )
            .await
            .map_err(diagnostic)?;
            let result = tokio::time::timeout(
                Duration::from_secs(5),
                proxy.call::<_, _, ()>("Event", &(id, "clicked", Value::from(0i32), timestamp)),
            )
            .await;
            match result {
                Ok(Ok(())) => Ok(TrayActionOutcome::Executed),
                Ok(Err(error)) => Err(diagnostic(format!(
                    "destination={} interface={INTERFACE} method=Event: {error}",
                    source.owner
                ))),
                Err(_) => Err(diagnostic(format!(
                    "destination={} interface={INTERFACE} method=Event: timed out",
                    source.owner
                ))),
            }
        }
    }
}
