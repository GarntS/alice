use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

use serde::Deserialize;

/// Default commented configuration template written on first run.
pub const DEFAULT_CONFIG_TEMPLATE: &str =
    include_str!("../../../assets/config/default_config.yaml");

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AliceConfig {
    pub theme_mode: ThemeMode,
    pub accent_color: String,
    pub show_network_label: bool,
    pub max_visible_tray_items: u32,
    pub time_zones: Vec<TimeZoneConfig>,
    pub power_commands: PowerCommandConfig,
}

impl Default for AliceConfig {
    fn default() -> Self {
        Self {
            theme_mode: ThemeMode::System,
            accent_color: "#4C956C".into(),
            show_network_label: true,
            max_visible_tray_items: 5,
            time_zones: vec![
                TimeZoneConfig {
                    label: "UTC".into(),
                    offset_hours: 0,
                },
                TimeZoneConfig {
                    label: "AEST".into(),
                    offset_hours: 10,
                },
            ],
            power_commands: PowerCommandConfig {
                lock: "loginctl lock-session".into(),
                lock_and_suspend: "loginctl lock-session && systemctl suspend".into(),
                restart: "systemctl reboot".into(),
                poweroff: "systemctl poweroff".into(),
            },
        }
    }
}

impl AliceConfig {
    pub fn load_or_create_default(path: &Path) -> Result<Self, ConfigError> {
        ensure_default_config(path)?;
        let contents = fs::read_to_string(path)?;
        Self::from_yaml_str(&contents)
    }

    pub fn from_yaml_str(yaml: &str) -> Result<Self, ConfigError> {
        let raw: RawConfig = serde_yaml::from_str(yaml)
            .map_err(|error| ConfigError::new(format!("failed to parse config: {error}")))?;
        Ok(raw.into_config())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeMode {
    System,
    Light,
    Dark,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimeZoneConfig {
    pub label: String,
    pub offset_hours: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PowerCommandConfig {
    pub lock: String,
    pub lock_and_suspend: String,
    pub restart: String,
    pub poweroff: String,
}

pub fn default_config_path() -> Result<PathBuf, ConfigError> {
    let base = match env::var_os("XDG_CONFIG_HOME") {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => {
            let home = env::var_os("HOME")
                .ok_or_else(|| ConfigError::new("HOME is not set and XDG_CONFIG_HOME is unset"))?;
            PathBuf::from(home).join(".config")
        }
    };

    Ok(base.join("alice").join("config.yaml"))
}

pub fn ensure_default_config(path: &Path) -> Result<bool, ConfigError> {
    if path.exists() {
        return Ok(false);
    }

    let parent = path
        .parent()
        .ok_or_else(|| ConfigError::new("config path has no parent directory"))?;
    fs::create_dir_all(parent)?;
    fs::write(path, DEFAULT_CONFIG_TEMPLATE)?;
    Ok(true)
}

#[derive(Debug)]
pub struct ConfigError {
    message: String,
}

impl ConfigError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

impl From<io::Error> for ConfigError {
    fn from(value: io::Error) -> Self {
        Self::new(value.to_string())
    }
}

#[derive(Debug, Deserialize)]
struct RawConfig {
    #[serde(default)]
    theme: RawThemeConfig,
    #[serde(default)]
    network: RawNetworkConfig,
    #[serde(default)]
    tray: RawTrayConfig,
    #[serde(default)]
    clock: RawClockConfig,
    #[serde(default)]
    power: RawPowerConfig,
}

impl RawConfig {
    fn into_config(self) -> AliceConfig {
        let defaults = AliceConfig::default();
        let max_visible_tray_items = self.tray.max_visible_items.unwrap_or(5).max(1);
        let time_zones = match self.clock.additional_time_zones {
            Some(time_zones) if !time_zones.is_empty() => time_zones
                .into_iter()
                .map(|zone| TimeZoneConfig {
                    label: if zone.label.trim().is_empty() {
                        "UTC".into()
                    } else {
                        zone.label
                    },
                    offset_hours: zone.offset_hours,
                })
                .collect(),
            _ => defaults.time_zones,
        };

        AliceConfig {
            theme_mode: self.theme.mode.unwrap_or(ThemeMode::System),
            accent_color: normalize_hex_color(
                self.theme
                    .accent
                    .as_deref()
                    .unwrap_or(&defaults.accent_color),
            )
            .unwrap_or(defaults.accent_color),
            show_network_label: self.network.show_label.unwrap_or(true),
            max_visible_tray_items,
            time_zones,
            power_commands: PowerCommandConfig {
                lock: non_empty_or_default(self.power.lock, defaults.power_commands.lock),
                lock_and_suspend: non_empty_or_default(
                    self.power.lock_and_suspend,
                    defaults.power_commands.lock_and_suspend,
                ),
                restart: non_empty_or_default(self.power.restart, defaults.power_commands.restart),
                poweroff: non_empty_or_default(
                    self.power.poweroff,
                    defaults.power_commands.poweroff,
                ),
            },
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawThemeConfig {
    mode: Option<ThemeMode>,
    accent: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
struct RawNetworkConfig {
    show_label: Option<bool>,
}

#[derive(Debug, Default, Deserialize)]
struct RawTrayConfig {
    max_visible_items: Option<u32>,
}

#[derive(Debug, Default, Deserialize)]
struct RawClockConfig {
    additional_time_zones: Option<Vec<RawTimeZoneConfig>>,
}

#[derive(Debug, Default, Deserialize)]
struct RawPowerConfig {
    lock: Option<String>,
    lock_and_suspend: Option<String>,
    restart: Option<String>,
    poweroff: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawTimeZoneConfig {
    label: String,
    offset_hours: i32,
}

impl<'de> Deserialize<'de> for ThemeMode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        match value.as_str() {
            "system" => Ok(Self::System),
            "light" => Ok(Self::Light),
            "dark" => Ok(Self::Dark),
            other => Err(serde::de::Error::custom(format!(
                "unsupported theme mode '{other}'"
            ))),
        }
    }
}

fn non_empty_or_default(value: Option<String>, default: String) -> String {
    match value {
        Some(value) if !value.trim().is_empty() => value,
        _ => default,
    }
}

fn normalize_hex_color(value: &str) -> Option<String> {
    let normalized = value.trim();
    if normalized.len() != 7 || !normalized.starts_with('#') {
        return None;
    }

    if normalized.chars().skip(1).all(|ch| ch.is_ascii_hexdigit()) {
        Some(normalized.to_ascii_uppercase())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn default_template_mentions_core_sections() {
        assert!(DEFAULT_CONFIG_TEMPLATE.contains("theme:"));
        assert!(DEFAULT_CONFIG_TEMPLATE.contains("network:"));
        assert!(DEFAULT_CONFIG_TEMPLATE.contains("tray:"));
        assert!(DEFAULT_CONFIG_TEMPLATE.contains("clock:"));
        assert!(DEFAULT_CONFIG_TEMPLATE.contains("power:"));
    }

    #[test]
    fn defaults_match_the_shipped_template_intent() {
        let config = AliceConfig::default();

        assert_eq!(config.theme_mode, ThemeMode::System);
        assert_eq!(config.accent_color, "#4C956C");
        assert!(config.show_network_label);
        assert_eq!(config.max_visible_tray_items, 5);
        assert_eq!(config.time_zones.len(), 2);
    }

    #[test]
    fn parses_custom_yaml_config() {
        let config = AliceConfig::from_yaml_str(
            r##"
theme:
  mode: dark
  accent: "#112233"
network:
  show_label: false
tray:
  max_visible_items: 8
clock:
  additional_time_zones:
    - label: JST
      offset_hours: 9
power:
  lock: "waylock"
  restart: "reboot-now"
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.theme_mode, ThemeMode::Dark);
        assert_eq!(config.accent_color, "#112233");
        assert!(!config.show_network_label);
        assert_eq!(config.max_visible_tray_items, 8);
        assert_eq!(config.time_zones.len(), 1);
        assert_eq!(config.time_zones[0].label, "JST");
        assert_eq!(config.power_commands.lock, "waylock");
        assert_eq!(config.power_commands.restart, "reboot-now");
        assert_eq!(config.power_commands.poweroff, "systemctl poweroff");
    }

    #[test]
    fn invalid_values_fall_back_to_defaults() {
        let config = AliceConfig::from_yaml_str(
            r##"
theme:
  accent: "banana"
tray:
  max_visible_items: 0
clock:
  additional_time_zones:
    - label: "   "
      offset_hours: -4
power:
  lock: ""
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.accent_color, "#4C956C");
        assert_eq!(config.max_visible_tray_items, 1);
        assert_eq!(config.time_zones[0].label, "UTC");
        assert_eq!(config.power_commands.lock, "loginctl lock-session");
    }

    #[test]
    fn invalid_theme_mode_is_rejected() {
        let error = AliceConfig::from_yaml_str(
            r##"
theme:
  mode: neon
"##,
        )
        .expect_err("invalid mode should fail");

        assert!(error.message().contains("unsupported theme mode"));
    }

    #[test]
    fn ensure_default_config_writes_template_once() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be monotonic enough for test")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-config-test-{unique}"));
        let path = root.join("alice/config.yaml");

        let created = ensure_default_config(&path).expect("config write should succeed");
        let contents = fs::read_to_string(&path).expect("config should be readable");
        let second = ensure_default_config(&path).expect("second write should succeed");

        assert!(created);
        assert!(contents.contains("theme:"));
        assert!(!second);

        fs::remove_dir_all(root).expect("temp config tree should be removable");
    }
}
