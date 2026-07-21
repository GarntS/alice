use std::{cmp::Ordering, collections::BTreeMap};

use serde::{Deserialize, Serialize};
use url::Url;

/// Metadata and synchronization capabilities for one allowlisted collection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CalDavCollection {
    pub href: Url,
    pub display_name: String,
    pub supports_vtodo: bool,
    pub supports_vevent: bool,
    pub supports_sync_collection: bool,
    pub sync_token: Option<String>,
}

/// Stable identity used by snapshots and completion requests.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct TaskResourceIdentity {
    pub collection_href: String,
    pub resource_href: String,
}

/// A complete server resource plus the typed records derived from it.
///
/// `icalendar` is retained verbatim and is the only source used when patching a
/// VTODO. This prevents typed normalization from discarding unknown content.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LosslessCalDavResource {
    pub identity: TaskResourceIdentity,
    pub etag: Option<String>,
    pub icalendar: String,
    pub kind: CalDavResourceKind,
    pub task: Option<NormalizedTask>,
    pub events: Vec<CalDavEvent>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CalDavResourceKind {
    Todo,
    Event,
    Mixed,
    Unknown,
}

/// UI-safe normalized VTODO fields. No time label or credential can enter this
/// model; completion instants are retained only as sortable Unix timestamps.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NormalizedTask {
    pub identity: TaskResourceIdentity,
    pub uid: String,
    pub title: String,
    pub collection_name: String,
    /// Machine-local `YYYY-MM-DD`, or `None` for an undated task.
    pub due_date: Option<String>,
    /// UTC Unix seconds, used for local completion-day filtering and ordering.
    pub completed_at_unix_secs: Option<i64>,
    pub status: TaskStatus,
    pub priority: TaskPriority,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskPriority {
    DoNow,
    Urgent,
    High,
    Medium,
    Low,
}

impl TaskPriority {
    pub fn from_ical(value: Option<i32>) -> Self {
        match value {
            Some(1) => Self::DoNow,
            Some(2) => Self::Urgent,
            Some(3 | 4) => Self::High,
            Some(5) => Self::Medium,
            _ => Self::Low,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Active,
    Completed,
    Cancelled,
}

/// Sort normalized tasks into dated active, undated active, completed, and
/// cancelled groups using stable, user-visible tie-breakers.
pub fn sort_normalized_tasks(tasks: &mut [NormalizedTask]) {
    tasks.sort_by(compare_normalized_tasks);
}

pub fn compare_normalized_tasks(left: &NormalizedTask, right: &NormalizedTask) -> Ordering {
    let left_group = task_sort_group(left);
    let right_group = task_sort_group(right);
    left_group
        .cmp(&right_group)
        .then_with(|| match left_group {
            0 => left.due_date.cmp(&right.due_date),
            2 => right
                .completed_at_unix_secs
                .cmp(&left.completed_at_unix_secs),
            _ => Ordering::Equal,
        })
        .then_with(|| left.priority.cmp(&right.priority))
        .then_with(|| left.title.to_lowercase().cmp(&right.title.to_lowercase()))
        .then_with(|| {
            left.identity
                .resource_href
                .cmp(&right.identity.resource_href)
        })
}

fn task_sort_group(task: &NormalizedTask) -> u8 {
    match (task.status, task.due_date.is_some()) {
        (TaskStatus::Active, true) => 0,
        (TaskStatus::Active, false) => 1,
        (TaskStatus::Completed, _) => 2,
        (TaskStatus::Cancelled, _) => 3,
    }
}

/// Typed VEVENT base record. Recurrences remain definitions, never expanded
/// occurrences, in this change.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CalDavEvent {
    pub collection_href: String,
    pub resource_href: String,
    pub uid: String,
    pub summary: String,
    pub start: CalendarValue,
    pub end: Option<CalendarValue>,
    pub recurrence: RecurrenceMetadata,
    pub referenced_timezones: Vec<TimezoneDefinition>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum CalendarValue {
    Date {
        /// Calendar date preserved exactly as `YYYY-MM-DD`.
        date: String,
    },
    DateTime {
        /// Original iCalendar basic DATE-TIME value.
        value: String,
        timezone_id: Option<String>,
        is_utc: bool,
        is_floating: bool,
    },
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecurrenceMetadata {
    pub rrules: Vec<String>,
    pub rdates: Vec<CalendarValue>,
    pub exdates: Vec<CalendarValue>,
    pub recurrence_id: Option<CalendarValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimezoneDefinition {
    pub tzid: String,
    /// Complete source VTIMEZONE component, retained for lossless persistence.
    pub raw_component: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventWindow {
    /// Inclusive machine-local date (`YYYY-MM-DD`).
    pub start_date: String,
    /// Inclusive machine-local date (`YYYY-MM-DD`).
    pub end_date: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CalDavFreshness {
    Disabled,
    Loading,
    Current,
    Stale,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CalDavSyncState {
    pub freshness: CalDavFreshness,
    pub last_success_unix_secs: Option<i64>,
    pub error: Option<String>,
    pub has_cached_data: bool,
}

impl Default for CalDavSyncState {
    fn default() -> Self {
        Self {
            freshness: CalDavFreshness::Disabled,
            last_success_unix_secs: None,
            error: None,
            has_cached_data: false,
        }
    }
}

/// Deterministically serialized native state for one synchronization pass.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CalDavCacheModel {
    pub collections: BTreeMap<String, CalDavCollection>,
    pub resources: BTreeMap<String, LosslessCalDavResource>,
    pub event_window: Option<EventWindow>,
    pub sync_state: CalDavSyncState,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn priority_order_and_mapping_are_deterministic() {
        assert!(TaskPriority::DoNow < TaskPriority::Urgent);
        assert!(TaskPriority::Urgent < TaskPriority::High);
        assert!(TaskPriority::High < TaskPriority::Medium);
        assert!(TaskPriority::Medium < TaskPriority::Low);

        assert_eq!(TaskPriority::from_ical(Some(1)), TaskPriority::DoNow);
        assert_eq!(TaskPriority::from_ical(Some(2)), TaskPriority::Urgent);
        assert_eq!(TaskPriority::from_ical(Some(4)), TaskPriority::High);
        assert_eq!(TaskPriority::from_ical(Some(5)), TaskPriority::Medium);
        assert_eq!(TaskPriority::from_ical(None), TaskPriority::Low);
        assert_eq!(TaskPriority::from_ical(Some(9)), TaskPriority::Low);
        assert_eq!(TaskPriority::from_ical(Some(10)), TaskPriority::Low);
    }

    #[test]
    fn cache_json_uses_stable_btree_key_order_and_round_trips() {
        let mut cache = CalDavCacheModel::default();
        for name in ["zeta", "alpha"] {
            let href = Url::parse(&format!("https://example.test/{name}/")).unwrap();
            cache.collections.insert(
                name.into(),
                CalDavCollection {
                    href,
                    display_name: name.into(),
                    supports_vtodo: true,
                    supports_vevent: false,
                    supports_sync_collection: true,
                    sync_token: Some(format!("token-{name}")),
                },
            );
        }

        let json = serde_json::to_string(&cache).unwrap();
        assert!(json.find("alpha").unwrap() < json.find("zeta").unwrap());
        assert_eq!(
            serde_json::from_str::<CalDavCacheModel>(&json).unwrap(),
            cache
        );
    }

    fn task(
        href: &str,
        title: &str,
        due_date: Option<&str>,
        status: TaskStatus,
        priority: TaskPriority,
        completed_at_unix_secs: Option<i64>,
    ) -> NormalizedTask {
        NormalizedTask {
            identity: TaskResourceIdentity {
                collection_href: "https://example.test/tasks/".into(),
                resource_href: href.into(),
            },
            uid: href.into(),
            title: title.into(),
            collection_name: "Tasks".into(),
            due_date: due_date.map(Into::into),
            completed_at_unix_secs,
            status,
            priority,
        }
    }

    #[test]
    fn task_order_is_dated_then_undated_then_newest_completed() {
        let mut tasks = vec![
            task(
                "completed-old",
                "Done",
                Some("2026-07-01"),
                TaskStatus::Completed,
                TaskPriority::Low,
                Some(10),
            ),
            task(
                "undated",
                "Later",
                None,
                TaskStatus::Active,
                TaskPriority::DoNow,
                None,
            ),
            task(
                "due-low",
                "alpha",
                Some("2026-07-20"),
                TaskStatus::Active,
                TaskPriority::Low,
                None,
            ),
            task(
                "completed-new",
                "Done",
                None,
                TaskStatus::Completed,
                TaskPriority::Low,
                Some(20),
            ),
            task(
                "due-urgent",
                "Zulu",
                Some("2026-07-20"),
                TaskStatus::Active,
                TaskPriority::Urgent,
                None,
            ),
            task(
                "due-earlier",
                "Earlier",
                Some("2026-07-19"),
                TaskStatus::Active,
                TaskPriority::Low,
                None,
            ),
        ];

        sort_normalized_tasks(&mut tasks);
        assert_eq!(
            tasks
                .iter()
                .map(|task| task.identity.resource_href.as_str())
                .collect::<Vec<_>>(),
            [
                "due-earlier",
                "due-urgent",
                "due-low",
                "undated",
                "completed-new",
                "completed-old",
            ]
        );
    }

    #[test]
    fn task_order_uses_case_insensitive_title_then_href() {
        let mut tasks = vec![
            task(
                "b",
                "ALPHA",
                None,
                TaskStatus::Active,
                TaskPriority::Medium,
                None,
            ),
            task(
                "a",
                "alpha",
                None,
                TaskStatus::Active,
                TaskPriority::Medium,
                None,
            ),
        ];
        sort_normalized_tasks(&mut tasks);
        assert_eq!(tasks[0].identity.resource_href, "a");
        assert_eq!(tasks[1].identity.resource_href, "b");
    }

    #[test]
    fn lossless_resource_equality_includes_source_and_typed_content() {
        let resource = LosslessCalDavResource {
            identity: TaskResourceIdentity {
                collection_href: "https://example.test/tasks/".into(),
                resource_href: "https://example.test/tasks/1.ics".into(),
            },
            etag: Some("\"one\"".into()),
            icalendar: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".into(),
            kind: CalDavResourceKind::Todo,
            task: None,
            events: vec![],
        };
        let mut changed = resource.clone();
        changed.icalendar.push_str("X-UNKNOWN:preserved\r\n");
        assert_ne!(resource, changed);
    }
}
