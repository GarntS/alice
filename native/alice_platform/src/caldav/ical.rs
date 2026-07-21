use std::{
    collections::{BTreeMap, BTreeSet},
    error::Error,
    fmt,
};

use chrono::{Local, LocalResult, NaiveDate, NaiveDateTime, TimeZone, Utc};
use chrono_tz::Tz;
use icalendar::{Calendar, Component, Property, TodoStatus};
use url::Url;

use super::{
    CalDavEvent, CalDavResourceKind, CalendarValue, LosslessCalDavResource, NormalizedTask,
    RecurrenceMetadata, TaskPriority, TaskResourceIdentity, TaskStatus, TimezoneDefinition,
};

/// Parse all supported components from one complete CalDAV resource.
pub fn parse_caldav_resource(
    source: &str,
    collection_href: &Url,
    resource_href: &Url,
    collection_name: &str,
    etag: Option<String>,
) -> Result<Option<LosslessCalDavResource>, ICalendarParseError> {
    let todo = parse_vtodo_resource(
        source,
        collection_href,
        resource_href,
        collection_name,
        etag.clone(),
    )?;
    let event = parse_vevent_resource(
        source,
        collection_href,
        resource_href,
        collection_name,
        etag,
    )?;
    match (todo, event) {
        (None, None) => Ok(None),
        (Some(resource), None) | (None, Some(resource)) => Ok(Some(resource)),
        (Some(mut todo), Some(event)) => {
            todo.kind = CalDavResourceKind::Mixed;
            todo.events = event.events;
            Ok(Some(todo))
        }
    }
}

/// Parse a CalDAV resource without performing I/O or mutating the source text.
///
/// Cancelled VTODOs remain available as lossless resources for cache
/// reconciliation but produce no normalized task and are therefore hidden.
pub fn parse_vtodo_resource(
    source: &str,
    collection_href: &Url,
    resource_href: &Url,
    collection_name: &str,
    etag: Option<String>,
) -> Result<Option<LosslessCalDavResource>, ICalendarParseError> {
    parse_vtodo_resource_in_zone(
        source,
        collection_href,
        resource_href,
        collection_name,
        etag,
        LocalZone::System,
    )
}

fn parse_vtodo_resource_in_zone(
    source: &str,
    collection_href: &Url,
    resource_href: &Url,
    collection_name: &str,
    etag: Option<String>,
    local_zone: LocalZone,
) -> Result<Option<LosslessCalDavResource>, ICalendarParseError> {
    let calendar = source
        .parse::<Calendar>()
        .map_err(|_| ICalendarParseError::new("invalid iCalendar resource"))?;
    let Some(todo) = calendar
        .components
        .iter()
        .find_map(|component| component.as_todo())
    else {
        return Ok(None);
    };

    let identity = TaskResourceIdentity {
        collection_href: collection_href.to_string(),
        resource_href: resource_href.to_string(),
    };
    let status = match todo.get_status() {
        Some(TodoStatus::Completed) => TaskStatus::Completed,
        Some(TodoStatus::Cancelled) => TaskStatus::Cancelled,
        Some(TodoStatus::NeedsAction | TodoStatus::InProcess) | None => TaskStatus::Active,
    };
    let task = if status == TaskStatus::Cancelled {
        None
    } else {
        Some(NormalizedTask {
            identity: identity.clone(),
            uid: todo
                .get_uid()
                .map(str::trim)
                .filter(|uid| !uid.is_empty())
                .unwrap_or(resource_href.as_str())
                .to_string(),
            title: todo
                .get_summary()
                .map(unescape_text)
                .map(|title| title.trim().to_string())
                .filter(|title| !title.is_empty())
                .unwrap_or_else(|| "(No title)".into()),
            collection_name: collection_name.trim().to_string(),
            due_date: normalize_due_date(todo.properties().get("DUE"), local_zone)?,
            completed_at_unix_secs: normalize_completed_instant(
                todo.properties().get("COMPLETED"),
                local_zone,
            )?,
            status,
            priority: TaskPriority::from_ical(todo.get_priority().map(|value| value as i32)),
        })
    };

    Ok(Some(LosslessCalDavResource {
        identity,
        etag,
        icalendar: source.to_string(),
        kind: CalDavResourceKind::Todo,
        task,
        events: vec![],
    }))
}

/// Parse every VEVENT in a resource as a base record or detached exception.
/// Recurrence definitions are retained but never expanded into occurrences.
pub fn parse_vevent_resource(
    source: &str,
    collection_href: &Url,
    resource_href: &Url,
    collection_name: &str,
    etag: Option<String>,
) -> Result<Option<LosslessCalDavResource>, ICalendarParseError> {
    let calendar = source
        .parse::<Calendar>()
        .map_err(|_| ICalendarParseError::new("invalid iCalendar resource"))?;
    let timezone_sources = extract_timezone_definitions(source);
    let has_todo = calendar
        .components
        .iter()
        .any(|component| component.as_todo().is_some());
    let event_components = calendar
        .components
        .iter()
        .filter_map(|component| component.as_event())
        .collect::<Vec<_>>();
    if event_components.is_empty() {
        return Ok(None);
    }

    let mut events = Vec::with_capacity(event_components.len());
    for (index, event) in event_components.into_iter().enumerate() {
        let start = event
            .properties()
            .get("DTSTART")
            .ok_or_else(|| ICalendarParseError::new("VEVENT is missing DTSTART"))
            .and_then(parse_typed_calendar_value)?;
        let end = event
            .properties()
            .get("DTEND")
            .map(parse_typed_calendar_value)
            .transpose()?;
        let rrules = component_properties(event, "RRULE")
            .into_iter()
            .map(|property| property.value().to_string())
            .collect();
        let rdates = component_properties(event, "RDATE")
            .into_iter()
            .map(parse_typed_calendar_values)
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .flatten()
            .collect();
        let exdates = component_properties(event, "EXDATE")
            .into_iter()
            .map(parse_typed_calendar_values)
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .flatten()
            .collect();
        let recurrence_id = event
            .properties()
            .get("RECURRENCE-ID")
            .map(parse_typed_calendar_value)
            .transpose()?;
        let recurrence = RecurrenceMetadata {
            rrules,
            rdates,
            exdates,
            recurrence_id,
        };

        let mut referenced_ids = BTreeSet::new();
        collect_timezone_id(&start, &mut referenced_ids);
        if let Some(end) = &end {
            collect_timezone_id(end, &mut referenced_ids);
        }
        for value in recurrence
            .rdates
            .iter()
            .chain(&recurrence.exdates)
            .chain(recurrence.recurrence_id.iter())
        {
            collect_timezone_id(value, &mut referenced_ids);
        }
        let referenced_timezones = referenced_ids
            .into_iter()
            .filter_map(|tzid| timezone_sources.get(&tzid).cloned())
            .collect();

        events.push(CalDavEvent {
            collection_href: collection_href.to_string(),
            resource_href: resource_href.to_string(),
            uid: event
                .get_uid()
                .map(str::trim)
                .filter(|uid| !uid.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| format!("{}#{index}", resource_href.as_str())),
            summary: event
                .get_summary()
                .map(unescape_text)
                .map(|summary| summary.trim().to_string())
                .filter(|summary| !summary.is_empty())
                .unwrap_or_else(|| "(No title)".into()),
            start,
            end,
            recurrence,
            referenced_timezones,
        });
    }

    let _ = collection_name; // Event UI is intentionally out of scope.
    Ok(Some(LosslessCalDavResource {
        identity: TaskResourceIdentity {
            collection_href: collection_href.to_string(),
            resource_href: resource_href.to_string(),
        },
        etag,
        icalendar: source.to_string(),
        kind: if has_todo {
            CalDavResourceKind::Mixed
        } else {
            CalDavResourceKind::Event
        },
        task: None,
        events,
    }))
}

fn component_properties<'a, C: Component>(component: &'a C, key: &str) -> Vec<&'a Property> {
    component
        .properties()
        .get(key)
        .into_iter()
        .chain(component.multi_properties().get(key).into_iter().flatten())
        .collect()
}

fn parse_typed_calendar_values(
    property: &Property,
) -> Result<Vec<CalendarValue>, ICalendarParseError> {
    property
        .value()
        .split(',')
        .map(|value| parse_typed_calendar_value_with_value(property, value))
        .collect()
}

fn parse_typed_calendar_value(property: &Property) -> Result<CalendarValue, ICalendarParseError> {
    parse_typed_calendar_value_with_value(property, property.value())
}

fn parse_typed_calendar_value_with_value(
    property: &Property,
    value: &str,
) -> Result<CalendarValue, ICalendarParseError> {
    let value = value.trim();
    let is_date = property
        .params()
        .get("VALUE")
        .is_some_and(|parameter| parameter.value().eq_ignore_ascii_case("DATE"))
        || (!value.contains('T') && value.len() == 8);
    if is_date {
        let date = NaiveDate::parse_from_str(value, "%Y%m%d")
            .map_err(|_| ICalendarParseError::new("invalid iCalendar date"))?;
        return Ok(CalendarValue::Date {
            date: date.format("%Y-%m-%d").to_string(),
        });
    }

    let basic = value
        .strip_suffix('Z')
        .or_else(|| value.strip_suffix('z'))
        .unwrap_or(value);
    NaiveDateTime::parse_from_str(basic, "%Y%m%dT%H%M%S")
        .map_err(|_| ICalendarParseError::new("invalid iCalendar date-time"))?;
    let timezone_id = property
        .params()
        .get("TZID")
        .map(|parameter| parameter.value().to_string());
    let is_utc = value.ends_with('Z') || value.ends_with('z');
    Ok(CalendarValue::DateTime {
        value: value.to_string(),
        is_utc,
        is_floating: !is_utc && timezone_id.is_none(),
        timezone_id,
    })
}

fn collect_timezone_id(value: &CalendarValue, output: &mut BTreeSet<String>) {
    if let CalendarValue::DateTime {
        timezone_id: Some(timezone_id),
        ..
    } = value
    {
        output.insert(timezone_id.clone());
    }
}

fn extract_timezone_definitions(source: &str) -> BTreeMap<String, TimezoneDefinition> {
    extract_raw_components(source, "VTIMEZONE")
        .into_iter()
        .filter_map(|raw_component| {
            let unfolded = icalendar::parser::unfold(&raw_component);
            let tzid = unfolded.lines().find_map(|line| {
                let (name, value) = line.split_once(':')?;
                name.eq_ignore_ascii_case("TZID")
                    .then(|| unescape_text(value.trim()))
            })?;
            Some((
                tzid.clone(),
                TimezoneDefinition {
                    tzid,
                    raw_component,
                },
            ))
        })
        .collect()
}

fn extract_raw_components(source: &str, component_name: &str) -> Vec<String> {
    let begin = format!("BEGIN:{component_name}");
    let mut output = Vec::new();
    let mut current = String::new();
    let mut depth = 0_u32;

    for line in source.split_inclusive('\n') {
        let content = line.trim_end_matches(['\r', '\n']);
        if depth == 0 {
            if content.eq_ignore_ascii_case(&begin) {
                depth = 1;
                current.push_str(line);
            }
            continue;
        }

        current.push_str(line);
        if content.to_ascii_uppercase().starts_with("BEGIN:") {
            depth += 1;
        } else if content.to_ascii_uppercase().starts_with("END:") {
            depth -= 1;
            if depth == 0 {
                output.push(std::mem::take(&mut current));
            }
        }
    }
    output
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
enum LocalZone {
    System,
    Named(Tz),
}

fn normalize_due_date(
    property: Option<&Property>,
    local_zone: LocalZone,
) -> Result<Option<String>, ICalendarParseError> {
    let Some(property) = property else {
        return Ok(None);
    };
    let parsed = parse_calendar_value(property, local_zone)?;
    Ok(Some(match parsed {
        ParsedCalendarValue::Date(date) => date.format("%Y-%m-%d").to_string(),
        ParsedCalendarValue::Instant(instant) => local_date(instant, local_zone)
            .format("%Y-%m-%d")
            .to_string(),
    }))
}

fn normalize_completed_instant(
    property: Option<&Property>,
    local_zone: LocalZone,
) -> Result<Option<i64>, ICalendarParseError> {
    let Some(property) = property else {
        return Ok(None);
    };
    let parsed = parse_calendar_value(property, local_zone)?;
    let instant = match parsed {
        ParsedCalendarValue::Date(date) => local_naive_to_utc(
            date.and_hms_opt(0, 0, 0)
                .ok_or_else(|| ICalendarParseError::new("invalid iCalendar date"))?,
            local_zone,
        )?,
        ParsedCalendarValue::Instant(instant) => instant,
    };
    Ok(Some(instant.timestamp()))
}

enum ParsedCalendarValue {
    Date(NaiveDate),
    Instant(chrono::DateTime<Utc>),
}

fn parse_calendar_value(
    property: &Property,
    local_zone: LocalZone,
) -> Result<ParsedCalendarValue, ICalendarParseError> {
    let value = property.value().trim();
    let is_date = property
        .params()
        .get("VALUE")
        .is_some_and(|parameter| parameter.value().eq_ignore_ascii_case("DATE"))
        || (!value.contains('T') && value.len() == 8);
    if is_date {
        return NaiveDate::parse_from_str(value, "%Y%m%d")
            .map(ParsedCalendarValue::Date)
            .map_err(|_| ICalendarParseError::new("invalid iCalendar date"));
    }

    let is_utc = value.ends_with('Z') || value.ends_with('z');
    let basic = if is_utc {
        &value[..value.len() - 1]
    } else {
        value
    };
    let naive = NaiveDateTime::parse_from_str(basic, "%Y%m%dT%H%M%S")
        .map_err(|_| ICalendarParseError::new("invalid iCalendar date-time"))?;
    if is_utc {
        return Ok(ParsedCalendarValue::Instant(Utc.from_utc_datetime(&naive)));
    }

    if let Some(timezone_id) = property.params().get("TZID") {
        let timezone = timezone_id
            .value()
            .parse::<Tz>()
            .map_err(|_| ICalendarParseError::new("unknown iCalendar timezone"))?;
        return Ok(ParsedCalendarValue::Instant(
            resolve_local_datetime(timezone.from_local_datetime(&naive))?.with_timezone(&Utc),
        ));
    }

    Ok(ParsedCalendarValue::Instant(local_naive_to_utc(
        naive, local_zone,
    )?))
}

fn local_naive_to_utc(
    value: NaiveDateTime,
    local_zone: LocalZone,
) -> Result<chrono::DateTime<Utc>, ICalendarParseError> {
    match local_zone {
        LocalZone::System => resolve_local_datetime(Local.from_local_datetime(&value))
            .map(|datetime| datetime.with_timezone(&Utc)),
        LocalZone::Named(timezone) => resolve_local_datetime(timezone.from_local_datetime(&value))
            .map(|datetime| datetime.with_timezone(&Utc)),
    }
}

fn resolve_local_datetime<TzValue: TimeZone>(
    result: LocalResult<chrono::DateTime<TzValue>>,
) -> Result<chrono::DateTime<TzValue>, ICalendarParseError> {
    match result {
        LocalResult::Single(value) | LocalResult::Ambiguous(value, _) => Ok(value),
        LocalResult::None => Err(ICalendarParseError::new(
            "iCalendar date-time falls in a timezone gap",
        )),
    }
}

fn local_date(instant: chrono::DateTime<Utc>, local_zone: LocalZone) -> NaiveDate {
    match local_zone {
        LocalZone::System => instant.with_timezone(&Local).date_naive(),
        LocalZone::Named(timezone) => instant.with_timezone(&timezone).date_naive(),
    }
}

/// Patch completion fields on the first top-level VTODO while preserving every
/// unrelated source byte, sibling component, and nested alarm.
pub fn patch_vtodo_completion(
    source: &str,
    completed: bool,
    completed_at: chrono::DateTime<Utc>,
) -> Result<String, ICalendarParseError> {
    // Validate structure first, but never include parser details or source text
    // in the returned error.
    source
        .parse::<Calendar>()
        .map_err(|_| ICalendarParseError::new("invalid iCalendar resource"))?;

    let line_ending = if source.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    let mut output = String::with_capacity(source.len() + 96);
    let mut stack: Vec<String> = Vec::new();
    let mut target_depth = None;
    let mut patched = false;
    let mut skipping_completion_property = false;

    for line in source.split_inclusive('\n') {
        let content = line.trim_end_matches(['\r', '\n']);
        let is_continuation = content.starts_with(' ') || content.starts_with('\t');

        if skipping_completion_property && is_continuation {
            continue;
        }
        if !is_continuation {
            skipping_completion_property = false;
        }

        if let Some(component) = component_marker(content, "BEGIN") {
            output.push_str(line);
            stack.push(component.to_ascii_uppercase());
            if target_depth.is_none() && !patched && component.eq_ignore_ascii_case("VTODO") {
                target_depth = Some(stack.len());
            }
            continue;
        }

        if let Some(component) = component_marker(content, "END") {
            if target_depth == Some(stack.len()) && component.eq_ignore_ascii_case("VTODO") {
                write_completion_properties(&mut output, completed, completed_at, line_ending);
                target_depth = None;
                patched = true;
            }
            output.push_str(line);
            stack.pop();
            continue;
        }

        let is_target_top_level = target_depth == Some(stack.len());
        if is_target_top_level
            && !is_continuation
            && property_name(content).is_some_and(is_completion_property)
        {
            skipping_completion_property = true;
            continue;
        }
        output.push_str(line);
    }

    if !patched {
        return Err(ICalendarParseError::new(
            "iCalendar resource does not contain a VTODO",
        ));
    }
    Ok(output)
}

fn component_marker<'a>(line: &'a str, marker: &str) -> Option<&'a str> {
    let (name, component) = line.split_once(':')?;
    name.eq_ignore_ascii_case(marker).then_some(component)
}

fn property_name(line: &str) -> Option<&str> {
    let declaration = line.split_once(':')?.0;
    Some(
        declaration
            .split_once(';')
            .map_or(declaration, |(name, _)| name),
    )
}

fn is_completion_property(name: &str) -> bool {
    name.eq_ignore_ascii_case("STATUS")
        || name.eq_ignore_ascii_case("COMPLETED")
        || name.eq_ignore_ascii_case("PERCENT-COMPLETE")
}

fn write_completion_properties(
    output: &mut String,
    completed: bool,
    completed_at: chrono::DateTime<Utc>,
    line_ending: &str,
) {
    if completed {
        output.push_str("STATUS:COMPLETED");
        output.push_str(line_ending);
        output.push_str("COMPLETED:");
        output.push_str(&completed_at.format("%Y%m%dT%H%M%SZ").to_string());
        output.push_str(line_ending);
        output.push_str("PERCENT-COMPLETE:100");
        output.push_str(line_ending);
    } else {
        output.push_str("STATUS:NEEDS-ACTION");
        output.push_str(line_ending);
        output.push_str("PERCENT-COMPLETE:0");
        output.push_str(line_ending);
    }
}

/// Decode RFC 5545 TEXT escapes after the parser has unfolded content lines.
pub fn unescape_text(value: &str) -> String {
    let mut output = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(character) = chars.next() {
        if character != '\\' {
            output.push(character);
            continue;
        }
        match chars.next() {
            Some('n' | 'N') => output.push('\n'),
            Some('\\') => output.push('\\'),
            Some(',') => output.push(','),
            Some(';') => output.push(';'),
            Some(other) => {
                // Unknown escapes are preserved rather than silently dropping
                // source information.
                output.push('\\');
                output.push(other);
            }
            None => output.push('\\'),
        }
    }
    output
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ICalendarParseError {
    message: &'static str,
}

impl ICalendarParseError {
    fn new(message: &'static str) -> Self {
        Self { message }
    }
}

impl fmt::Display for ICalendarParseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message)
    }
}

impl Error for ICalendarParseError {}

#[cfg(test)]
mod tests {
    use super::*;

    const VIKUNJA_TASK: &str = include_str!("../../tests/fixtures/caldav/vikunja-task.ics");
    const CANCELLED_TASK: &str = include_str!("../../tests/fixtures/caldav/cancelled-task.ics");
    const RECURRING_EVENT: &str = include_str!("../../tests/fixtures/caldav/recurring-event.ics");
    const ALL_DAY_EVENT: &str = include_str!("../../tests/fixtures/caldav/all-day-event.ics");
    const COMPLEX_TASK: &str = include_str!("../../tests/fixtures/caldav/complex-task.ics");
    const RFC5545_TASK: &str = include_str!("../../tests/fixtures/caldav/rfc5545-task.ics");

    fn collection() -> Url {
        Url::parse("https://tasks.example.test/dav/calendars/alice/work/").unwrap()
    }

    fn resource(name: &str) -> Url {
        collection().join(name).unwrap()
    }

    #[test]
    fn parses_timed_recurrence_and_detached_exception_without_expansion() {
        let parsed = parse_vevent_resource(
            RECURRING_EVENT,
            &collection(),
            &resource("meeting.ics"),
            "Work",
            Some("\"event-etag\"".into()),
        )
        .unwrap()
        .unwrap();

        assert_eq!(parsed.kind, CalDavResourceKind::Event);
        assert_eq!(parsed.events.len(), 2);
        assert_eq!(parsed.icalendar, RECURRING_EVENT);
        let base = &parsed.events[0];
        assert_eq!(base.uid, "meeting-1");
        assert_eq!(base.summary, "Weekly, planning");
        assert_eq!(
            base.start,
            CalendarValue::DateTime {
                value: "20260721T090000".into(),
                timezone_id: Some("America/New_York".into()),
                is_utc: false,
                is_floating: false,
            }
        );
        assert_eq!(base.recurrence.rrules, ["FREQ=WEEKLY;COUNT=4"]);
        assert_eq!(base.recurrence.rdates.len(), 2);
        assert_eq!(base.recurrence.exdates.len(), 1);
        assert_eq!(base.referenced_timezones.len(), 1);
        assert_eq!(base.referenced_timezones[0].tzid, "America/New_York");
        assert!(
            base.referenced_timezones[0]
                .raw_component
                .contains("X-LIC-LOCATION:America/New_York\r\n")
        );

        let exception = &parsed.events[1];
        assert_eq!(exception.uid, "meeting-1");
        assert!(exception.recurrence.recurrence_id.is_some());
        assert!(exception.recurrence.rrules.is_empty());
    }

    #[test]
    fn parses_all_day_event_and_date_recurrence_values() {
        let parsed = parse_vevent_resource(
            ALL_DAY_EVENT,
            &collection(),
            &resource("holiday.ics"),
            "Work",
            None,
        )
        .unwrap()
        .unwrap();
        assert_eq!(parsed.events.len(), 1);
        let event = &parsed.events[0];
        assert_eq!(
            event.start,
            CalendarValue::Date {
                date: "2026-07-20".into()
            }
        );
        assert_eq!(
            event.end,
            Some(CalendarValue::Date {
                date: "2026-07-21".into()
            })
        );
        assert_eq!(
            event.recurrence.rdates,
            [CalendarValue::Date {
                date: "2026-07-27".into()
            }]
        );
        assert_eq!(event.recurrence.exdates.len(), 1);
        assert!(event.referenced_timezones.is_empty());
    }

    #[test]
    fn completion_patch_changes_only_top_level_completion_properties() {
        let completed_at = Utc
            .with_ymd_and_hms(2026, 7, 20, 14, 15, 16)
            .single()
            .unwrap();
        let patched = patch_vtodo_completion(COMPLEX_TASK, true, completed_at).unwrap();

        assert!(patched.contains("STATUS:COMPLETED\r\n"));
        assert!(patched.contains("COMPLETED:20260720T141516Z\r\n"));
        assert!(patched.contains("PERCENT-COMPLETE:100\r\n"));
        assert!(!patched.contains("PERCENT-COMPLETE:50"));
        assert!(patched.contains("STATUS:X-ALARM-STATUS\r\n"));
        assert!(patched.contains("X-ALARM-UNKNOWN:preserve\r\n"));
        assert!(patched.contains("X-VIKUNJA-TASK-ID:123\r\n"));
        assert!(patched.contains("RRULE:FREQ=WEEKLY;COUNT=8\r\n"));
        assert!(patched.contains("RELATED-TO;RELTYPE=PARENT:parent-1\r\n"));
        assert!(patched.contains("X-TIMEZONE-UNKNOWN:keep\r\n"));
        assert!(patched.contains("X-SIBLING:preserve\r\n"));
        assert!(patched.contains(
            "DESCRIPTION:A long description with escaped\\, punctuation\\; and a folded \r\n continuation.\r\n"
        ));
        assert_eq!(
            extract_raw_components(&patched, "VEVENT"),
            extract_raw_components(COMPLEX_TASK, "VEVENT")
        );
        assert_eq!(
            extract_raw_components(&patched, "VTIMEZONE"),
            extract_raw_components(COMPLEX_TASK, "VTIMEZONE")
        );

        let task = parse_vtodo_resource(
            &patched,
            &collection(),
            &resource("complex.ics"),
            "Work",
            None,
        )
        .unwrap()
        .unwrap()
        .task
        .unwrap();
        assert_eq!(task.status, TaskStatus::Completed);
        assert_eq!(task.completed_at_unix_secs, Some(completed_at.timestamp()));
        assert_eq!(
            patch_vtodo_completion(&patched, true, completed_at).unwrap(),
            patched
        );
    }

    #[test]
    fn uncomplete_patch_removes_completed_and_sets_active_fields() {
        let patched = patch_vtodo_completion(COMPLEX_TASK, false, Utc::now()).unwrap();
        assert!(patched.contains("STATUS:NEEDS-ACTION\r\n"));
        assert!(patched.contains("PERCENT-COMPLETE:0\r\n"));
        assert!(!patched.contains("COMPLETED:"));
        assert!(patched.contains("BEGIN:VALARM\r\n"));
        assert!(patched.contains("BEGIN:VEVENT\r\n"));

        let task = parse_vtodo_resource(
            &patched,
            &collection(),
            &resource("complex.ics"),
            "Work",
            None,
        )
        .unwrap()
        .unwrap()
        .task
        .unwrap();
        assert_eq!(task.status, TaskStatus::Active);
        assert_eq!(task.completed_at_unix_secs, None);
    }

    #[test]
    fn vikunja_and_rfc_round_trips_preserve_all_non_completion_bytes() {
        let completed_at = Utc
            .with_ymd_and_hms(2026, 7, 20, 14, 15, 16)
            .single()
            .unwrap();
        for (name, source) in [("vikunja", VIKUNJA_TASK), ("rfc5545", RFC5545_TASK)] {
            let completed = patch_vtodo_completion(source, true, completed_at).unwrap();
            let round_trip = patch_vtodo_completion(&completed, false, completed_at).unwrap();

            assert_eq!(
                non_completion_content(&completed),
                non_completion_content(source),
                "complete must preserve {name} content"
            );
            assert_eq!(
                non_completion_content(&round_trip),
                non_completion_content(source),
                "un-complete must preserve {name} content"
            );
            assert!(
                parse_vtodo_resource(
                    &completed,
                    &collection(),
                    &resource(&format!("{name}.ics")),
                    "Work",
                    None,
                )
                .unwrap()
                .unwrap()
                .task
                .is_some()
            );
        }

        let completed = patch_vtodo_completion(RFC5545_TASK, true, completed_at).unwrap();
        assert_eq!(
            extract_raw_components(&completed, "VJOURNAL"),
            extract_raw_components(RFC5545_TASK, "VJOURNAL")
        );
        for marker in [
            "ATTENDEE;CN=Bob;PARTSTAT=NEEDS-ACTION:mailto:bob@example.test",
            "RELATED-TO;RELTYPE=CHILD:child@example.test",
            "RRULE:FREQ=DAILY;COUNT=3",
            "X-CUSTOM-PROPERTY;X-PARAM=custom:value",
            "X-ALARM-CUSTOM:keep",
        ] {
            assert!(
                completed.contains(marker),
                "missing preserved marker: {marker}"
            );
        }
    }

    fn non_completion_content(source: &str) -> String {
        let mut output = String::new();
        let mut stack: Vec<String> = Vec::new();
        let mut skipping = false;
        for line in source.split_inclusive('\n') {
            let content = line.trim_end_matches(['\r', '\n']);
            let continuation = content.starts_with(' ') || content.starts_with('\t');
            if skipping && continuation {
                continue;
            }
            if !continuation {
                skipping = false;
            }
            if let Some(component) = component_marker(content, "BEGIN") {
                output.push_str(line);
                stack.push(component.to_ascii_uppercase());
                continue;
            }
            if component_marker(content, "END").is_some() {
                output.push_str(line);
                stack.pop();
                continue;
            }
            if stack.last().is_some_and(|name| name == "VTODO")
                && !continuation
                && property_name(content).is_some_and(is_completion_property)
            {
                skipping = true;
                continue;
            }
            output.push_str(line);
        }
        output
    }

    #[test]
    fn completion_patch_rejects_resource_without_vtodo() {
        assert_eq!(
            patch_vtodo_completion(ALL_DAY_EVENT, true, Utc::now())
                .unwrap_err()
                .to_string(),
            "iCalendar resource does not contain a VTODO"
        );
    }

    #[test]
    fn parses_folded_and_escaped_vikunja_task_fields() {
        let parsed = parse_vtodo_resource(
            VIKUNJA_TASK,
            &collection(),
            &resource("42.ics"),
            "Work",
            Some("\"etag-42\"".into()),
        )
        .unwrap()
        .unwrap();
        let task = parsed.task.as_ref().unwrap();

        assert_eq!(task.identity.collection_href, collection().as_str());
        assert_eq!(task.identity.resource_href, resource("42.ics").as_str());
        assert_eq!(task.uid, "vikunja-task-42");
        assert_eq!(
            task.title,
            "Write CalDAV, parser; preserve\nall fields and folded text"
        );
        assert_eq!(task.collection_name, "Work");
        assert_eq!(task.status, TaskStatus::Active);
        assert_eq!(parsed.etag.as_deref(), Some("\"etag-42\""));
        assert_eq!(parsed.icalendar, VIKUNJA_TASK);
    }

    #[test]
    fn hides_cancelled_task_but_retains_lossless_resource() {
        let parsed = parse_vtodo_resource(
            CANCELLED_TASK,
            &collection(),
            &resource("cancelled.ics"),
            "Work",
            None,
        )
        .unwrap()
        .unwrap();

        assert!(parsed.task.is_none());
        assert_eq!(parsed.icalendar, CANCELLED_TASK);
    }

    #[test]
    fn maps_missing_title_statuses_and_all_priority_levels() {
        let cases = [
            ("NEEDS-ACTION", "1", TaskStatus::Active, TaskPriority::DoNow),
            ("IN-PROCESS", "2", TaskStatus::Active, TaskPriority::Urgent),
            ("COMPLETED", "3", TaskStatus::Completed, TaskPriority::High),
            ("NEEDS-ACTION", "4", TaskStatus::Active, TaskPriority::High),
            (
                "NEEDS-ACTION",
                "5",
                TaskStatus::Active,
                TaskPriority::Medium,
            ),
            ("NEEDS-ACTION", "0", TaskStatus::Active, TaskPriority::Low),
            ("NEEDS-ACTION", "9", TaskStatus::Active, TaskPriority::Low),
        ];
        for (index, (status, priority, expected_status, expected_priority)) in
            cases.into_iter().enumerate()
        {
            let source = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:{index}\r\nSTATUS:{status}\r\nPRIORITY:{priority}\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );
            let task = parse_vtodo_resource(
                &source,
                &collection(),
                &resource(&format!("priority-{index}.ics")),
                "Work",
                None,
            )
            .unwrap()
            .unwrap()
            .task
            .unwrap();
            assert_eq!(task.title, "(No title)");
            assert_eq!(task.status, expected_status);
            assert_eq!(task.priority, expected_priority);
        }
    }

    #[test]
    fn uses_resource_href_as_stable_uid_when_uid_is_missing() {
        let source =
            "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nSUMMARY:No UID\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let href = resource("missing-uid.ics");
        let task = parse_vtodo_resource(source, &collection(), &href, "Work", None)
            .unwrap()
            .unwrap()
            .task
            .unwrap();
        assert_eq!(task.uid, href.as_str());
    }

    #[test]
    fn normalizes_date_utc_tzid_and_floating_values_at_local_midnight() {
        let local_zone = LocalZone::Named(chrono_tz::America::Los_Angeles);
        let cases = [
            (
                "DUE;VALUE=DATE:20260721\r\nCOMPLETED;VALUE=DATE:20260721",
                "2026-07-21",
                Utc.with_ymd_and_hms(2026, 7, 21, 7, 0, 0)
                    .single()
                    .unwrap()
                    .timestamp(),
            ),
            (
                "DUE:20260721T003000Z\r\nCOMPLETED:20260721T003000Z",
                "2026-07-20",
                Utc.with_ymd_and_hms(2026, 7, 21, 0, 30, 0)
                    .single()
                    .unwrap()
                    .timestamp(),
            ),
            (
                "DUE;TZID=America/New_York:20260721T003000\r\nCOMPLETED;TZID=America/New_York:20260721T003000",
                "2026-07-20",
                Utc.with_ymd_and_hms(2026, 7, 21, 4, 30, 0)
                    .single()
                    .unwrap()
                    .timestamp(),
            ),
            (
                "DUE:20260721T003000\r\nCOMPLETED:20260721T003000",
                "2026-07-21",
                Utc.with_ymd_and_hms(2026, 7, 21, 7, 30, 0)
                    .single()
                    .unwrap()
                    .timestamp(),
            ),
        ];

        for (properties, expected_date, expected_completed) in cases {
            let source = format!(
                "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:date-test\r\n{properties}\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
            );
            let task = parse_vtodo_resource_in_zone(
                &source,
                &collection(),
                &resource("date-test.ics"),
                "Work",
                None,
                local_zone,
            )
            .unwrap()
            .unwrap()
            .task
            .unwrap();

            assert_eq!(task.due_date.as_deref(), Some(expected_date));
            assert_eq!(task.completed_at_unix_secs, Some(expected_completed));
            assert!(!task.due_date.unwrap().contains(':'));
        }
    }

    #[test]
    fn rejects_unknown_tzid_without_exposing_resource_content() {
        let source = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:secret-uid\r\nDUE;TZID=Secret/Unknown:20260721T003000\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let error = parse_vtodo_resource_in_zone(
            source,
            &collection(),
            &resource("bad-zone.ics"),
            "Work",
            None,
            LocalZone::Named(chrono_tz::UTC),
        )
        .unwrap_err();
        assert_eq!(error.to_string(), "unknown iCalendar timezone");
        assert!(!error.to_string().contains("secret-uid"));
    }

    #[test]
    fn returns_none_for_resource_without_vtodo_and_redacts_parse_details() {
        let event =
            "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:event-1\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
        assert!(
            parse_vtodo_resource(event, &collection(), &resource("event.ics"), "Work", None)
                .unwrap()
                .is_none()
        );

        let error = parse_vtodo_resource(
            "BEGIN:broken-secret-resource",
            &collection(),
            &resource("bad.ics"),
            "Work",
            None,
        )
        .unwrap_err();
        assert_eq!(error.to_string(), "invalid iCalendar resource");
        assert!(!error.to_string().contains("secret"));
    }
}
