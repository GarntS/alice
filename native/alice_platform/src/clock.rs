use chrono::Local;
use chrono_tz::Tz;
use std::fs;

use crate::{PlatformError, providers::ClockProvider, state::ClockSnapshot};

pub struct LocalClockProvider;

impl LocalClockProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_now() -> ClockSnapshot {
        let now = Local::now();
        let time_zone_code = local_time_zone_abbrev(&now);
        ClockSnapshot {
            time_zone_code,
            date_label: now.format("%d %b").to_string(),
            time_label: now.format("%H:%M").to_string(),
        }
    }
}

fn local_time_zone_abbrev(now: &chrono::DateTime<Local>) -> String {
    let abbrev = now.format("%Z").to_string();
    if is_short_time_zone_code(&abbrev) {
        return abbrev.trim().to_string();
    }

    if let Some(tz_name) = system_time_zone_name() {
        if let Ok(time_zone) = tz_name.parse::<Tz>() {
            let tz_abbrev = now.with_timezone(&time_zone).format("%Z").to_string();
            if is_short_time_zone_code(&tz_abbrev) {
                return tz_abbrev.trim().to_string();
            }
        }
    }

    let offset_hours = now.offset().local_minus_utc() / 3600;
    if let Some(mapped) = offset_hours_to_abbrev(offset_hours) {
        return mapped;
    }

    abbrev.trim().to_string()
}

fn system_time_zone_name() -> Option<String> {
    if let Ok(tz) = std::env::var("TZ") {
        let trimmed = tz.trim();
        if !trimmed.is_empty() {
            let cleaned = trimmed.trim_start_matches(':');
            if cleaned == "/etc/localtime" {
                // Fall through to the /etc/localtime resolution below.
            } else if let Some(name) = extract_zoneinfo_name(cleaned) {
                return Some(name);
            } else {
                return Some(cleaned.to_string());
            }
        }
    }

    if let Ok(path) = fs::read_link("/etc/localtime") {
        let path_str = path.to_string_lossy();
        if let Some(name) = extract_zoneinfo_name(&path_str) {
            return Some(name);
        }
    }

    if let Ok(contents) = fs::read_to_string("/etc/timezone") {
        let trimmed = contents.trim();
        if !trimmed.is_empty() {
            if let Some(name) = extract_zoneinfo_name(trimmed) {
                return Some(name);
            }
            return Some(trimmed.to_string());
        }
    }

    None
}

fn is_short_time_zone_code(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return false;
    }
    let has_offset_chars = trimmed
        .chars()
        .any(|ch| ch.is_ascii_digit() || matches!(ch, ':' | '+' | '-'));
    let has_letters = trimmed.chars().any(|ch| ch.is_ascii_alphabetic());
    has_letters && !has_offset_chars
}

fn extract_zoneinfo_name(value: &str) -> Option<String> {
    let mut name = if let Some(zoneinfo_index) = value.find("zoneinfo/") {
        &value[zoneinfo_index + "zoneinfo/".len()..]
    } else {
        value
    };
    if let Some(stripped) = name.strip_prefix("posix/") {
        name = stripped;
    } else if let Some(stripped) = name.strip_prefix("right/") {
        name = stripped;
    }
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

fn offset_hours_to_abbrev(offset_hours: i32) -> Option<String> {
    let abbrev = match offset_hours {
        0 => "UTC",
        1 => "CET",
        2 => "EET",
        3 => "EEST",
        9 => "JST",
        10 => "AEST",
        11 => "AEDT",
        -4 => "EDT",
        -5 => "EST",
        -6 => "CST",
        -7 => "MST",
        -8 => "PST",
        _ => return None,
    };
    Some(abbrev.into())
}

impl ClockProvider for LocalClockProvider {
    fn read_clock(&self) -> Result<ClockSnapshot, PlatformError> {
        Ok(Self::read_now())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_clock_provider_returns_non_empty_labels() {
        let snapshot = LocalClockProvider::read_now();
        assert!(!snapshot.time_zone_code.is_empty());
        assert!(!snapshot.date_label.is_empty());
        assert!(!snapshot.time_label.is_empty());
    }

    #[test]
    fn extract_zoneinfo_name_normalizes_paths() {
        assert_eq!(
            extract_zoneinfo_name("America/New_York"),
            Some("America/New_York".to_string())
        );
        assert_eq!(
            extract_zoneinfo_name("/usr/share/zoneinfo/America/New_York"),
            Some("America/New_York".to_string())
        );
        assert_eq!(
            extract_zoneinfo_name("/usr/share/zoneinfo/posix/America/New_York"),
            Some("America/New_York".to_string())
        );
        assert_eq!(
            extract_zoneinfo_name("/usr/share/zoneinfo/right/America/New_York"),
            Some("America/New_York".to_string())
        );
        assert_eq!(extract_zoneinfo_name(""), None);
    }
}
