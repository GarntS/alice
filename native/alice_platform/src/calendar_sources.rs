//! Startup-owned calendar source coordinator and iCalendar feed ingestion.
//!
//! Source snapshots are intentionally isolated: a failed refresh never clears a
//! previously accepted snapshot, and callers only ever read the merged store.

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::{Arc, Mutex, OnceLock, RwLock},
    time::Duration,
};

use chrono::{
    DateTime, Datelike, Duration as ChronoDuration, Local, LocalResult, NaiveDate, NaiveDateTime,
    TimeZone, Utc,
};
use chrono_tz::Tz;

use crate::{
    config::{CalendarConfig, CalendarEntry, CalendarEntryKind},
    runtime::Trigger,
    state::CalendarEvent,
};

pub(crate) const ICS_DEFAULT_COLOR: &str = "#E53935";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CalendarOccurrence {
    pub source_id: String,
    pub uid: String,
    /// Stable `(source, UID, recurrence-start)` identity used by the store and
    /// reminder scheduler.
    pub occurrence_id: String,
    pub date: NaiveDate,
    pub starts_at: Option<DateTime<Utc>>,
    pub ends_at: Option<DateTime<Utc>>,
    pub event: CalendarEvent,
    pub alarms: Vec<Alarm>,
    pub notify_for_events: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Alarm {
    Relative {
        seconds_before_start: i64,
        description: String,
    },
    Absolute {
        at: DateTime<Utc>,
        description: String,
    },
}

#[derive(Debug, Clone, Default)]
struct SourceSnapshot {
    occurrences: Vec<CalendarOccurrence>,
    last_error: Option<String>,
}

/// Thread-safe source-scoped event store. It contains no credentials and is
/// safe to query from the FRB request thread.
#[derive(Default)]
pub(crate) struct CalendarCoordinator {
    sources: RwLock<BTreeMap<String, SourceSnapshot>>,
}

impl CalendarCoordinator {
    pub(crate) fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Replace a normalized source snapshot. Source IDs isolate replacement,
    /// so one source can never erase another source's events.
    pub(crate) fn replace_source(&self, source_id: &str, occurrences: Vec<CalendarOccurrence>) {
        if let Ok(mut sources) = self.sources.write() {
            sources.insert(
                source_id.to_string(),
                SourceSnapshot {
                    occurrences,
                    last_error: None,
                },
            );
        }
    }

    /// Publish already-normalized events from a non-ICS source (currently
    /// Google) into the same merged store queried by the clock panel.
    pub(crate) fn replace_events(&self, source_id: &str, entries: Vec<(NaiveDate, CalendarEvent)>) {
        self.replace_source(
            source_id,
            entries
                .into_iter()
                .map(|(date, event)| CalendarOccurrence {
                    occurrence_id: format!("{source_id}:{}", event.id),
                    source_id: source_id.to_owned(),
                    uid: event.id.clone(),
                    date,
                    starts_at: None,
                    ends_at: None,
                    event,
                    alarms: Vec::new(),
                    notify_for_events: false,
                })
                .collect(),
        );
    }

    /// Save a diagnostic without destroying last valid events.
    pub(crate) fn record_failure(&self, source_id: &str, error: impl Into<String>) {
        if let Ok(mut sources) = self.sources.write() {
            sources.entry(source_id.to_string()).or_default().last_error = Some(error.into());
        }
    }

    pub(crate) fn events_for_date(&self, date: NaiveDate) -> Vec<CalendarEvent> {
        let Ok(sources) = self.sources.read() else {
            return Vec::new();
        };
        let mut occurrences = sources
            .values()
            .flat_map(|snapshot| snapshot.occurrences.iter())
            .filter(|occurrence| occurrence.date == date)
            .map(|occurrence| occurrence.event.clone())
            .collect::<Vec<_>>();
        occurrences.sort_by(|left, right| {
            left.start_label
                .cmp(&right.start_label)
                .then_with(|| left.title.cmp(&right.title))
                .then_with(|| left.id.cmp(&right.id))
        });
        occurrences
    }

    #[cfg(test)]
    fn source_error(&self, source_id: &str) -> Option<String> {
        self.sources.read().ok()?.get(source_id)?.last_error.clone()
    }
}

static GLOBAL_COORDINATOR: OnceLock<Arc<CalendarCoordinator>> = OnceLock::new();

pub(crate) fn global_coordinator() -> Option<Arc<CalendarCoordinator>> {
    GLOBAL_COORDINATOR.get().cloned()
}

/// Start source workers once the process runtime exists. Workers refresh
/// immediately and then independently at their source's configured cadence.
pub(crate) fn start_global_coordinator(
    config: &CalendarConfig,
    trigger: tokio::sync::mpsc::Sender<Trigger>,
) {
    let coordinator = GLOBAL_COORDINATOR
        .get_or_init(CalendarCoordinator::new)
        .clone();
    for entry in config.calendars.iter().cloned() {
        if !matches!(entry.kind, CalendarEntryKind::Ics { .. }) {
            continue;
        }
        let coordinator = coordinator.clone();
        let trigger = trigger.clone();
        tokio::spawn(async move {
            loop {
                if let Err(error) = refresh_ics_source(&coordinator, &entry).await {
                    eprintln!("alice: calendar source '{}': {error}", entry.id);
                    coordinator.record_failure(&entry.id, error);
                } else {
                    let _ = trigger.send(Trigger::Event).await;
                }
                tokio::time::sleep(Duration::from_secs(entry.poll_interval_secs as u64)).await;
            }
        });
    }
}

pub(crate) async fn refresh_ics_source(
    coordinator: &CalendarCoordinator,
    entry: &CalendarEntry,
) -> Result<(), String> {
    let source = acquire_ics(entry).await?;
    let window_start = Local::now().date_naive() - ChronoDuration::days(92);
    let window_end = Local::now().date_naive() + ChronoDuration::days(92);
    let occurrences = parse_ics_occurrences(entry, &source, window_start, window_end)?;
    coordinator.replace_source(&entry.id, occurrences.clone());
    schedule_occurrence_notifications(occurrences);
    Ok(())
}

async fn acquire_ics(entry: &CalendarEntry) -> Result<String, String> {
    let CalendarEntryKind::Ics { path, url, .. } = &entry.kind else {
        return Err("not an ICS source".into());
    };
    match (path, url) {
        (Some(path), None) => tokio::fs::read_to_string(path)
            .await
            .map_err(|error| format!("could not read {}: {error}", path.display())),
        (None, Some(url)) => reqwest::get(url)
            .await
            .map_err(|error| format!("could not fetch {url}: {error}"))?
            .error_for_status()
            .map_err(|error| format!("could not fetch {url}: {error}"))?
            .text()
            .await
            .map_err(|error| format!("could not read response from {url}: {error}")),
        _ => Err("ICS source must set exactly one path or HTTP(S) URL".into()),
    }
}

#[derive(Debug, Clone)]
struct Property {
    name: String,
    params: BTreeMap<String, String>,
    value: String,
}

#[derive(Debug, Clone)]
struct RawEvent {
    uid: String,
    summary: String,
    start: IcsTime,
    end: Option<IcsTime>,
    recurrence_id: Option<IcsTime>,
    rrules: Vec<String>,
    rdates: Vec<IcsTime>,
    exdates: Vec<IcsTime>,
    alarms: Vec<RawAlarm>,
}

#[derive(Debug, Clone)]
struct RawAlarm {
    trigger: String,
    trigger_params: BTreeMap<String, String>,
    description: String,
}

#[derive(Debug, Clone)]
enum IcsTime {
    Date(NaiveDate),
    DateTime { local: NaiveDateTime, zone: Zone },
}

#[derive(Debug, Clone)]
enum Zone {
    Utc,
    Named(Tz),
    Fixed(chrono::FixedOffset),
    Local,
}

impl IcsTime {
    fn key(&self) -> String {
        match self {
            Self::Date(date) => date.format("%Y%m%d").to_string(),
            Self::DateTime { local, .. } => local.format("%Y%m%dT%H%M%S").to_string(),
        }
    }

    fn instant(&self) -> Option<DateTime<Utc>> {
        let Self::DateTime { local, zone } = self else {
            return None;
        };
        let utc = match zone {
            Zone::Utc => Utc.from_utc_datetime(local),
            Zone::Named(zone) => match zone.from_local_datetime(local) {
                LocalResult::Single(value) => value.with_timezone(&Utc),
                LocalResult::Ambiguous(first, _) => first.with_timezone(&Utc),
                LocalResult::None => return None,
            },
            Zone::Fixed(offset) => match offset.from_local_datetime(local) {
                LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => {
                    value.with_timezone(&Utc)
                }
                LocalResult::None => return None,
            },
            Zone::Local => match Local.from_local_datetime(local) {
                LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => {
                    value.with_timezone(&Utc)
                }
                LocalResult::None => return None,
            },
        };
        Some(utc)
    }
}

fn parse_ics_occurrences(
    entry: &CalendarEntry,
    source: &str,
    window_start: NaiveDate,
    window_end: NaiveDate,
) -> Result<Vec<CalendarOccurrence>, String> {
    let lines = unfold_lines(source);
    if !lines
        .iter()
        .any(|line| line.eq_ignore_ascii_case("BEGIN:VCALENDAR"))
    {
        return Err("invalid iCalendar data: missing VCALENDAR".into());
    }
    let zones = parse_embedded_zones(&lines);
    let calendar_name = find_calendar_name(&lines).unwrap_or_else(|| entry.id.clone());
    let components = extract_components(&lines, "VEVENT");
    let mut raw_events = Vec::new();
    for (index, component) in components.iter().enumerate() {
        match parse_raw_event(component, index, &zones) {
            Ok(event) => raw_events.push(event),
            Err(error) => eprintln!(
                "alice: calendar source '{}': skipped invalid VEVENT: {error}",
                entry.id
            ),
        }
    }

    let mut detached = BTreeMap::new();
    let mut base = Vec::new();
    for event in raw_events {
        if let Some(recurrence_id) = &event.recurrence_id {
            detached.insert((event.uid.clone(), recurrence_id.key()), event);
        } else {
            base.push(event);
        }
    }

    let mut output = Vec::new();
    for event in base {
        let mut starts = recurrence_starts(&event, window_start, window_end)?;
        starts.sort_by_key(IcsTime::key);
        starts.dedup_by(|left, right| left.key() == right.key());
        for start in starts {
            let source_event = detached
                .remove(&(event.uid.clone(), start.key()))
                .unwrap_or_else(|| event.clone());
            let start = if source_event.recurrence_id.is_some() {
                source_event.start.clone()
            } else {
                start
            };
            if let Some(occurrence) = map_occurrence(entry, &calendar_name, &source_event, start)
                && occurrence.date >= window_start
                && occurrence.date <= window_end
            {
                output.push(occurrence);
            }
        }
    }
    // A detached event whose master was not present still deserves display.
    for (_, event) in detached {
        if let Some(occurrence) = map_occurrence(entry, &calendar_name, &event, event.start.clone())
            && occurrence.date >= window_start
            && occurrence.date <= window_end
        {
            output.push(occurrence);
        }
    }
    Ok(output)
}

fn map_occurrence(
    entry: &CalendarEntry,
    calendar_name: &str,
    event: &RawEvent,
    start: IcsTime,
) -> Option<CalendarOccurrence> {
    let (date, starts_at, is_all_day, start_label) = match &start {
        IcsTime::Date(date) => (*date, None, true, String::new()),
        IcsTime::DateTime { .. } => {
            let instant = start.instant()?;
            let local = instant.with_timezone(&Local);
            (
                local.date_naive(),
                Some(instant),
                false,
                local.format("%H:%M").to_string(),
            )
        }
    };
    let ends_at = event.end.as_ref().and_then(IcsTime::instant);
    let end_label = ends_at
        .map(|instant| instant.with_timezone(&Local).format("%H:%M").to_string())
        .unwrap_or_default();
    let alarms = parse_alarms(&event.alarms, starts_at);
    let color = entry
        .color
        .clone()
        .unwrap_or_else(|| ICS_DEFAULT_COLOR.into());
    Some(CalendarOccurrence {
        source_id: entry.id.clone(),
        uid: event.uid.clone(),
        occurrence_id: format!("{}:{}:{}", entry.id, event.uid, start.key()),
        date,
        starts_at,
        ends_at,
        event: CalendarEvent {
            id: format!("{}:{}:{}", entry.id, event.uid, start.key()),
            title: event.summary.clone(),
            is_all_day,
            start_label,
            end_label,
            calendar_name: calendar_name.to_string(),
            calendar_color: color,
        },
        alarms,
        notify_for_events: matches!(
            entry.kind,
            CalendarEntryKind::Ics {
                notify_for_events: true,
                ..
            }
        ),
    })
}

fn recurrence_starts(
    event: &RawEvent,
    window_start: NaiveDate,
    window_end: NaiveDate,
) -> Result<Vec<IcsTime>, String> {
    let mut occurrences = vec![event.start.clone()];
    for rrule in &event.rrules {
        occurrences.extend(expand_rrule(&event.start, rrule, window_start, window_end)?);
    }
    occurrences.extend(event.rdates.clone());
    let excluded = event
        .exdates
        .iter()
        .map(IcsTime::key)
        .collect::<BTreeSet<_>>();
    occurrences.retain(|value| !excluded.contains(&value.key()));
    Ok(occurrences)
}

fn expand_rrule(
    start: &IcsTime,
    rule: &str,
    window_start: NaiveDate,
    window_end: NaiveDate,
) -> Result<Vec<IcsTime>, String> {
    let parts = rule
        .split(';')
        .filter_map(|part| part.split_once('='))
        .map(|(key, value)| (key.to_ascii_uppercase(), value.to_string()))
        .collect::<BTreeMap<_, _>>();
    let frequency = parts
        .get("FREQ")
        .map(String::as_str)
        .ok_or("RRULE is missing FREQ")?;
    let interval = parts
        .get("INTERVAL")
        .and_then(|value| value.parse::<i64>().ok())
        .unwrap_or(1)
        .max(1);
    let count = parts
        .get("COUNT")
        .and_then(|value| value.parse::<usize>().ok());
    let until = parts
        .get("UNTIL")
        .and_then(|value| parse_rrule_until(value, start));
    let mut output = Vec::new();
    let mut current = start.clone();
    // This guard keeps malformed unbounded rules from consuming a worker.
    for index in 1..=20_000usize {
        current = advance_time(&current, frequency, interval)?;
        let current_date = match &current {
            IcsTime::Date(date) => *date,
            IcsTime::DateTime { local, .. } => local.date(),
        };
        if until
            .as_ref()
            .is_some_and(|limit| current.key() > limit.key())
            || current_date > window_end
        {
            break;
        }
        if current_date >= window_start {
            output.push(current.clone());
        }
        if count.is_some_and(|max| index + 1 >= max) {
            break;
        }
    }
    Ok(output)
}

fn parse_rrule_until(value: &str, start: &IcsTime) -> Option<IcsTime> {
    let property = Property {
        name: "UNTIL".into(),
        params: BTreeMap::new(),
        value: value.into(),
    };
    parse_ics_time(&property, &BTreeMap::new())
        .ok()
        .map(|until| match (until, start) {
            (IcsTime::DateTime { local, .. }, IcsTime::DateTime { zone, .. }) => {
                IcsTime::DateTime {
                    local,
                    zone: zone.clone(),
                }
            }
            (value, _) => value,
        })
}

fn advance_time(value: &IcsTime, frequency: &str, interval: i64) -> Result<IcsTime, String> {
    let add_months = |date: NaiveDate, months: i32| {
        let mut month = date.month() as i32 + months;
        let mut year = date.year();
        while month > 12 {
            month -= 12;
            year += 1;
        }
        let day = date.day().min(days_in_month(year, month as u32));
        NaiveDate::from_ymd_opt(year, month as u32, day).ok_or("invalid recurrence date")
    };
    match value {
        IcsTime::Date(date) => Ok(IcsTime::Date(match frequency {
            "DAILY" => *date + ChronoDuration::days(interval),
            "WEEKLY" => *date + ChronoDuration::weeks(interval),
            "MONTHLY" => add_months(*date, interval as i32)?,
            "YEARLY" => add_months(*date, (interval * 12) as i32)?,
            other => return Err(format!("unsupported RRULE FREQ {other}")),
        })),
        IcsTime::DateTime { local, zone } => {
            let date = local.date();
            let next_date = match frequency {
                "DAILY" => date + ChronoDuration::days(interval),
                "WEEKLY" => date + ChronoDuration::weeks(interval),
                "MONTHLY" => add_months(date, interval as i32)?,
                "YEARLY" => add_months(date, (interval * 12) as i32)?,
                other => return Err(format!("unsupported RRULE FREQ {other}")),
            };
            Ok(IcsTime::DateTime {
                local: next_date.and_time(local.time()),
                zone: zone.clone(),
            })
        }
    }
}

fn days_in_month(year: i32, month: u32) -> u32 {
    let next = if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)
    };
    (next.unwrap() - ChronoDuration::days(1)).day()
}

fn unfold_lines(source: &str) -> Vec<String> {
    let mut output: Vec<String> = Vec::new();
    for raw in source.lines() {
        let line = raw.trim_end_matches('\r');
        if (line.starts_with(' ') || line.starts_with('\t')) && !output.is_empty() {
            output.last_mut().unwrap().push_str(line.trim_start());
        } else {
            output.push(line.to_string());
        }
    }
    output
}

fn extract_components(lines: &[String], kind: &str) -> Vec<Vec<String>> {
    let begin = format!("BEGIN:{kind}");
    let end = format!("END:{kind}");
    let mut components = Vec::new();
    let mut current = None;
    for line in lines {
        if line.eq_ignore_ascii_case(&begin) {
            current = Some(Vec::new());
        } else if line.eq_ignore_ascii_case(&end) {
            if let Some(component) = current.take() {
                components.push(component);
            }
        } else if let Some(component) = current.as_mut() {
            component.push(line.clone());
        }
    }
    components
}

fn parse_embedded_zones(lines: &[String]) -> BTreeMap<String, chrono::FixedOffset> {
    let mut zones = BTreeMap::new();
    for component in extract_components(lines, "VTIMEZONE") {
        let properties = component
            .iter()
            .filter_map(|line| parse_property(line))
            .collect::<Vec<_>>();
        let id = property(&properties, "TZID").map(|value| unescape(&value.value));
        let offset = properties
            .iter()
            .find(|value| value.name == "TZOFFSETTO")
            .and_then(|value| parse_offset(&value.value));
        if let (Some(id), Some(offset)) = (id, offset) {
            zones.insert(id, offset);
        }
    }
    zones
}

fn parse_raw_event(
    component: &[String],
    index: usize,
    zones: &BTreeMap<String, chrono::FixedOffset>,
) -> Result<RawEvent, String> {
    let properties = component
        .iter()
        .filter_map(|line| parse_property(line))
        .collect::<Vec<_>>();
    let start = parse_ics_time(
        property(&properties, "DTSTART").ok_or("VEVENT is missing DTSTART")?,
        zones,
    )?;
    let end = property(&properties, "DTEND")
        .map(|value| parse_ics_time(value, zones))
        .transpose()?;
    let recurrence_id = property(&properties, "RECURRENCE-ID")
        .map(|value| parse_ics_time(value, zones))
        .transpose()?;
    let rdates = properties
        .iter()
        .filter(|value| value.name == "RDATE")
        .flat_map(|value| {
            value.value.split(',').map(move |part| {
                let mut property = value.clone();
                property.value = part.to_string();
                parse_ics_time(&property, zones)
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let exdates = properties
        .iter()
        .filter(|value| value.name == "EXDATE")
        .flat_map(|value| {
            value.value.split(',').map(move |part| {
                let mut property = value.clone();
                property.value = part.to_string();
                parse_ics_time(&property, zones)
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let alarms = extract_components(component, "VALARM")
        .into_iter()
        .map(|alarm| {
            let properties = alarm
                .iter()
                .filter_map(|line| parse_property(line))
                .collect::<Vec<_>>();
            let trigger = property(&properties, "TRIGGER").ok_or("VALARM is missing TRIGGER")?;
            Ok(RawAlarm {
                trigger: trigger.value.clone(),
                trigger_params: trigger.params.clone(),
                description: property(&properties, "DESCRIPTION")
                    .map(|value| unescape(&value.value))
                    .unwrap_or_default(),
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(RawEvent {
        uid: property(&properties, "UID")
            .map(|value| unescape(&value.value))
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| format!("event-{index}")),
        summary: property(&properties, "SUMMARY")
            .map(|value| unescape(&value.value))
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "(No title)".into()),
        start,
        end,
        recurrence_id,
        rrules: properties
            .iter()
            .filter(|value| value.name == "RRULE")
            .map(|value| value.value.clone())
            .collect(),
        rdates,
        exdates,
        alarms,
    })
}

fn parse_alarms(alarms: &[RawAlarm], starts_at: Option<DateTime<Utc>>) -> Vec<Alarm> {
    alarms
        .iter()
        .filter_map(|alarm| {
            if alarm
                .trigger_params
                .get("VALUE")
                .is_some_and(|value| value.eq_ignore_ascii_case("DATE-TIME"))
                || alarm.trigger.ends_with('Z')
            {
                let property = Property {
                    name: "TRIGGER".into(),
                    params: alarm.trigger_params.clone(),
                    value: alarm.trigger.clone(),
                };
                return parse_ics_time(&property, &BTreeMap::new())
                    .ok()?
                    .instant()
                    .map(|at| Alarm::Absolute {
                        at,
                        description: alarm.description.clone(),
                    });
            }
            let seconds = parse_duration(&alarm.trigger)?;
            starts_at.map(|_| Alarm::Relative {
                seconds_before_start: seconds.unsigned_abs() as i64,
                description: alarm.description.clone(),
            })
        })
        .collect()
}

fn parse_duration(value: &str) -> Option<i64> {
    let mut text = value.trim();
    let negative = text.starts_with('-');
    text = text.trim_start_matches(['+', '-']);
    let text = text.strip_prefix('P')?;
    let mut seconds = 0_i64;
    let mut digits = String::new();
    for character in text.chars() {
        if character.is_ascii_digit() {
            digits.push(character);
            continue;
        }
        let value = digits.parse::<i64>().ok()?;
        digits.clear();
        seconds += match character {
            'D' => value * 86_400,
            'H' => value * 3_600,
            'M' => value * 60,
            'S' => value,
            'T' => continue,
            _ => return None,
        };
    }
    Some(if negative { -seconds } else { seconds })
}

fn parse_property(line: &str) -> Option<Property> {
    let (left, value) = line.split_once(':')?;
    let mut parts = left.split(';');
    let name = parts.next()?.to_ascii_uppercase();
    let params = parts
        .filter_map(|part| {
            part.split_once('=').map(|(key, value)| {
                (
                    key.to_ascii_uppercase(),
                    value.trim_matches('"').to_string(),
                )
            })
        })
        .collect();
    Some(Property {
        name,
        params,
        value: value.to_string(),
    })
}

fn property<'a>(properties: &'a [Property], name: &str) -> Option<&'a Property> {
    properties.iter().find(|property| property.name == name)
}

fn parse_ics_time(
    property: &Property,
    zones: &BTreeMap<String, chrono::FixedOffset>,
) -> Result<IcsTime, String> {
    let value = property.value.trim();
    let is_date = property
        .params
        .get("VALUE")
        .is_some_and(|value| value.eq_ignore_ascii_case("DATE"))
        || (!value.contains('T') && value.len() == 8);
    if is_date {
        return NaiveDate::parse_from_str(value, "%Y%m%d")
            .map(IcsTime::Date)
            .map_err(|_| "invalid DATE value".into());
    }
    let utc = value.ends_with('Z');
    let bare = value.trim_end_matches(['Z', 'z']);
    let local = NaiveDateTime::parse_from_str(bare, "%Y%m%dT%H%M%S")
        .or_else(|_| NaiveDateTime::parse_from_str(bare, "%Y%m%dT%H%M"))
        .map_err(|_| "invalid DATE-TIME value")?;
    let zone = if utc {
        Zone::Utc
    } else if let Some(id) = property.params.get("TZID") {
        id.parse::<Tz>()
            .map(Zone::Named)
            .or_else(|_| zones.get(id).copied().map(Zone::Fixed).ok_or(()))
            .unwrap_or(Zone::Local)
    } else {
        Zone::Local
    };
    Ok(IcsTime::DateTime { local, zone })
}

fn parse_offset(value: &str) -> Option<chrono::FixedOffset> {
    let sign = if value.starts_with('-') { -1 } else { 1 };
    let digits = value.trim_start_matches(['+', '-']);
    let hours = digits.get(0..2)?.parse::<i32>().ok()?;
    let minutes = digits.get(2..4).unwrap_or("0").parse::<i32>().ok()?;
    chrono::FixedOffset::east_opt(sign * (hours * 3_600 + minutes * 60))
}

fn find_calendar_name(lines: &[String]) -> Option<String> {
    lines
        .iter()
        .filter_map(|line| parse_property(line))
        .find(|property| property.name == "X-WR-CALNAME" || property.name == "NAME")
        .map(|property| unescape(&property.value))
        .filter(|value| !value.trim().is_empty())
}

fn unescape(value: &str) -> String {
    value
        .replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
}

// The delivered-key queue is intentionally bounded. The identity includes the
// source, UID, recurrence start, and trigger kind, so refreshes can safely
// reschedule future work without producing duplicate notifications.
static DELIVERED_REMINDERS: OnceLock<Mutex<VecDeque<String>>> = OnceLock::new();
const MAX_DELIVERED_REMINDERS: usize = 4_096;

fn schedule_occurrence_notifications(occurrences: Vec<CalendarOccurrence>) {
    for occurrence in occurrences {
        let Some(start) = occurrence.starts_at else {
            continue;
        };
        for (kind, due, body) in reminder_candidates(&occurrence, start) {
            if due <= Utc::now()
                || !remember_reminder(format!("{}:{kind}", occurrence.occurrence_id))
            {
                continue;
            }
            let summary = occurrence.event.title.clone();
            tokio::spawn(async move {
                let wait = (due - Utc::now()).to_std().unwrap_or_default();
                tokio::time::sleep(wait).await;
                crate::notifications::push_internal_notification(summary, body);
            });
        }
    }
}

fn reminder_candidates(
    occurrence: &CalendarOccurrence,
    start: DateTime<Utc>,
) -> Vec<(String, DateTime<Utc>, String)> {
    let mut candidates = occurrence
        .alarms
        .iter()
        .enumerate()
        .map(|(index, alarm)| match alarm {
            Alarm::Relative {
                seconds_before_start,
                description,
            } => (
                format!("alarm-{index}"),
                start - ChronoDuration::seconds(*seconds_before_start),
                if description.is_empty() {
                    format!("{} is starting soon", occurrence.event.title)
                } else {
                    description.clone()
                },
            ),
            Alarm::Absolute { at, description } => (
                format!("alarm-{index}"),
                *at,
                if description.is_empty() {
                    format!("{} is starting soon", occurrence.event.title)
                } else {
                    description.clone()
                },
            ),
        })
        .collect::<Vec<_>>();
    if occurrence.notify_for_events {
        candidates.extend([30_i64, 10, 2].into_iter().map(|minutes| {
            (
                format!("default-{minutes}"),
                start - ChronoDuration::minutes(minutes),
                format!("{} starts in {minutes} minutes", occurrence.event.title),
            )
        }));
    }
    candidates
}

fn remember_reminder(identity: String) -> bool {
    let queue = DELIVERED_REMINDERS.get_or_init(|| Mutex::new(VecDeque::new()));
    let Ok(mut queue) = queue.lock() else {
        return false;
    };
    if queue.contains(&identity) {
        return false;
    }
    queue.push_back(identity);
    if queue.len() > MAX_DELIVERED_REMINDERS {
        queue.pop_front();
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{CalendarEntry, CalendarEntryKind};

    fn entry() -> CalendarEntry {
        CalendarEntry {
            id: "ics".into(),
            color: None,
            poll_interval_secs: 600,
            kind: CalendarEntryKind::Ics {
                path: Some("/tmp/feed.ics".into()),
                url: None,
                notify_for_events: true,
            },
        }
    }

    #[test]
    fn parses_recurring_events_exdates_exceptions_and_default_color() {
        let source = "BEGIN:VCALENDAR\nX-WR-CALNAME: Team\nBEGIN:VEVENT\nUID:weekly\nSUMMARY:Standup\nDTSTART:20260101T090000Z\nDTEND:20260101T093000Z\nRRULE:FREQ=DAILY;COUNT=3\nEXDATE:20260102T090000Z\nEND:VEVENT\nBEGIN:VEVENT\nUID:weekly\nRECURRENCE-ID:20260103T090000Z\nSUMMARY:Moved standup\nDTSTART:20260103T100000Z\nDTEND:20260103T103000Z\nEND:VEVENT\nEND:VCALENDAR\n";
        let events = parse_ics_occurrences(
            &entry(),
            source,
            NaiveDate::from_ymd_opt(2026, 1, 1).unwrap(),
            NaiveDate::from_ymd_opt(2026, 1, 4).unwrap(),
        )
        .unwrap();
        assert_eq!(events.len(), 2);
        assert!(
            events
                .iter()
                .any(|event| event.event.title == "Moved standup")
        );
        assert!(
            events
                .iter()
                .all(|event| event.event.calendar_color == ICS_DEFAULT_COLOR)
        );
    }

    #[test]
    fn handles_all_day_events_and_named_timezone_dst_boundaries() {
        let source = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:all-day\nSUMMARY:Holiday\nDTSTART;VALUE=DATE:20260308\nDTEND;VALUE=DATE:20260309\nEND:VEVENT\nBEGIN:VEVENT\nUID:dst\nSUMMARY:DST meeting\nDTSTART;TZID=America/New_York:20260308T090000\nDTEND;TZID=America/New_York:20260308T100000\nEND:VEVENT\nEND:VCALENDAR\n";
        let events = parse_ics_occurrences(
            &entry(),
            source,
            NaiveDate::from_ymd_opt(2026, 3, 7).unwrap(),
            NaiveDate::from_ymd_opt(2026, 3, 9).unwrap(),
        )
        .unwrap();
        assert_eq!(events.len(), 2);
        assert!(events.iter().any(|event| event.event.is_all_day));
        assert!(
            events
                .iter()
                .any(|event| event.uid == "dst" && event.starts_at.is_some())
        );
    }

    #[tokio::test]
    async fn refreshes_a_local_ics_file() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("calendar.ics");
        let date = Local::now().date_naive();
        std::fs::write(
            &path,
            format!("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:file\nSUMMARY:From file\nDTSTART;VALUE=DATE:{}\nEND:VEVENT\nEND:VCALENDAR\n", date.format("%Y%m%d")),
        )
        .unwrap();
        let mut source = entry();
        source.kind = CalendarEntryKind::Ics {
            path: Some(path),
            url: None,
            notify_for_events: true,
        };
        let coordinator = CalendarCoordinator::new();
        refresh_ics_source(&coordinator, &source).await.unwrap();
        assert_eq!(coordinator.events_for_date(date)[0].title, "From file");
    }

    #[tokio::test]
    async fn refreshes_an_http_ics_feed_and_isolates_malformed_data() {
        use wiremock::{
            Mock, MockServer, ResponseTemplate,
            matchers::{method, path},
        };

        let server = MockServer::start().await;
        let date = Local::now().date_naive();
        Mock::given(method("GET"))
            .and(path("/feed.ics"))
            .respond_with(ResponseTemplate::new(200).set_body_string(format!(
                "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:http\nSUMMARY:From HTTP\nDTSTART;VALUE=DATE:{}\nEND:VEVENT\nEND:VCALENDAR\n",
                date.format("%Y%m%d")
            )))
            .mount(&server)
            .await;
        let mut source = entry();
        source.kind = CalendarEntryKind::Ics {
            path: None,
            url: Some(format!("{}/feed.ics", server.uri())),
            notify_for_events: true,
        };
        let coordinator = CalendarCoordinator::new();
        refresh_ics_source(&coordinator, &source).await.unwrap();
        assert_eq!(coordinator.events_for_date(date)[0].title, "From HTTP");

        source.kind = CalendarEntryKind::Ics {
            path: None,
            url: Some(format!("{}/missing.ics", server.uri())),
            notify_for_events: true,
        };
        assert!(refresh_ics_source(&coordinator, &source).await.is_err());
        // The failed update leaves the source's successfully parsed data intact.
        assert_eq!(coordinator.events_for_date(date)[0].title, "From HTTP");
    }

    #[test]
    fn schedules_defaults_only_for_enabled_timed_events_and_deduplicates() {
        let start = Utc::now() + ChronoDuration::hours(1);
        let occurrence = CalendarOccurrence {
            source_id: "ics".into(),
            uid: "uid".into(),
            occurrence_id: "ics:uid:future".into(),
            date: start.date_naive(),
            starts_at: Some(start),
            ends_at: None,
            event: CalendarEvent {
                title: "Future event".into(),
                ..Default::default()
            },
            alarms: vec![Alarm::Relative {
                seconds_before_start: 300,
                description: "Alarm".into(),
            }],
            notify_for_events: true,
        };
        assert_eq!(reminder_candidates(&occurrence, start).len(), 4);
        let mut disabled = occurrence.clone();
        disabled.notify_for_events = false;
        assert_eq!(reminder_candidates(&disabled, start).len(), 1);
        assert!(remember_reminder("test-dedupe".into()));
        assert!(!remember_reminder("test-dedupe".into()));
    }

    #[test]
    fn merged_date_results_are_source_scoped_and_sorted() {
        let coordinator = CalendarCoordinator::new();
        let date = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
        coordinator.replace_events(
            "google-work",
            vec![(
                date,
                CalendarEvent {
                    id: "google-event".into(),
                    title: "Google".into(),
                    start_label: "09:00".into(),
                    ..Default::default()
                },
            )],
        );
        coordinator.replace_events(
            "ics-home",
            vec![(
                date,
                CalendarEvent {
                    id: "ics-event".into(),
                    title: "ICS".into(),
                    start_label: "08:00".into(),
                    ..Default::default()
                },
            )],
        );

        assert_eq!(
            coordinator
                .events_for_date(date)
                .into_iter()
                .map(|event| event.title)
                .collect::<Vec<_>>(),
            vec!["ICS", "Google"]
        );
    }

    #[test]
    fn refresh_failure_retains_prior_source_snapshot() {
        let coordinator = CalendarCoordinator::new();
        coordinator.replace_source(
            "ics",
            vec![CalendarOccurrence {
                source_id: "ics".into(),
                uid: "uid".into(),
                occurrence_id: "ics:uid:1".into(),
                date: NaiveDate::from_ymd_opt(2026, 1, 1).unwrap(),
                starts_at: None,
                ends_at: None,
                event: CalendarEvent {
                    title: "kept".into(),
                    ..Default::default()
                },
                alarms: vec![],
                notify_for_events: true,
            }],
        );
        coordinator.record_failure("ics", "network unavailable");
        assert_eq!(
            coordinator.events_for_date(NaiveDate::from_ymd_opt(2026, 1, 1).unwrap())[0].title,
            "kept"
        );
        assert_eq!(
            coordinator.source_error("ics").as_deref(),
            Some("network unavailable")
        );
    }
}
