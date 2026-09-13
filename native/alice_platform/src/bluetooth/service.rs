//! Runtime-owned BlueZ availability monitor.
//!
//! The monitor deliberately publishes only cache changes. Snapshot assembly
//! reads that cache and therefore never opens a D-Bus connection itself.

use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
};

use futures_util::{StreamExt, stream::SelectAll};

use crate::{
    bluetooth::{
        aggregation::aggregate_devices,
        transport::{BluetoothCache, DeviceObservation},
    },
    runtime::Trigger,
    state::BluetoothSnapshot,
};

pub type BluetoothSnapshotCache = BluetoothCache<BluetoothSnapshot>;

#[derive(Clone, Default)]
pub struct CachedBluetoothProvider(BluetoothSnapshotCache);

impl CachedBluetoothProvider {
    pub fn new(cache: BluetoothSnapshotCache) -> Self {
        Self(cache)
    }
}

impl crate::providers::BluetoothProvider for CachedBluetoothProvider {
    fn read_bluetooth(&self) -> Result<BluetoothSnapshot, crate::PlatformError> {
        Ok(self.0.snapshot())
    }
}

/// Monitor BlueZ and adapter power state. A short polling interval makes both
/// BlueZ restarts and adapter power changes observable even when BlueZ drops
/// its D-Bus event stream during a restart. Device property monitoring is added
/// by the command service on the same runtime-owned cache.
pub async fn run_bluetooth_service(
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
) {
    loop {
        let Ok(session) = bluer::Session::new().await else {
            DEFAULT_AGENT_OWNED.store(false, Ordering::Release);
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            continue;
        };
        let broker = crate::bluetooth::prompt::PromptBroker::new(cache.clone(), trigger.clone());
        install_prompt_broker(broker.clone());
        // The handle is deliberately retained for this connected BlueZ session;
        // dropping it unregisters Alice's agent automatically on service loss.
        // Never rely on BlueR's empty-agent behavior: all unexpected requests
        // are explicitly rejected until the tokenized Flutter prompt broker is
        // installed below.
        let agent = session
            .register_agent(bluer::agent::Agent {
                request_default: true,
                request_pin_code: Some(Box::new(move |request| {
                    let broker = broker.clone();
                    Box::pin(async move {
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::RequestPinCode,
                                None,
                                None,
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::PinCode(pin)) => Ok(pin),
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                request_passkey: Some(Box::new(|request| {
                    Box::pin(async move {
                        let broker =
                            active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::RequestPasskey,
                                None,
                                None,
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::Passkey(passkey)) => {
                                Ok(passkey)
                            }
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                display_pin_code: Some(Box::new(|request| Box::pin(async move {
                    let broker = active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                    let response = broker.open(request.device.to_string(), request.device.to_string(), crate::state::BluetoothPromptKind::DisplayPasskey, request.pincode.parse().ok(), None).map_err(|_| bluer::agent::ReqError::Rejected)?;
                    tokio::select! {
                        response = response => match response { Ok(crate::bluetooth::prompt::PromptResponse::Accept) => Ok(()), _ => Err(bluer::agent::ReqError::Rejected) },
                        _ = request.cancel => { broker.cancel(); Err(bluer::agent::ReqError::Canceled) },
                    }
                }))),
                display_passkey: Some(Box::new(|request| {
                    Box::pin(async move {
                        let broker =
                            active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::DisplayPasskey,
                                Some(request.passkey),
                                None,
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::Accept) => Ok(()),
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                request_confirmation: Some(Box::new(|request| {
                    Box::pin(async move {
                        let broker =
                            active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::RequestConfirmation,
                                Some(request.passkey),
                                None,
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::Accept) => Ok(()),
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                request_authorization: Some(Box::new(|request| {
                    Box::pin(async move {
                        let broker =
                            active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::AuthorizeDevice,
                                None,
                                None,
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::Accept) => Ok(()),
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                authorize_service: Some(Box::new(|request| {
                    Box::pin(async move {
                        let broker =
                            active_prompt_broker().ok_or(bluer::agent::ReqError::Rejected)?;
                        let response = broker
                            .open(
                                request.device.to_string(),
                                request.device.to_string(),
                                crate::state::BluetoothPromptKind::AuthorizeService,
                                None,
                                Some(request.service.to_string()),
                            )
                            .map_err(|_| bluer::agent::ReqError::Rejected)?;
                        match response.await {
                            Ok(crate::bluetooth::prompt::PromptResponse::Accept) => Ok(()),
                            _ => Err(bluer::agent::ReqError::Rejected),
                        }
                    })
                })),
                ..Default::default()
            })
            .await;
        DEFAULT_AGENT_OWNED.store(agent.is_ok(), Ordering::Release);
        while let Ok(next) = observed_availability_for(&session).await {
            if cache.update(|current| merge_observed(current, next.clone()))
                && trigger.send(Trigger::Event).await.is_err()
            {
                return;
            }
            if !next.available {
                break;
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        }
        drop(agent);
        DEFAULT_AGENT_OWNED.store(false, Ordering::Release);
    }
}

static ADDRESS_LOCKS: OnceLock<Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>> =
    OnceLock::new();
static DEFAULT_AGENT_OWNED: AtomicBool = AtomicBool::new(false);
static PROMPT_BROKER: OnceLock<Mutex<Option<crate::bluetooth::prompt::PromptBroker>>> =
    OnceLock::new();
static COMMAND_CONTEXT: OnceLock<(BluetoothSnapshotCache, tokio::sync::mpsc::Sender<Trigger>)> =
    OnceLock::new();

pub fn install_command_context(
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
) {
    let _ = COMMAND_CONTEXT.set((cache, trigger));
}

pub fn request_global_scan() -> bool {
    let Some((cache, trigger)) = COMMAND_CONTEXT.get().cloned() else {
        return false;
    };
    let Some(runtime) = crate::runtime::tokio_handle() else {
        return false;
    };
    runtime.spawn(scan_powered_adapters(cache, trigger));
    true
}

pub fn request_global_connect(address: String) -> bool {
    let Some((cache, trigger)) = COMMAND_CONTEXT.get().cloned() else {
        return false;
    };
    let Some(runtime) = crate::runtime::tokio_handle() else {
        return false;
    };
    runtime.spawn(connect_device(cache, trigger, address));
    true
}

pub fn request_global_disconnect(address: String) -> bool {
    let Some((cache, trigger)) = COMMAND_CONTEXT.get().cloned() else {
        return false;
    };
    let Some(runtime) = crate::runtime::tokio_handle() else {
        return false;
    };
    runtime.spawn(disconnect_device(cache, trigger, address));
    true
}

fn install_prompt_broker(broker: crate::bluetooth::prompt::PromptBroker) {
    *PROMPT_BROKER
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = Some(broker);
}

fn active_prompt_broker() -> Option<crate::bluetooth::prompt::PromptBroker> {
    PROMPT_BROKER
        .get()
        .and_then(|broker| broker.lock().ok().and_then(|broker| broker.clone()))
}

pub fn respond_to_prompt(
    token: String,
    response: crate::bluetooth::prompt::PromptResponse,
) -> bool {
    active_prompt_broker().is_some_and(|broker| broker.respond(&token, response))
}

fn default_agent_owned() -> bool {
    DEFAULT_AGENT_OWNED.load(Ordering::Acquire)
}

fn address_lock(address: &str) -> Arc<tokio::sync::Mutex<()>> {
    let locks = ADDRESS_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    locks
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .entry(address.into())
        .or_default()
        .clone()
}

/// Connect an address through the matching powered adapter. Conflicting work
/// for that address waits on one mutex while unrelated devices proceed.
pub async fn connect_device(
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
    address: String,
) {
    let lock = address_lock(&address);
    let _guard = lock.lock().await;
    let result = connect_device_inner(&cache, &trigger, &address).await;
    if let Err(error) = result {
        finish_operation(&cache, &trigger, &address, Some(error)).await;
    }
}

/// Disconnect an address through the matching powered adapter.
pub async fn disconnect_device(
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
    address: String,
) {
    let lock = address_lock(&address);
    let _guard = lock.lock().await;
    set_operation(
        &cache,
        &trigger,
        &address,
        crate::state::BluetoothOperationState::Disconnecting,
        None,
    )
    .await;
    let result = async {
        let (device, _) = find_powered_device(&address).await?;
        device.disconnect().await.map_err(|error| error.to_string())
    }
    .await;
    if let Err(error) = result {
        finish_operation(&cache, &trigger, &address, Some(error)).await;
    }
}

async fn connect_device_inner(
    cache: &BluetoothSnapshotCache,
    trigger: &tokio::sync::mpsc::Sender<Trigger>,
    address: &str,
) -> Result<(), String> {
    let (device, paired) = find_powered_device(address).await?;
    if !paired && !default_agent_owned() {
        return Err("Alice could not acquire BlueZ default-agent ownership".into());
    }
    if !paired {
        set_operation(
            cache,
            trigger,
            address,
            crate::state::BluetoothOperationState::Pairing,
            None,
        )
        .await;
        device.pair().await.map_err(|error| error.to_string())?;
        device
            .set_trusted(true)
            .await
            .map_err(|error| error.to_string())?;
    }
    set_operation(
        cache,
        trigger,
        address,
        crate::state::BluetoothOperationState::Connecting,
        None,
    )
    .await;
    device.connect().await.map_err(|error| error.to_string())
}

async fn find_powered_device(address: &str) -> Result<(bluer::Device, bool), String> {
    let address = address
        .parse()
        .map_err(|_| "Invalid Bluetooth address".to_string())?;
    let session = bluer::Session::new()
        .await
        .map_err(|error| error.to_string())?;
    for name in session
        .adapter_names()
        .await
        .map_err(|error| error.to_string())?
    {
        let adapter = session.adapter(&name).map_err(|error| error.to_string())?;
        if adapter.is_powered().await.unwrap_or(false) {
            let device = adapter.device(address).map_err(|error| error.to_string())?;
            if device.remote_address().await.is_ok() {
                let paired = device.is_paired().await.unwrap_or(false);
                return Ok((device, paired));
            }
        }
    }
    Err("Bluetooth device is unavailable".into())
}

async fn set_operation(
    cache: &BluetoothSnapshotCache,
    trigger: &tokio::sync::mpsc::Sender<Trigger>,
    address: &str,
    operation: crate::state::BluetoothOperationState,
    error: Option<crate::state::BluetoothOperationError>,
) {
    if cache.update(|snapshot| update_device_state(snapshot, address, operation, error)) {
        let _ = trigger.send(Trigger::Event).await;
    }
}

async fn finish_operation(
    cache: &BluetoothSnapshotCache,
    trigger: &tokio::sync::mpsc::Sender<Trigger>,
    address: &str,
    failure: Option<String>,
) {
    set_operation(
        cache,
        trigger,
        address,
        crate::state::BluetoothOperationState::Idle,
        failure.map(|message| crate::state::BluetoothOperationError {
            message,
            retryable: true,
        }),
    )
    .await;
}

fn update_device_state(
    snapshot: &mut BluetoothSnapshot,
    address: &str,
    operation: crate::state::BluetoothOperationState,
    error: Option<crate::state::BluetoothOperationError>,
) {
    for device in snapshot
        .devices
        .iter_mut()
        .chain(snapshot.scan_results.iter_mut())
    {
        if device.address == address {
            device.operation = operation;
            device.error = error.clone();
        }
    }
}

/// Discover on every currently powered adapter for exactly 15 seconds. Each
/// `bluer` discovery stream owns its session and stopping/dropping it releases
/// only Alice's discovery request.
pub async fn scan_powered_adapters(
    cache: BluetoothSnapshotCache,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
) {
    cache.update(|snapshot| {
        snapshot.scan_state = crate::state::BluetoothScanState::Scanning;
        snapshot.scan_results.clear();
    });
    if trigger.send(Trigger::Event).await.is_err() {
        return;
    }

    let Ok(session) = bluer::Session::new().await else {
        finish_scan(&cache, &trigger).await;
        return;
    };
    let Ok(names) = session.adapter_names().await else {
        finish_scan(&cache, &trigger).await;
        return;
    };
    let mut streams = SelectAll::new();
    for name in names {
        let Ok(adapter) = session.adapter(&name) else {
            continue;
        };
        if !adapter.is_powered().await.unwrap_or(false) {
            continue;
        }
        if let Ok(stream) = adapter.discover_devices_with_changes().await {
            streams.push(Box::pin(
                stream.map(move |event| (adapter.clone(), name.clone(), event)),
            ));
        }
    }

    let deadline = tokio::time::Instant::now() + tokio::time::Duration::from_secs(15);
    while !streams.is_empty() {
        tokio::select! {
            _ = tokio::time::sleep_until(deadline) => break,
            event = streams.next() => match event {
                Some((adapter, adapter_id, bluer::AdapterEvent::DeviceAdded(address))) => {
                    if let Some(device) = read_device(&adapter, adapter_id, address).await {
                        cache.update(|snapshot| {
                            let device = aggregate_devices([device]).pop().expect("one observation creates one device");
                            if let Some(existing) = snapshot.scan_results.iter_mut().find(|row| row.address == device.address) {
                                *existing = device;
                            } else {
                                snapshot.scan_results.push(device);
                                snapshot.scan_results.sort_by(|left, right| left.address.cmp(&right.address));
                            }
                        });
                        if trigger.send(Trigger::Event).await.is_err() { return; }
                    }
                }
                Some(_) => {},
                None => break,
            }
        }
    }
    // Drop all streams before publishing completion to release Alice-owned
    // discovery sessions immediately.
    drop(streams);
    finish_scan(&cache, &trigger).await;
}

async fn finish_scan(cache: &BluetoothSnapshotCache, trigger: &tokio::sync::mpsc::Sender<Trigger>) {
    if cache.update(|snapshot| snapshot.scan_state = crate::state::BluetoothScanState::Idle) {
        let _ = trigger.send(Trigger::Event).await;
    }
}

async fn read_device(
    adapter: &bluer::Adapter,
    adapter_id: String,
    address: bluer::Address,
) -> Option<DeviceObservation> {
    let device = adapter.device(address).ok()?;
    Some(DeviceObservation {
        adapter_id,
        address: address.to_string(),
        alias: device.alias().await.ok(),
        name: device.name().await.ok().flatten(),
        class: device.class().await.ok().flatten(),
        appearance: device.appearance().await.ok().flatten(),
        paired: device.is_paired().await.unwrap_or(false),
        trusted: device.is_trusted().await.unwrap_or(false),
        connected: device.is_connected().await.unwrap_or(false),
    })
}

async fn observed_availability_for(
    session: &bluer::Session,
) -> Result<BluetoothSnapshot, bluer::Error> {
    let names = session.adapter_names().await?;
    let mut observations = vec![];
    let mut has_powered_adapter = false;
    for name in names {
        let Ok(adapter) = session.adapter(&name) else {
            continue;
        };
        if !adapter.is_powered().await.unwrap_or(false) {
            continue;
        }
        has_powered_adapter = true;
        let Ok(addresses) = adapter.device_addresses().await else {
            continue;
        };
        for address in addresses {
            let Ok(device) = adapter.device(address) else {
                continue;
            };
            observations.push(DeviceObservation {
                adapter_id: name.clone(),
                address: address.to_string(),
                alias: device.alias().await.ok(),
                name: device.name().await.ok().flatten(),
                class: device.class().await.ok().flatten(),
                appearance: device.appearance().await.ok().flatten(),
                paired: device.is_paired().await.unwrap_or(false),
                trusted: device.is_trusted().await.unwrap_or(false),
                connected: device.is_connected().await.unwrap_or(false),
            });
        }
    }
    Ok(BluetoothSnapshot {
        available: has_powered_adapter,
        devices: aggregate_devices(observations),
        ..BluetoothSnapshot::default()
    })
}

fn merge_observed(current: &mut BluetoothSnapshot, mut observed: BluetoothSnapshot) {
    // Adapter or service loss cancels active work and leaves a retryable error
    // instead of reporting stale progress.
    if !observed.available {
        for mut device in current.devices.clone() {
            if device.operation != crate::state::BluetoothOperationState::Idle {
                device.operation = crate::state::BluetoothOperationState::Idle;
                device.error = Some(crate::state::BluetoothOperationError {
                    message: "Bluetooth service or adapter became unavailable".into(),
                    retryable: true,
                });
                observed.devices.push(device);
            }
        }
    }
    // The monitor owns availability and observed properties, while commands own
    // transient scan, operation, error, and prompt state.
    for device in &mut observed.devices {
        if let Some(previous) = current
            .devices
            .iter()
            .find(|old| old.address == device.address)
        {
            device.operation = match previous.operation {
                crate::state::BluetoothOperationState::Pairing
                | crate::state::BluetoothOperationState::Connecting
                    if device.connected =>
                {
                    crate::state::BluetoothOperationState::Idle
                }
                crate::state::BluetoothOperationState::Disconnecting if !device.connected => {
                    crate::state::BluetoothOperationState::Idle
                }
                operation => operation,
            };
            device.error = previous.error.clone();
        }
    }
    observed.scan_state = current.scan_state;
    observed.scan_results = current.scan_results.clone();
    observed.prompt = current.prompt.clone();
    *current = observed;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_cache_represents_unavailable_bluetooth() {
        let cache = BluetoothSnapshotCache::default();
        assert!(!cache.snapshot().available);
    }
}
