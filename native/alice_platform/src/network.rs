use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{
    PlatformError,
    providers::NetworkProvider,
    state::{NetworkKind, NetworkSnapshot},
};

pub struct SysNetworkProvider {
    net_root: PathBuf,
}

impl SysNetworkProvider {
    pub fn new() -> Self {
        Self {
            net_root: PathBuf::from("/sys/class/net"),
        }
    }

    pub fn with_net_root(net_root: impl Into<PathBuf>) -> Self {
        Self {
            net_root: net_root.into(),
        }
    }

    fn read_network_from_root(net_root: &Path) -> Result<NetworkSnapshot, PlatformError> {
        let entries = fs::read_dir(net_root).map_err(|error| {
            PlatformError::new(format!("failed to read network devices: {error}"))
        })?;

        let mut wired_connected = false;

        for entry in entries {
            let entry = entry.map_err(|error| {
                PlatformError::new(format!("failed to inspect network device: {error}"))
            })?;
            let interface_name = entry.file_name().to_string_lossy().to_string();
            if interface_name == "lo" {
                continue;
            }

            let interface_path = entry.path();
            if !is_connected(&interface_path) {
                continue;
            }

            if is_wireless(&interface_path) {
                return Ok(NetworkSnapshot {
                    kind: NetworkKind::Wifi,
                    label: interface_name,
                });
            }

            wired_connected = true;
        }

        if wired_connected {
            Ok(NetworkSnapshot {
                kind: NetworkKind::Wired,
                label: "Connected".into(),
            })
        } else {
            Ok(NetworkSnapshot {
                kind: NetworkKind::Disconnected,
                label: "Disconnected".into(),
            })
        }
    }
}

impl NetworkProvider for SysNetworkProvider {
    fn read_network(&self) -> Result<NetworkSnapshot, PlatformError> {
        Self::read_network_from_root(&self.net_root)
    }
}

fn is_connected(interface_path: &Path) -> bool {
    match fs::read_to_string(interface_path.join("operstate")) {
        Ok(state) => {
            let state = state.trim();
            matches!(state, "up" | "unknown")
        }
        Err(_) => false,
    }
}

fn is_wireless(interface_path: &Path) -> bool {
    interface_path.join("wireless").exists()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        env,
        time::{SystemTime, UNIX_EPOCH},
    };

    fn make_interface(root: &Path, name: &str, operstate: &str, wireless: bool) {
        let path = root.join(name);
        fs::create_dir_all(&path).expect("interface dir should be creatable");
        fs::write(path.join("operstate"), operstate).expect("operstate should be writable");
        if wireless {
            fs::create_dir_all(path.join("wireless")).expect("wireless dir should be creatable");
        }
    }

    #[test]
    fn prefers_connected_wifi() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-net-test-{unique}"));
        fs::create_dir_all(&root).expect("temp net root should exist");
        make_interface(&root, "eth0", "up\n", false);
        make_interface(&root, "wlan0", "up\n", true);

        let snapshot =
            SysNetworkProvider::read_network_from_root(&root).expect("network should load");
        assert_eq!(snapshot.kind, NetworkKind::Wifi);
        assert_eq!(snapshot.label, "wlan0");

        fs::remove_dir_all(root).expect("temp net root should be removable");
    }

    #[test]
    fn reports_wired_when_no_wifi_is_connected() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-net-test-{unique}"));
        fs::create_dir_all(&root).expect("temp net root should exist");
        make_interface(&root, "eth0", "up\n", false);
        make_interface(&root, "wlan0", "down\n", true);

        let snapshot =
            SysNetworkProvider::read_network_from_root(&root).expect("network should load");
        assert_eq!(snapshot.kind, NetworkKind::Wired);
        assert_eq!(snapshot.label, "Connected");

        fs::remove_dir_all(root).expect("temp net root should be removable");
    }

    #[test]
    fn reports_disconnected_when_no_connected_interfaces_exist() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-net-test-{unique}"));
        fs::create_dir_all(&root).expect("temp net root should exist");
        make_interface(&root, "lo", "up\n", false);
        make_interface(&root, "eth0", "down\n", false);

        let snapshot =
            SysNetworkProvider::read_network_from_root(&root).expect("network should load");
        assert_eq!(snapshot.kind, NetworkKind::Disconnected);
        assert_eq!(snapshot.label, "Disconnected");

        fs::remove_dir_all(root).expect("temp net root should be removable");
    }
}
