use chrono::Local;

use crate::{PlatformError, providers::ClockProvider, state::ClockSnapshot};

pub struct LocalClockProvider;

impl LocalClockProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_now() -> ClockSnapshot {
        let now = Local::now();
        ClockSnapshot {
            time_zone_code: now.format("%Z").to_string(),
            date_label: now.format("%d %b").to_string(),
            time_label: now.format("%H:%M").to_string(),
        }
    }
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
}
