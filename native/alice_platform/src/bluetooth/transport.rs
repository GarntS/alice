//! BlueZ transport boundary.
//!
//! The runtime service owns the concrete BlueZ session; tests use
//! `FakeBluetoothTransport` and never need D-Bus, BlueZ, or Bluetooth hardware.

use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdapterObservation {
    pub id: String,
    pub powered: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceObservation {
    pub adapter_id: String,
    pub address: String,
    pub alias: Option<String>,
    pub name: Option<String>,
    pub class: Option<u32>,
    pub appearance: Option<u16>,
    pub paired: bool,
    pub trusted: bool,
    pub connected: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BluetoothTransportError(pub String);

impl std::fmt::Display for BluetoothTransportError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::error::Error for BluetoothTransportError {}

/// The synchronous observation seam used by cache aggregation. Commands are
/// added here as the Bluetooth service is implemented, keeping BlueZ out of
/// snapshot assembly and unit tests.
pub trait BluetoothTransport {
    fn bluez_available(&self) -> Result<bool, BluetoothTransportError>;
    fn adapters(&self) -> Result<Vec<AdapterObservation>, BluetoothTransportError>;
    fn devices(&self, adapter_id: &str) -> Result<Vec<DeviceObservation>, BluetoothTransportError>;
}

/// Concrete BlueZ entry point. It deliberately does no work until the runtime
/// service asks it to open a session.
pub struct BluezTransport;

impl BluezTransport {
    pub async fn probe() -> Result<(), BluetoothTransportError> {
        bluer::Session::new()
            .await
            .map(|_| ())
            .map_err(|error| BluetoothTransportError(error.to_string()))
    }
}

/// A deterministic, in-memory transport for native tests.
#[derive(Debug, Clone)]
pub struct FakeBluetoothTransport {
    pub available: Result<bool, BluetoothTransportError>,
    pub adapter_rows: Result<Vec<AdapterObservation>, BluetoothTransportError>,
    pub device_rows: BTreeMap<String, Result<Vec<DeviceObservation>, BluetoothTransportError>>,
}

impl Default for FakeBluetoothTransport {
    fn default() -> Self {
        Self {
            available: Ok(false),
            adapter_rows: Ok(vec![]),
            device_rows: BTreeMap::new(),
        }
    }
}

impl BluetoothTransport for FakeBluetoothTransport {
    fn bluez_available(&self) -> Result<bool, BluetoothTransportError> {
        self.available.clone()
    }

    fn adapters(&self) -> Result<Vec<AdapterObservation>, BluetoothTransportError> {
        self.adapter_rows.clone()
    }

    fn devices(&self, adapter_id: &str) -> Result<Vec<DeviceObservation>, BluetoothTransportError> {
        self.device_rows
            .get(adapter_id)
            .cloned()
            .unwrap_or(Ok(vec![]))
    }
}

/// A runtime-owned, snapshot-safe cache. Reads and writes are intentionally
/// independent from the transport so snapshot construction cannot cause D-Bus
/// I/O.
#[derive(Clone)]
pub struct BluetoothCache<T>(Arc<Mutex<T>>);

impl<T: Default> Default for BluetoothCache<T> {
    fn default() -> Self {
        Self(Arc::new(Mutex::new(T::default())))
    }
}

impl<T: Clone + PartialEq> BluetoothCache<T> {
    pub fn snapshot(&self) -> T {
        self.0
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn update(&self, update: impl FnOnce(&mut T)) -> bool {
        let mut current = self.0.lock().unwrap_or_else(|error| error.into_inner());
        let previous = current.clone();
        update(&mut current);
        *current != previous
    }

    pub fn set(&self, next: T) -> bool {
        let mut current = self.0.lock().unwrap_or_else(|error| error.into_inner());
        if *current == next {
            return false;
        }
        *current = next;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_transport_and_cache_do_not_require_bluez() {
        let fake = FakeBluetoothTransport {
            available: Ok(true),
            adapter_rows: Ok(vec![AdapterObservation {
                id: "hci0".into(),
                powered: true,
            }]),
            device_rows: BTreeMap::new(),
        };
        assert!(fake.bluez_available().unwrap());
        assert_eq!(fake.adapters().unwrap().len(), 1);

        let cache = BluetoothCache::<Vec<String>>::default();
        assert!(cache.set(vec!["cached".into()]));
        assert!(!cache.set(vec!["cached".into()]));
        assert_eq!(cache.snapshot(), ["cached"]);
    }
}
