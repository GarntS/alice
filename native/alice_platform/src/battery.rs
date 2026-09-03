use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{PlatformError, config::BatteryConfig, state::BatterySnapshot};

pub const POWER_SUPPLY_PATH: &str = "/sys/class/power_supply";

pub struct SysfsBatteryProvider {
    root: PathBuf,
    config: BatteryConfig,
}

impl SysfsBatteryProvider {
    pub fn new(config: BatteryConfig) -> Self {
        Self::with_root(config, POWER_SUPPLY_PATH)
    }

    pub fn with_root(config: BatteryConfig, root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            config,
        }
    }

    fn selected_device(&self) -> Option<PathBuf> {
        if let Some(name) = &self.config.device_name {
            return Some(self.root.join(name));
        }
        let mut entries = fs::read_dir(&self.root)
            .ok()?
            .filter_map(Result::ok)
            .collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.file_name());
        entries.into_iter().map(|entry| entry.path()).find(|path| {
            fs::read_to_string(path.join("type"))
                .ok()
                .is_some_and(|kind| kind.trim() == "Battery")
        })
    }

    pub fn read(&self) -> Option<BatterySnapshot> {
        if !self.config.enable {
            return None;
        }
        let device = self.selected_device()?;
        let capacity = fs::read_to_string(device.join("capacity"))
            .ok()?
            .trim()
            .parse::<u8>()
            .ok()?;
        if capacity > 100 {
            return None;
        }
        let status = fs::read_to_string(device.join("status"))
            .ok()?
            .trim()
            .to_owned();
        if status.is_empty() {
            return None;
        }
        Some(BatterySnapshot { capacity, status })
    }
}

impl crate::providers::BatteryProvider for SysfsBatteryProvider {
    fn read_battery(&self) -> Result<Option<BatterySnapshot>, PlatformError> {
        Ok(self.read())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn device(root: &Path, name: &str, kind: &str, capacity: &str, status: &str) {
        let path = root.join(name);
        fs::create_dir(&path).unwrap();
        fs::write(path.join("type"), kind).unwrap();
        fs::write(path.join("capacity"), capacity).unwrap();
        fs::write(path.join("status"), status).unwrap();
    }
    fn config(device_name: Option<&str>) -> BatteryConfig {
        BatteryConfig {
            enable: true,
            device_name: device_name.map(str::to_owned),
        }
    }

    #[test]
    fn auto_discovers_lexical_battery() {
        let tmp = TempDir::new().unwrap();
        device(tmp.path(), "BAT1", "Battery", "80", "Discharging");
        device(tmp.path(), "BAT0", "Battery", "70", "Charging");
        assert_eq!(
            SysfsBatteryProvider::with_root(config(None), tmp.path())
                .read()
                .unwrap()
                .capacity,
            70
        );
    }
    #[test]
    fn configured_device_takes_precedence() {
        let tmp = TempDir::new().unwrap();
        device(tmp.path(), "BAT0", "Battery", "70", "Charging");
        device(tmp.path(), "CUSTOM", "Mains", "12", "Full");
        assert_eq!(
            SysfsBatteryProvider::with_root(config(Some("CUSTOM")), tmp.path())
                .read()
                .unwrap()
                .capacity,
            12
        );
    }
    #[test]
    fn rejects_missing_malformed_and_out_of_range_data() {
        let tmp = TempDir::new().unwrap();
        device(tmp.path(), "BAT0", "Battery", "101", "Charging");
        assert!(
            SysfsBatteryProvider::with_root(config(None), tmp.path())
                .read()
                .is_none()
        );
        fs::write(tmp.path().join("BAT0/capacity"), "bad").unwrap();
        assert!(
            SysfsBatteryProvider::with_root(config(None), tmp.path())
                .read()
                .is_none()
        );
        fs::write(tmp.path().join("BAT0/capacity"), "50").unwrap();
        fs::remove_file(tmp.path().join("BAT0/status")).unwrap();
        assert!(
            SysfsBatteryProvider::with_root(config(None), tmp.path())
                .read()
                .is_none()
        );
        assert!(
            SysfsBatteryProvider::with_root(config(Some("missing")), tmp.path())
                .read()
                .is_none()
        );
    }
}
