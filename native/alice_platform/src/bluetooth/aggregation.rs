use std::collections::{BTreeMap, BTreeSet};

use crate::{
    bluetooth::transport::DeviceObservation,
    state::{
        BluetoothDeviceCategory, BluetoothDevicePresentation, BluetoothDeviceSnapshot,
        BluetoothOperationState,
    },
};

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BluetoothDeviceLists {
    pub connected: Vec<BluetoothDeviceSnapshot>,
    pub known: Vec<BluetoothDeviceSnapshot>,
    pub nearby: Vec<BluetoothDeviceSnapshot>,
}

/// Merge powered-adapter observations using the Bluetooth address as the stable
/// identity. Boolean state is combined so a later adapter observation cannot
/// hide a connection reported by another adapter.
pub fn aggregate_devices(
    rows: impl IntoIterator<Item = DeviceObservation>,
) -> Vec<BluetoothDeviceSnapshot> {
    let mut devices = BTreeMap::<String, BluetoothDeviceSnapshot>::new();
    for row in rows {
        let presentation = BluetoothDevicePresentation {
            class: row.class,
            appearance: row.appearance,
            category: device_category(row.class, row.appearance),
        };
        match devices.get_mut(&row.address) {
            Some(device) => {
                device.alias = non_empty(device.alias.take()).or_else(|| non_empty(row.alias));
                device.name = non_empty(device.name.take()).or_else(|| non_empty(row.name));
                device.paired |= row.paired;
                device.trusted |= row.trusted;
                device.connected |= row.connected;
                if device.presentation.class.is_none() {
                    device.presentation.class = presentation.class;
                }
                if device.presentation.appearance.is_none() {
                    device.presentation.appearance = presentation.appearance;
                }
                if device.presentation.category == BluetoothDeviceCategory::Generic {
                    device.presentation.category = presentation.category;
                }
            }
            None => {
                devices.insert(
                    row.address.clone(),
                    BluetoothDeviceSnapshot {
                        address: row.address,
                        alias: non_empty(row.alias),
                        name: non_empty(row.name),
                        paired: row.paired,
                        trusted: row.trusted,
                        connected: row.connected,
                        presentation,
                        operation: BluetoothOperationState::Idle,
                        error: None,
                    },
                );
            }
        }
    }
    devices.into_values().collect()
}

pub fn device_label(device: &BluetoothDeviceSnapshot) -> String {
    non_empty(device.alias.clone())
        .or_else(|| non_empty(device.name.clone()))
        .unwrap_or_else(|| device.address.clone())
}

pub fn device_category(class: Option<u32>, appearance: Option<u16>) -> BluetoothDeviceCategory {
    if let Some(class) = class {
        match (class >> 8) & 0x1f {
            1 => return BluetoothDeviceCategory::Computer,
            2 => return BluetoothDeviceCategory::Phone,
            4 => return BluetoothDeviceCategory::Audio,
            5 => return BluetoothDeviceCategory::Peripheral,
            7 => return BluetoothDeviceCategory::Wearable,
            _ => {}
        }
    }
    // Bluetooth SIG Appearance values encode a 10-bit category in bits 6..15
    // and a 6-bit subcategory. Every defined subcategory inherits its
    // category's presentation icon.
    match appearance.map(|value| value >> 6) {
        Some(0x001) => BluetoothDeviceCategory::Phone,
        Some(0x002) => BluetoothDeviceCategory::Computer,
        Some(0x003) => BluetoothDeviceCategory::Wearable,
        Some(0x004) => BluetoothDeviceCategory::Clock,
        Some(0x005) | Some(0x028) | Some(0x02b) => BluetoothDeviceCategory::Display,
        Some(0x006) => BluetoothDeviceCategory::Peripheral,
        Some(0x007) => BluetoothDeviceCategory::Wearable,
        Some(0x008) => BluetoothDeviceCategory::Tag,
        Some(0x009) => BluetoothDeviceCategory::Key,
        Some(0x00a) => BluetoothDeviceCategory::Media,
        Some(0x00b) => BluetoothDeviceCategory::Scanner,
        Some(0x00c) => BluetoothDeviceCategory::Temperature,
        Some(0x00d) | Some(0x00e) => BluetoothDeviceCategory::Heart,
        Some(0x00f) => BluetoothDeviceCategory::Input,
        Some(0x010) | Some(0x031..=0x037) => BluetoothDeviceCategory::Health,
        Some(0x011) | Some(0x051) => BluetoothDeviceCategory::Fitness,
        Some(0x012) => BluetoothDeviceCategory::Cycling,
        Some(0x013) => BluetoothDeviceCategory::Controls,
        Some(0x014) => BluetoothDeviceCategory::Network,
        Some(0x015) => BluetoothDeviceCategory::Sensor,
        Some(0x016) | Some(0x01f) => BluetoothDeviceCategory::Light,
        Some(0x017) => BluetoothDeviceCategory::Fan,
        Some(0x018..=0x01a) => BluetoothDeviceCategory::Climate,
        Some(0x01b) => BluetoothDeviceCategory::Heating,
        Some(0x01c) => BluetoothDeviceCategory::Access,
        Some(0x01d) => BluetoothDeviceCategory::Motorized,
        Some(0x01e) => BluetoothDeviceCategory::Power,
        Some(0x020) => BluetoothDeviceCategory::WindowCovering,
        Some(0x021) | Some(0x022) | Some(0x025) | Some(0x027) | Some(0x029) => {
            BluetoothDeviceCategory::Audio
        }
        Some(0x023) => BluetoothDeviceCategory::Vehicle,
        Some(0x024) => BluetoothDeviceCategory::Appliance,
        Some(0x026) => BluetoothDeviceCategory::Aircraft,
        Some(0x02a) => BluetoothDeviceCategory::Gaming,
        Some(0x052) => BluetoothDeviceCategory::Measurement,
        Some(0x053) => BluetoothDeviceCategory::Tools,
        Some(0x054) => BluetoothDeviceCategory::Cookware,
        _ => BluetoothDeviceCategory::Generic,
    }
}

/// Apply connected > known > nearby precedence, retaining each address in one
/// list only. The caller may pass fresh aggregation output and retained scan
/// results independently.
pub fn exclusive_device_lists(
    devices: &[BluetoothDeviceSnapshot],
    scan_results: &[BluetoothDeviceSnapshot],
) -> BluetoothDeviceLists {
    let mut lists = BluetoothDeviceLists::default();
    let mut used = BTreeSet::new();
    for device in devices.iter().filter(|device| device.connected) {
        if used.insert(device.address.clone()) {
            lists.connected.push(device.clone());
        }
    }
    for device in devices
        .iter()
        .filter(|device| device.paired && !device.connected)
    {
        if used.insert(device.address.clone()) {
            lists.known.push(device.clone());
        }
    }
    for device in scan_results {
        if used.insert(device.address.clone()) {
            lists.nearby.push(device.clone());
        }
    }
    lists
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn observation(adapter_id: &str, address: &str) -> DeviceObservation {
        DeviceObservation {
            adapter_id: adapter_id.into(),
            address: address.into(),
            alias: None,
            name: None,
            class: None,
            appearance: None,
            paired: false,
            trusted: false,
            connected: false,
        }
    }

    #[test]
    fn merges_multi_adapter_observations_by_address() {
        let mut first = observation("hci0", "AA:BB");
        first.name = Some("Headphones".into());
        // Appearance category 0x021 (Audio Sink), subcategory 0.
        first.appearance = Some(0x021 << 6);
        let mut second = observation("hci1", "AA:BB");
        second.alias = Some("Desk headphones".into());
        second.paired = true;
        second.connected = true;
        let devices = aggregate_devices([first, second]);

        assert_eq!(devices.len(), 1);
        assert_eq!(device_label(&devices[0]), "Desk headphones");
        assert!(devices[0].paired && devices[0].connected);
        assert_eq!(
            devices[0].presentation.category,
            BluetoothDeviceCategory::Audio
        );
    }

    #[test]
    fn label_and_category_fall_back_to_address_and_generic() {
        let device = aggregate_devices([observation("hci0", "AA:BB")])
            .pop()
            .unwrap();
        assert_eq!(device_label(&device), "AA:BB");
        assert_eq!(
            device.presentation.category,
            BluetoothDeviceCategory::Generic
        );
    }

    #[test]
    fn lists_are_exclusive_and_prefer_connected_then_known() {
        let mut connected = aggregate_devices([observation("hci0", "connected")])
            .pop()
            .unwrap();
        connected.connected = true;
        connected.paired = true;
        let mut known = aggregate_devices([observation("hci0", "known")])
            .pop()
            .unwrap();
        known.paired = true;
        let nearby = aggregate_devices([
            observation("hci0", "connected"),
            observation("hci0", "known"),
            observation("hci0", "nearby"),
        ]);
        let lists = exclusive_device_lists(&[connected, known], &nearby);

        assert_eq!(lists.connected.len(), 1);
        assert_eq!(lists.known.len(), 1);
        assert_eq!(
            lists
                .nearby
                .iter()
                .map(|device| &device.address)
                .collect::<Vec<_>>(),
            ["nearby"]
        );
    }
}
