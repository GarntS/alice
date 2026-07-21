use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
};

use chrono::{Local, NaiveDate, Utc};
use tokio::sync::mpsc;

use crate::{config::ValidatedCalDavConfig, runtime::Trigger};

use super::{
    CalDavFreshness, TaskResourceIdentity,
    cache::{CacheLoad, default_cache_path, load_cache, store_cache},
    client::{CalDavClient, CalDavClientError},
    provider::CalDavCacheProvider,
};

#[derive(Debug, Clone)]
pub struct CalDavRefreshHandle {
    sender: mpsc::Sender<()>,
    queued: Arc<AtomicBool>,
}

impl CalDavRefreshHandle {
    pub fn request_refresh(&self) -> bool {
        if self.queued.swap(true, Ordering::AcqRel) {
            return false;
        }
        match self.sender.try_send(()) {
            Ok(()) => true,
            Err(_) => {
                self.queued.store(false, Ordering::Release);
                false
            }
        }
    }
}

pub fn refresh_channel() -> (CalDavRefreshHandle, mpsc::Receiver<()>) {
    let (sender, receiver) = mpsc::channel(1);
    (
        CalDavRefreshHandle {
            sender,
            queued: Arc::new(AtomicBool::new(false)),
        },
        receiver,
    )
}

static GLOBAL_REFRESH: OnceLock<CalDavRefreshHandle> = OnceLock::new();
static GLOBAL_CORE: OnceLock<Arc<RuntimeCore>> = OnceLock::new();

pub fn request_global_refresh() -> bool {
    GLOBAL_REFRESH
        .get()
        .is_some_and(CalDavRefreshHandle::request_refresh)
}

pub async fn mutate_global_task(
    identity: TaskResourceIdentity,
    completed: bool,
) -> Result<(), CalDavClientError> {
    let core = GLOBAL_CORE
        .get()
        .cloned()
        .ok_or_else(|| CalDavClientError::new("CalDAV runtime is not available"))?;
    core.mutate_task(identity, completed).await
}

pub fn start_runtime_service(
    config: ValidatedCalDavConfig,
    trigger: mpsc::Sender<Trigger>,
) -> Result<CalDavCacheProvider, CalDavClientError> {
    let cache_path = default_cache_path().map_err(|error| {
        CalDavClientError::new(format!("failed to resolve CalDAV cache path: {error}"))
    })?;
    let state = match load_cache(&cache_path)
        .map_err(|error| CalDavClientError::new(format!("failed to load CalDAV cache: {error}")))?
    {
        CacheLoad::Loaded(state) => state,
        CacheLoad::Missing | CacheLoad::Invalid => Default::default(),
    };
    let provider = CalDavCacheProvider::new(prepare_startup_state(state));
    CalDavCacheProvider::install_global(provider.clone());
    let client = CalDavClient::new(config.clone())?;
    let (handle, receiver) = refresh_channel();
    let _ = GLOBAL_REFRESH.set(handle.clone());
    let core = Arc::new(RuntimeCore {
        client,
        provider: provider.clone(),
        cache_path,
        trigger,
    });
    let _ = GLOBAL_CORE.set(core.clone());
    tokio::spawn(run_refresh_loop(
        handle,
        receiver,
        config.poll_interval_secs,
        move |date_changed| {
            let core = core.clone();
            async move { core.refresh(date_changed).await }
        },
        || Local::now().date_naive(),
    ));
    Ok(provider)
}

fn prepare_startup_state(mut state: super::CalDavCacheModel) -> super::CalDavCacheModel {
    if state.resources.is_empty() {
        state.sync_state.freshness = CalDavFreshness::Loading;
        state.sync_state.has_cached_data = false;
    } else {
        state.sync_state.freshness = CalDavFreshness::Stale;
        state.sync_state.has_cached_data = true;
    }
    state.sync_state.error = None;
    state
}

struct RuntimeCore {
    client: CalDavClient,
    provider: CalDavCacheProvider,
    cache_path: PathBuf,
    trigger: mpsc::Sender<Trigger>,
}

impl RuntimeCore {
    async fn mutate_task(
        &self,
        identity: TaskResourceIdentity,
        completed: bool,
    ) -> Result<(), CalDavClientError> {
        let state = self.provider.persisted_state();
        let resource = state
            .resources
            .get(&identity.resource_href)
            .filter(|resource| resource.identity == identity)
            .cloned()
            .ok_or_else(|| CalDavClientError::new("CalDAV task is no longer available"))?;
        let collection_name = resource
            .task
            .as_ref()
            .map(|task| task.collection_name.as_str())
            .unwrap_or("CalDAV");
        let authoritative = self
            .client
            .mutate_task_completion(&resource, completed, Utc::now(), collection_name)
            .await?;
        let href = authoritative.identity.resource_href.clone();
        let visible_changed = self.provider.update(move |state| {
            state.resources.insert(href, authoritative);
        });
        store_cache(&self.cache_path, &self.provider.persisted_state()).map_err(|error| {
            CalDavClientError::new(format!("failed to persist CalDAV mutation: {error}"))
        })?;
        if visible_changed {
            let _ = self.trigger.send(Trigger::Event).await;
        }
        Ok(())
    }

    async fn refresh(&self, date_changed: bool) {
        if self.provider.update(|state| {
            state.sync_state.freshness = CalDavFreshness::Loading;
            state.sync_state.error = None;
        }) {
            let _ = self.trigger.send(Trigger::Event).await;
        }

        let discovery = match self.client.discover().await {
            Ok(discovery) => discovery,
            Err(error) => {
                self.publish_failure(error.to_string()).await;
                return;
            }
        };
        let persisted = self.provider.persisted_state();
        let mut successful = Vec::new();
        let mut errors = discovery.errors;
        for mut collection in discovery.collections {
            let collection_key = super::collection_url_key(&collection.href);
            collection.sync_token = cached_sync_token(&persisted, &collection);
            if date_changed && collection.supports_vevent {
                collection.sync_token = None;
            }
            let existing = persisted
                .resources
                .iter()
                .filter(|(_, resource)| {
                    url::Url::parse(&resource.identity.collection_href)
                        .is_ok_and(|href| super::collection_url_key(&href) == collection_key)
                })
                .map(|(href, resource)| (href.clone(), resource.clone()))
                .collect::<BTreeMap<_, _>>();
            match self
                .client
                .synchronize_collection(&collection, &existing)
                .await
            {
                Ok(result) => successful.push(result),
                Err(error) => errors.push(format!(
                    "CalDAV collection {} failed: {}",
                    collection.display_name,
                    self.client.redact(error.message())
                )),
            }
        }

        let now = Utc::now().timestamp();
        let visible_changed = self.provider.update(|state| {
            for result in successful.iter() {
                let collection_href = result.collection.href.to_string();
                let collection_key = super::collection_url_key(&result.collection.href);
                state.resources.retain(|_, resource| {
                    match url::Url::parse(&resource.identity.collection_href) {
                        Ok(href) => super::collection_url_key(&href) != collection_key,
                        Err(_) => true,
                    }
                });
                state.resources.extend(result.resources.clone());
                state
                    .collections
                    .retain(|_, cached| super::collection_url_key(&cached.href) != collection_key);
                state
                    .collections
                    .insert(collection_href, result.collection.clone());
                if let Some(window) = &result.event_window {
                    state.event_window = Some(window.clone());
                }
            }
            state.sync_state.has_cached_data = !state.resources.is_empty();
            if errors.is_empty() {
                state.sync_state.freshness = CalDavFreshness::Current;
                state.sync_state.error = None;
            } else {
                state.sync_state.freshness = CalDavFreshness::Error;
                state.sync_state.error = Some(errors.join("; "));
            }
            if !successful.is_empty() {
                state.sync_state.last_success_unix_secs = Some(now);
            }
        });
        if let Err(error) = store_cache(&self.cache_path, &self.provider.persisted_state()) {
            self.publish_failure(format!("failed to persist CalDAV cache: {error}"))
                .await;
            return;
        }
        if visible_changed {
            let _ = self.trigger.send(Trigger::Event).await;
        }
    }

    async fn publish_failure(&self, message: String) {
        let message = self.client.redact(&message);
        if self.provider.update(|state| {
            state.sync_state.freshness = CalDavFreshness::Error;
            state.sync_state.error = Some(message);
            state.sync_state.has_cached_data = !state.resources.is_empty();
        }) {
            let _ = self.trigger.send(Trigger::Event).await;
        }
    }
}

fn cached_sync_token(
    persisted: &super::CalDavCacheModel,
    discovered: &super::CalDavCollection,
) -> Option<String> {
    let discovered_key = super::collection_url_key(&discovered.href);
    persisted
        .collections
        .values()
        .find(|cached| super::collection_url_key(&cached.href) == discovered_key)
        .and_then(|cached| cached.sync_token.clone())
}

/// Run immediate startup synchronization, periodic polling, panel/manual
/// requests, and local-date reconciliation with at most one active pass.
pub async fn run_refresh_loop<F, FutureValue, D>(
    handle: CalDavRefreshHandle,
    mut receiver: mpsc::Receiver<()>,
    poll_interval_secs: u32,
    mut refresh: F,
    mut today: D,
) where
    F: FnMut(bool) -> FutureValue,
    FutureValue: Future<Output = ()>,
    D: FnMut() -> NaiveDate,
{
    let mut last_date = today();
    refresh(true).await;
    let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(
        poll_interval_secs.max(1) as u64,
    ));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    interval.tick().await;

    loop {
        let requested = tokio::select! {
            value = receiver.recv() => {
                if value.is_none() { break; }
                true
            }
            _ = interval.tick() => false,
        };
        let current_date = today();
        let date_changed = current_date != last_date;
        last_date = current_date;
        refresh(date_changed).await;

        // Requests made during the pass are deliberately coalesced into that
        // pass. Drain their one-slot notification before accepting new work.
        while receiver.try_recv().is_ok() {}
        handle.queued.store(false, Ordering::Release);
        let _ = requested;
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::caldav::{
        CalDavCacheModel, CalDavCollection, CalDavResourceKind, LosslessCalDavResource,
        TaskResourceIdentity,
    };

    #[test]
    fn cached_startup_is_published_stale_and_empty_startup_loads() {
        let empty = prepare_startup_state(CalDavCacheModel::default());
        assert_eq!(empty.sync_state.freshness, CalDavFreshness::Loading);
        assert!(!empty.sync_state.has_cached_data);

        let mut cached = CalDavCacheModel::default();
        cached.resources.insert(
            "https://example.test/tasks/1.ics".into(),
            LosslessCalDavResource {
                identity: TaskResourceIdentity {
                    collection_href: "https://example.test/tasks/".into(),
                    resource_href: "https://example.test/tasks/1.ics".into(),
                },
                etag: Some("\"one\"".into()),
                icalendar: "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n".into(),
                kind: CalDavResourceKind::Unknown,
                task: None,
                events: vec![],
            },
        );
        cached.sync_state.error = Some("old error".into());
        let cached = prepare_startup_state(cached);
        assert_eq!(cached.sync_state.freshness, CalDavFreshness::Stale);
        assert!(cached.sync_state.has_cached_data);
        assert_eq!(cached.sync_state.error, None);
    }

    #[test]
    fn fresh_discovery_does_not_reuse_server_token_but_cached_slash_variant_does() {
        let mut discovered = CalDavCollection {
            href: url::Url::parse("https://example.test/dav/projects/36").unwrap(),
            display_name: "Work".into(),
            supports_vtodo: true,
            supports_vevent: false,
            supports_sync_collection: true,
            sync_token: Some("server-current-token".into()),
        };
        let mut cache = CalDavCacheModel::default();

        discovered.sync_token = cached_sync_token(&cache, &discovered);
        assert_eq!(
            discovered.sync_token, None,
            "fresh sync must be authoritative"
        );

        let mut cached = discovered.clone();
        cached.href = url::Url::parse("https://example.test/dav/projects/36/").unwrap();
        cached.sync_token = Some("alice-persisted-token".into());
        cache.collections.insert(cached.href.to_string(), cached);
        assert_eq!(
            cached_sync_token(&cache, &discovered).as_deref(),
            Some("alice-persisted-token")
        );
    }

    #[tokio::test(start_paused = true)]
    async fn startup_poll_and_concurrent_requests_are_coalesced() {
        let (handle, receiver) = refresh_channel();
        let calls = Arc::new(AtomicUsize::new(0));
        let observed = calls.clone();
        let task_handle = handle.clone();
        let task = tokio::spawn(async move {
            run_refresh_loop(
                task_handle,
                receiver,
                60,
                move |_| {
                    let observed = observed.clone();
                    async move {
                        observed.fetch_add(1, Ordering::SeqCst);
                        tokio::task::yield_now().await;
                    }
                },
                || chrono::NaiveDate::from_ymd_opt(2026, 7, 20).unwrap(),
            )
            .await;
        });
        tokio::task::yield_now().await;
        assert_eq!(calls.load(Ordering::SeqCst), 1, "startup refresh");
        assert!(handle.request_refresh());
        assert!(!handle.request_refresh());
        assert!(!handle.request_refresh());
        tokio::task::yield_now().await;
        tokio::task::yield_now().await;
        assert_eq!(calls.load(Ordering::SeqCst), 2);

        tokio::time::advance(tokio::time::Duration::from_secs(60)).await;
        tokio::task::yield_now().await;
        assert_eq!(calls.load(Ordering::SeqCst), 3, "background poll");
        task.abort();
    }

    #[tokio::test]
    async fn date_change_is_reported_to_refresh_pass() {
        let (handle, receiver) = refresh_channel();
        let dates = Arc::new(AtomicUsize::new(0));
        let date_counter = dates.clone();
        let rollovers = Arc::new(AtomicUsize::new(0));
        let rollover_counter = rollovers.clone();
        let task_handle = handle.clone();
        let task = tokio::spawn(async move {
            run_refresh_loop(
                task_handle,
                receiver,
                3600,
                move |date_changed| {
                    let rollover_counter = rollover_counter.clone();
                    async move {
                        if date_changed {
                            rollover_counter.fetch_add(1, Ordering::SeqCst);
                        }
                    }
                },
                move || {
                    chrono::NaiveDate::from_ymd_opt(
                        2026,
                        7,
                        20 + date_counter.fetch_add(1, Ordering::SeqCst) as u32,
                    )
                    .unwrap()
                },
            )
            .await;
        });
        tokio::task::yield_now().await;
        assert!(handle.request_refresh());
        tokio::task::yield_now().await;
        tokio::task::yield_now().await;
        assert_eq!(rollovers.load(Ordering::SeqCst), 1);
        task.abort();
    }
}
