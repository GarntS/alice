use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{
    PlatformError,
    providers::{Stats, StatsProvider},
};

pub struct ProcStatsProvider {
    proc_root: PathBuf,
}

impl ProcStatsProvider {
    pub fn new() -> Self {
        Self {
            proc_root: PathBuf::from("/proc"),
        }
    }

    pub fn with_proc_root(proc_root: impl Into<PathBuf>) -> Self {
        Self {
            proc_root: proc_root.into(),
        }
    }

    fn meminfo_path(&self) -> PathBuf {
        self.proc_root.join("meminfo")
    }

    fn stat_path(&self) -> PathBuf {
        self.proc_root.join("stat")
    }

    fn read_stats_from_paths(
        meminfo_path: &Path,
        stat_path: &Path,
    ) -> Result<Stats, PlatformError> {
        let meminfo = fs::read_to_string(meminfo_path)
            .map_err(|error| PlatformError::new(format!("failed to read meminfo: {error}")))?;
        let stat = fs::read_to_string(stat_path)
            .map_err(|error| PlatformError::new(format!("failed to read stat: {error}")))?;

        let memory_usage_percent = parse_memory_usage_percent(&meminfo)?;
        let cpu_usage_cores = parse_cpu_usage_cores(&stat)?;

        Ok(Stats {
            memory_usage_percent,
            cpu_usage_cores,
        })
    }
}

impl StatsProvider for ProcStatsProvider {
    fn read_stats(&self) -> Result<Stats, PlatformError> {
        Self::read_stats_from_paths(&self.meminfo_path(), &self.stat_path())
    }
}

fn parse_memory_usage_percent(meminfo: &str) -> Result<f64, PlatformError> {
    let total_kib = parse_meminfo_value(meminfo, "MemTotal")?;
    let available_kib = parse_meminfo_value(meminfo, "MemAvailable")?;

    if total_kib == 0 {
        return Err(PlatformError::new("MemTotal reported as zero"));
    }

    let used_kib = total_kib.saturating_sub(available_kib);
    Ok((used_kib as f64 / total_kib as f64) * 100.0)
}

fn parse_meminfo_value(meminfo: &str, key: &str) -> Result<u64, PlatformError> {
    let prefix = format!("{key}:");
    let line = meminfo
        .lines()
        .find(|line| line.starts_with(&prefix))
        .ok_or_else(|| PlatformError::new(format!("missing {key} in meminfo")))?;

    let value = line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| PlatformError::new(format!("missing numeric value for {key}")))?;

    value
        .parse::<u64>()
        .map_err(|error| PlatformError::new(format!("invalid {key} value: {error}")))
}

fn parse_cpu_usage_cores(stat: &str) -> Result<f64, PlatformError> {
    let mut total_cores = 0.0;

    for line in stat.lines() {
        if !is_cpu_core_line(line) {
            continue;
        }

        total_cores += parse_cpu_core_usage(line)?;
    }

    Ok(total_cores)
}

fn is_cpu_core_line(line: &str) -> bool {
    let Some(label) = line.split_whitespace().next() else {
        return false;
    };

    label != "cpu"
        && label.starts_with("cpu")
        && label[3..]
            .chars()
            .all(|character| character.is_ascii_digit())
}

fn parse_cpu_core_usage(line: &str) -> Result<f64, PlatformError> {
    let fields = line.split_whitespace().collect::<Vec<_>>();
    if fields.len() < 8 {
        return Err(PlatformError::new("cpu stat line has too few fields"));
    }

    let user = parse_cpu_field(fields[1], "user")?;
    let nice = parse_cpu_field(fields[2], "nice")?;
    let system = parse_cpu_field(fields[3], "system")?;
    let idle = parse_cpu_field(fields[4], "idle")?;
    let iowait = parse_cpu_field(fields[5], "iowait")?;
    let irq = parse_cpu_field(fields[6], "irq")?;
    let softirq = parse_cpu_field(fields[7], "softirq")?;
    let steal = fields
        .get(8)
        .map(|value| parse_cpu_field(value, "steal"))
        .transpose()?
        .unwrap_or(0);

    let active = user + nice + system + irq + softirq + steal;
    let total = active + idle + iowait;

    if total == 0 {
        return Ok(0.0);
    }

    Ok(active as f64 / total as f64)
}

fn parse_cpu_field(value: &str, label: &str) -> Result<u64, PlatformError> {
    value
        .parse::<u64>()
        .map_err(|error| PlatformError::new(format!("invalid cpu {label} field: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        env,
        time::{SystemTime, UNIX_EPOCH},
    };

    #[test]
    fn parses_memory_usage_from_meminfo() {
        let usage = parse_memory_usage_percent(
            "MemTotal:       16000000 kB\nMemAvailable:    4000000 kB\n",
        )
        .expect("meminfo should parse");

        assert_eq!(usage, 75.0);
    }

    #[test]
    fn parses_cpu_usage_cores_from_stat() {
        let usage = parse_cpu_usage_cores(
            "cpu  0 0 0 0 0 0 0 0 0 0\n\
             cpu0 100 0 100 200 0 0 0 0 0 0\n\
             cpu1 100 0 100 200 0 0 0 0 0 0\n",
        )
        .expect("stat should parse");

        assert_eq!(usage, 1.0);
    }

    #[test]
    fn reads_stats_from_custom_proc_root() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be available")
            .as_nanos();
        let root = env::temp_dir().join(format!("alice-proc-test-{unique}"));
        fs::create_dir_all(&root).expect("temp proc dir should be creatable");
        fs::write(
            root.join("meminfo"),
            "MemTotal:       8000000 kB\nMemAvailable:    2000000 kB\n",
        )
        .expect("meminfo should be writable");
        fs::write(
            root.join("stat"),
            "cpu  0 0 0 0 0 0 0 0 0 0\n\
             cpu0 200 0 100 100 0 0 0 0 0 0\n\
             cpu1 50 0 50 300 0 0 0 0 0 0\n",
        )
        .expect("stat should be writable");

        let provider = ProcStatsProvider::with_proc_root(&root);
        let stats = provider.read_stats().expect("stats should load");

        assert_eq!(stats.memory_usage_percent, 75.0);
        assert_eq!(stats.cpu_usage_cores, 1.0);

        fs::remove_dir_all(root).expect("temp proc dir should be removable");
    }
}
