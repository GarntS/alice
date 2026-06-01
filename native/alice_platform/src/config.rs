use std::{
    env, fs, io,
    path::{Path, PathBuf},
};

use chrono::{Offset, Utc};
use chrono_tz::Tz;
use serde::Deserialize;

/// Default commented configuration template written on first run.
pub const DEFAULT_CONFIG_TEMPLATE: &str =
    include_str!("../../../assets/config/default_config.yaml");

#[derive(Debug, Clone, PartialEq)]
pub struct AliceConfig {
    pub theme_mode: ThemeMode,
    pub accent_color: String,
    pub transparent_top_bar: bool,
    pub show_network_label: bool,
    pub max_visible_tray_items: u32,
    pub local_time_zone_label: Option<String>,
    pub time_zones: Vec<TimeZoneConfig>,
    pub power_commands: PowerCommandConfig,
    pub panel_top_gap_px: u32,
    pub calendar: Option<CalendarConfig>,
    pub notifications: NotificationConfig,
    pub weather: WeatherConfig,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationConfig {
    /// How long (ms) before the freedesktop server auto-dismisses. 0 = never expire.
    pub default_timeout_ms: u32,
    /// Whether newly received notifications should appear as floating popups.
    pub show_notification_popup: bool,
    /// How long (ms) popup cards remain visible. 0 = never auto-expire.
    pub notification_display_time_ms: u32,
    /// Whether critical notification popups are allowed to auto-expire.
    pub expire_critical_notifications: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarConfig {
    pub google_client_id: String,
    pub google_client_secret: String,
    /// How often (in seconds) to poll for calendar changes via incremental sync.
    pub poll_interval_secs: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WeatherConfig {
    pub enable: bool,
    pub pirate_weather_key: Option<String>,
    pub forecast_lat: Option<f64>,
    pub forecast_long: Option<f64>,
    pub forecast_language: String,
    pub forecast_units: String,
    pub refresh_interval: u32,
    pub location_label: Option<String>,
}

impl WeatherConfig {
    pub fn validated_for_runtime(&self) -> Result<Option<ValidatedWeatherConfig>, String> {
        if !self.enable {
            return Ok(None);
        }

        let key = self
            .pirate_weather_key
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                "weather.pirate_weather_key is required when weather is enabled".to_string()
            })?;
        let forecast_lat = self.forecast_lat.ok_or_else(|| {
            "weather.forecast_lat is required when weather is enabled".to_string()
        })?;
        let forecast_long = self.forecast_long.ok_or_else(|| {
            "weather.forecast_long is required when weather is enabled".to_string()
        })?;

        if !(-90.0..=90.0).contains(&forecast_lat) {
            return Err("weather.forecast_lat must be between -90 and 90".into());
        }
        if !(-180.0..=180.0).contains(&forecast_long) {
            return Err("weather.forecast_long must be between -180 and 180".into());
        }

        Ok(Some(ValidatedWeatherConfig {
            pirate_weather_key: key.to_string(),
            forecast_lat,
            forecast_long,
            forecast_language: non_empty_or_default(
                Some(self.forecast_language.clone()),
                "en".into(),
            ),
            forecast_units: non_empty_or_default(Some(self.forecast_units.clone()), "us".into()),
            refresh_interval: self.refresh_interval.max(300),
        }))
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ValidatedWeatherConfig {
    pub pirate_weather_key: String,
    pub forecast_lat: f64,
    pub forecast_long: f64,
    pub forecast_language: String,
    pub forecast_units: String,
    pub refresh_interval: u32,
}

impl Default for AliceConfig {
    fn default() -> Self {
        Self {
            theme_mode: ThemeMode::System,
            accent_color: "#4C956C".into(),
            transparent_top_bar: false,
            show_network_label: true,
            max_visible_tray_items: 5,
            local_time_zone_label: None,
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
            panel_top_gap_px: 8,
            calendar: None,
            notifications: NotificationConfig {
                default_timeout_ms: 5000,
                show_notification_popup: true,
                notification_display_time_ms: 5000,
                expire_critical_notifications: false,
            },
            weather: WeatherConfig {
                enable: true,
                pirate_weather_key: None,
                forecast_lat: None,
                forecast_long: None,
                forecast_language: "en".into(),
                forecast_units: "us".into(),
                refresh_interval: 3600,
                location_label: None,
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
    #[serde(default)]
    calendar: Option<RawCalendarConfig>,
    #[serde(default)]
    notifications: RawNotificationConfig,
    #[serde(default)]
    weather: RawWeatherConfig,
}

#[derive(Debug, Default, Deserialize)]
struct RawNotificationConfig {
    default_timeout_ms: Option<u32>,
    show_notification_popup: Option<bool>,
    notification_display_time_ms: Option<u32>,
    expire_critical_notifications: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct RawCalendarConfig {
    google_client_id: String,
    google_client_secret: String,
    #[serde(default)]
    poll_interval_secs: Option<u32>,
}

#[derive(Debug, Default, Deserialize)]
struct RawWeatherConfig {
    enable: Option<bool>,
    pirate_weather_key: Option<String>,
    forecast_lat: Option<f64>,
    forecast_long: Option<f64>,
    forecast_language: Option<String>,
    forecast_units: Option<String>,
    refresh_interval: Option<u32>,
    location_label: Option<String>,
}

impl RawConfig {
    fn into_config(self) -> AliceConfig {
        let defaults = AliceConfig::default();
        let max_visible_tray_items = self.tray.max_visible_items.unwrap_or(5).max(1);
        let local_time_zone_label = normalize_optional_label(self.clock.local_time_zone_label);
        let time_zones = match self.clock.additional_time_zones {
            Some(time_zones) if !time_zones.is_empty() => time_zones
                .into_iter()
                .map(resolve_time_zone_config)
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
            transparent_top_bar: self.theme.transparent_top_bar.unwrap_or(false),
            show_network_label: self.network.show_label.unwrap_or(true),
            max_visible_tray_items,
            local_time_zone_label,
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
            panel_top_gap_px: self.theme.panel_top_gap_px.unwrap_or(8),
            calendar: self.calendar.map(|c| CalendarConfig {
                google_client_id: c.google_client_id,
                google_client_secret: c.google_client_secret,
                poll_interval_secs: c.poll_interval_secs.unwrap_or(30).max(1),
            }),
            notifications: NotificationConfig {
                default_timeout_ms: self
                    .notifications
                    .default_timeout_ms
                    .unwrap_or(defaults.notifications.default_timeout_ms),
                show_notification_popup: self
                    .notifications
                    .show_notification_popup
                    .unwrap_or(defaults.notifications.show_notification_popup),
                notification_display_time_ms: self
                    .notifications
                    .notification_display_time_ms
                    .unwrap_or(defaults.notifications.notification_display_time_ms),
                expire_critical_notifications: self
                    .notifications
                    .expire_critical_notifications
                    .unwrap_or(defaults.notifications.expire_critical_notifications),
            },
            weather: WeatherConfig {
                enable: self.weather.enable.unwrap_or(defaults.weather.enable),
                pirate_weather_key: normalize_optional_label(self.weather.pirate_weather_key),
                forecast_lat: self.weather.forecast_lat,
                forecast_long: self.weather.forecast_long,
                forecast_language: non_empty_or_default(
                    self.weather.forecast_language,
                    defaults.weather.forecast_language,
                ),
                forecast_units: non_empty_or_default(
                    self.weather.forecast_units,
                    defaults.weather.forecast_units,
                ),
                refresh_interval: self
                    .weather
                    .refresh_interval
                    .unwrap_or(defaults.weather.refresh_interval)
                    .max(300),
                location_label: normalize_optional_label(self.weather.location_label),
            },
        }
    }
}

#[derive(Debug, Default, Deserialize)]
struct RawThemeConfig {
    mode: Option<ThemeMode>,
    accent: Option<String>,
    transparent_top_bar: Option<bool>,
    panel_top_gap_px: Option<u32>,
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
    local_time_zone_label: Option<String>,
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
    label: Option<String>,
    offset_hours: Option<i32>,
    tz_name: Option<String>,
    tz_abbrev_name: Option<String>,
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

fn normalize_optional_label(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
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

fn resolve_time_zone_config(zone: RawTimeZoneConfig) -> TimeZoneConfig {
    let label_override = zone
        .label
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);

    let tz_name = zone
        .tz_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let tz_abbrev = zone
        .tz_abbrev_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let offset_hours = zone.offset_hours;

    let mut resolved_offset = 0;
    let mut resolved_abbrev = None;

    if let Some(tz_name) = tz_name {
        if let Ok(time_zone) = tz_name.parse::<Tz>() {
            let zoned = Utc::now().with_timezone(&time_zone);
            resolved_offset = zoned.offset().fix().local_minus_utc() / 3600;
            resolved_abbrev = Some(zoned.format("%Z").to_string());
        }
    } else if let Some(abbrev) = tz_abbrev {
        let normalized = abbrev.to_ascii_uppercase();
        resolved_offset = tz_abbrev_offset_hours(&normalized).unwrap_or(0);
        resolved_abbrev = Some(normalized);
    } else if let Some(offset_hours) = offset_hours {
        resolved_offset = offset_hours;
    }

    let label = label_override
        .or(resolved_abbrev)
        .unwrap_or_else(|| format_offset_label(resolved_offset));
    TimeZoneConfig {
        label,
        offset_hours: resolved_offset,
    }
}

fn format_offset_label(offset_hours: i32) -> String {
    if offset_hours == 0 {
        "UTC".into()
    } else {
        format!("UTC{offset_hours:+}")
    }
}

fn tz_abbrev_offset_hours(abbrev: &str) -> Option<i32> {
    match abbrev {
        "UTC" | "GMT" => Some(0),
        "BST" => Some(1),
        "CET" => Some(1),
        "CEST" => Some(2),
        "EET" => Some(2),
        "EEST" => Some(3),
        "IST" => Some(5),
        "JST" => Some(9),
        "AEST" => Some(10),
        "AEDT" => Some(11),
        "PST" => Some(-8),
        "PDT" => Some(-7),
        "MST" => Some(-7),
        "MDT" => Some(-6),
        "CST" => Some(-6),
        "CDT" => Some(-5),
        "EST" => Some(-5),
        "EDT" => Some(-4),
        _ => None,
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
        assert!(!config.transparent_top_bar);
        assert!(config.show_network_label);
        assert_eq!(config.max_visible_tray_items, 5);
        assert_eq!(config.local_time_zone_label, None);
        assert_eq!(config.time_zones.len(), 2);
        assert_eq!(config.notifications.default_timeout_ms, 5000);
        assert!(config.notifications.show_notification_popup);
        assert_eq!(config.notifications.notification_display_time_ms, 5000);
        assert!(!config.notifications.expire_critical_notifications);
        assert!(config.weather.enable);
        assert_eq!(config.weather.pirate_weather_key, None);
        assert_eq!(config.weather.forecast_lat, None);
        assert_eq!(config.weather.forecast_long, None);
        assert_eq!(config.weather.forecast_language, "en");
        assert_eq!(config.weather.forecast_units, "us");
        assert_eq!(config.weather.refresh_interval, 3600);
        assert_eq!(config.weather.location_label, None);
    }

    #[test]
    fn parses_notification_popup_defaults_when_omitted() {
        let config = AliceConfig::from_yaml_str("notifications:\n  default_timeout_ms: 7000\n")
            .expect("yaml should parse");

        assert_eq!(config.notifications.default_timeout_ms, 7000);
        assert!(config.notifications.show_notification_popup);
        assert_eq!(config.notifications.notification_display_time_ms, 5000);
        assert!(!config.notifications.expire_critical_notifications);
    }

    #[test]
    fn parses_explicit_notification_popup_config() {
        let config = AliceConfig::from_yaml_str(
            r##"
notifications:
  default_timeout_ms: 9000
  show_notification_popup: false
  notification_display_time_ms: 0
  expire_critical_notifications: true
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.notifications.default_timeout_ms, 9000);
        assert!(!config.notifications.show_notification_popup);
        assert_eq!(config.notifications.notification_display_time_ms, 0);
        assert!(config.notifications.expire_critical_notifications);
    }

    #[test]
    fn parses_weather_config_defaults_and_validation() {
        let omitted = AliceConfig::from_yaml_str("").expect("empty yaml should parse");
        assert!(omitted.weather.enable);
        assert!(omitted.weather.validated_for_runtime().is_err());

        let disabled = AliceConfig::from_yaml_str(
            r##"
weather:
  enable: false
"##,
        )
        .expect("disabled weather should parse");
        assert!(!disabled.weather.enable);
        assert_eq!(disabled.weather.validated_for_runtime().unwrap(), None);

        let valid = AliceConfig::from_yaml_str(
            r##"
weather:
  pirate_weather_key: "abc123"
  forecast_lat: 43.407
  forecast_long: -70.996
  forecast_language: fr
  forecast_units: ca
  refresh_interval: 120
  location_label: Farmington
"##,
        )
        .expect("valid weather config should parse");
        assert_eq!(valid.weather.refresh_interval, 300);
        assert_eq!(valid.weather.location_label, Some("Farmington".into()));
        let runtime = valid
            .weather
            .validated_for_runtime()
            .expect("valid weather runtime config")
            .expect("weather enabled");
        assert_eq!(runtime.pirate_weather_key, "abc123");
        assert_eq!(runtime.forecast_lat, 43.407);
        assert_eq!(runtime.forecast_long, -70.996);
        assert_eq!(runtime.forecast_language, "fr");
        assert_eq!(runtime.forecast_units, "ca");
        assert_eq!(runtime.refresh_interval, 300);

        let invalid_lat = AliceConfig::from_yaml_str(
            r##"
weather:
  pirate_weather_key: "abc123"
  forecast_lat: 91
  forecast_long: 0
"##,
        )
        .expect("invalid coordinate config should still parse");
        assert!(
            invalid_lat
                .weather
                .validated_for_runtime()
                .expect_err("invalid lat should be rejected")
                .contains("forecast_lat")
        );
    }

    #[test]
    fn parses_custom_yaml_config() {
        let config = AliceConfig::from_yaml_str(
            r##"
theme:
  mode: dark
  accent: "#112233"
  transparent_top_bar: true
network:
  show_label: false
tray:
  max_visible_items: 8
clock:
  local_time_zone_label: ET
  additional_time_zones:
    - label: Tokyo
      tz_abbrev_name: JST
power:
  lock: "waylock"
  restart: "reboot-now"
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.theme_mode, ThemeMode::Dark);
        assert_eq!(config.accent_color, "#112233");
        assert!(config.transparent_top_bar);
        assert!(!config.show_network_label);
        assert_eq!(config.max_visible_tray_items, 8);
        assert_eq!(config.local_time_zone_label, Some("ET".to_string()));
        assert_eq!(config.time_zones.len(), 1);
        assert_eq!(config.time_zones[0].label, "Tokyo");
        assert_eq!(config.time_zones[0].offset_hours, 9);
        assert_eq!(config.power_commands.lock, "waylock");
        assert_eq!(config.power_commands.restart, "reboot-now");
        assert_eq!(config.power_commands.poweroff, "systemctl poweroff");
    }

    #[test]
    fn parses_disabled_transparent_top_bar() {
        let config = AliceConfig::from_yaml_str(
            r##"
theme:
  transparent_top_bar: false
"##,
        )
        .expect("yaml should parse");

        assert!(!config.transparent_top_bar);
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
  local_time_zone_label: "   "
  additional_time_zones:
    - tz_abbrev_name: "   "
      offset_hours: -4
power:
  lock: ""
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.accent_color, "#4C956C");
        assert!(!config.transparent_top_bar);
        assert_eq!(config.max_visible_tray_items, 1);
        assert_eq!(config.local_time_zone_label, None);
        assert_eq!(config.time_zones[0].label, "UTC-4");
        assert_eq!(config.power_commands.lock, "loginctl lock-session");
    }

    #[test]
    fn tz_name_sets_abbreviation_and_offset() {
        let config = AliceConfig::from_yaml_str(
            r##"
clock:
  additional_time_zones:
    - tz_name: UTC
"##,
        )
        .expect("yaml should parse");

        assert_eq!(config.time_zones.len(), 1);
        assert_eq!(config.time_zones[0].label, "UTC");
        assert_eq!(config.time_zones[0].offset_hours, 0);
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
    fn load_or_create_default_reads_existing_explicit_path() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be monotonic enough for test")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-existing-config-test-{unique}"));
        let path = root.join("alice/config.yaml");
        fs::create_dir_all(path.parent().expect("path has parent"))
            .expect("temp config tree should be creatable");
        fs::write(
            &path,
            r##"
theme:
  mode: light
  accent: "#00ff00"
network:
  show_label: false
"##,
        )
        .expect("config should be writable");

        let config = AliceConfig::load_or_create_default(&path)
            .expect("existing explicit config should parse");
        assert_eq!(config.theme_mode, ThemeMode::Light);
        assert_eq!(config.accent_color, "#00FF00");
        assert!(!config.show_network_label);

        fs::remove_dir_all(root).expect("temp config tree should be removable");
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
