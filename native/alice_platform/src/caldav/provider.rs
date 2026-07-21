use std::sync::{Arc, OnceLock, RwLock};

use super::{CalDavCacheModel, CalDavSyncState, NormalizedTask, sort_normalized_tasks};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalDavSnapshot {
    pub tasks: Vec<NormalizedTask>,
    pub sync_state: CalDavSyncState,
}

/// In-memory provider read by snapshot assembly. It owns no client and its read
/// path cannot perform network or disk I/O.
#[derive(Debug, Clone, Default)]
pub struct CalDavCacheProvider {
    state: Arc<RwLock<CalDavCacheModel>>,
}

static GLOBAL_PROVIDER: OnceLock<CalDavCacheProvider> = OnceLock::new();

impl CalDavCacheProvider {
    pub fn install_global(provider: CalDavCacheProvider) {
        let _ = GLOBAL_PROVIDER.set(provider);
    }

    pub fn global() -> Option<CalDavCacheProvider> {
        GLOBAL_PROVIDER.get().cloned()
    }

    pub fn new(state: CalDavCacheModel) -> Self {
        Self {
            state: Arc::new(RwLock::new(state)),
        }
    }

    pub fn snapshot(&self) -> CalDavSnapshot {
        snapshot_from_state(&self.state.read().unwrap_or_else(|lock| lock.into_inner()))
    }

    pub fn persisted_state(&self) -> CalDavCacheModel {
        self.state
            .read()
            .unwrap_or_else(|lock| lock.into_inner())
            .clone()
    }

    /// Mutate native cache state and report only whether snapshot-visible task
    /// or synchronization content changed.
    pub fn update(&self, update: impl FnOnce(&mut CalDavCacheModel)) -> bool {
        let mut state = self.state.write().unwrap_or_else(|lock| lock.into_inner());
        let before = snapshot_from_state(&state);
        update(&mut state);
        before != snapshot_from_state(&state)
    }
}

fn snapshot_from_state(state: &CalDavCacheModel) -> CalDavSnapshot {
    let mut tasks = state
        .resources
        .values()
        .filter_map(|resource| resource.task.clone())
        .collect::<Vec<_>>();
    sort_normalized_tasks(&mut tasks);
    CalDavSnapshot {
        tasks,
        sync_state: state.sync_state.clone(),
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeMap, thread};

    use super::*;
    use crate::caldav::{CalDavCollection, CalDavFreshness, ical::parse_vtodo_resource};

    #[test]
    fn repeated_unrelated_snapshot_reads_never_invoke_caldav_io() {
        let provider = CalDavCacheProvider::default();
        let network_calls = std::sync::atomic::AtomicUsize::new(0);
        for _ in 0..1_000 {
            let _ = provider.snapshot();
        }
        assert_eq!(
            network_calls.load(std::sync::atomic::Ordering::SeqCst),
            0,
            "cache provider has no network boundary on its read path"
        );
    }

    #[test]
    fn synchronization_failure_retains_cached_tasks() {
        let collection = url::Url::parse("https://example.test/tasks/").unwrap();
        let href = collection.join("1.ics").unwrap();
        let source = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:one\r\nSUMMARY:Cached task\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let resource = parse_vtodo_resource(source, &collection, &href, "Tasks", None)
            .unwrap()
            .unwrap();
        let mut state = CalDavCacheModel::default();
        state.resources.insert(href.to_string(), resource);
        let provider = CalDavCacheProvider::new(state);
        assert_eq!(provider.snapshot().tasks.len(), 1);

        assert!(provider.update(|state| {
            state.sync_state.freshness = CalDavFreshness::Error;
            state.sync_state.error = Some("redacted transport failure".into());
            state.sync_state.has_cached_data = true;
        }));
        let snapshot = provider.snapshot();
        assert_eq!(snapshot.tasks.len(), 1);
        assert_eq!(snapshot.tasks[0].title, "Cached task");
        assert_eq!(snapshot.sync_state.freshness, CalDavFreshness::Error);
    }

    #[test]
    fn reads_are_concurrency_safe_and_metadata_only_updates_are_not_visible() {
        let provider = CalDavCacheProvider::default();
        let readers = (0..8)
            .map(|_| {
                let provider = provider.clone();
                thread::spawn(move || {
                    for _ in 0..100 {
                        assert!(provider.snapshot().tasks.is_empty());
                    }
                })
            })
            .collect::<Vec<_>>();

        assert!(!provider.update(|state| {
            state.collections = BTreeMap::from([(
                "work".into(),
                CalDavCollection {
                    href: url::Url::parse("https://example.test/work/").unwrap(),
                    display_name: "Work".into(),
                    supports_vtodo: true,
                    supports_vevent: false,
                    supports_sync_collection: true,
                    sync_token: Some("native-only-token".into()),
                },
            )]);
        }));
        assert!(provider.update(|state| {
            state.sync_state.freshness = CalDavFreshness::Loading;
        }));
        for reader in readers {
            reader.join().unwrap();
        }
    }
}
