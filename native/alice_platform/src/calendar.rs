//! Google Calendar integration.
//!
//! Fetches events for a given date using the Google Calendar API with
//! installed-flow OAuth2 authentication (yup-oauth2 + google-calendar3).
//!
//! Authentication state is held in a process-global `Mutex` so that:
//! - The first call initiates an installed flow and returns the auth URL.
//! - Subsequent calls while polling return the same URL.
//! - Once authorised, calls proceed to the Calendar API.

use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{LazyLock, Mutex, OnceLock},
    time::Duration,
};

// ---------------------------------------------------------------------------
// Shared tokio runtime + stored authenticator
//
// A single multi-thread runtime is shared across both the auth flow thread and
// every do_fetch_events call, so all tokio resources (hyper clients, TCP
// sockets) belong to the same runtime. The Authenticator is stored globally
// after the initial auth succeeds; do_fetch_events reuses it directly rather
// than building a new one, preventing duplicate port-8085 binds.
// ---------------------------------------------------------------------------

type CalendarAuth = yup_oauth2::authenticator::Authenticator<
    hyper_rustls::HttpsConnector<hyper_util::client::legacy::connect::HttpConnector>,
>;

static CALENDAR_RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static CALENDAR_AUTH: LazyLock<Mutex<HashMap<String, CalendarAuth>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn calendar_runtime() -> &'static tokio::runtime::Runtime {
    CALENDAR_RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(1)
            .enable_all()
            .build()
            .expect("[alice/calendar] failed to create tokio runtime")
    })
}

use crate::{
    config::{CalendarConfig, CalendarEntry, CalendarEntryKind},
    state::{CalendarEvent, CalendarFetchResult},
};

// ---------------------------------------------------------------------------
// Event cache
//
// Holds a ~6-month window of events (3 months either side) so that date taps within the window are
// served instantly. `cal_meta` maps calendar IDs to (name, color) so that
// incremental-sync responses can populate new events with the right metadata.
// ---------------------------------------------------------------------------

struct EventCache {
    window_start: chrono::NaiveDate,
    window_end: chrono::NaiveDate,
    /// All events in the window, tagged with their calendar date.
    entries: Vec<(chrono::NaiveDate, CalendarEvent)>,
    /// Per-calendar sync token for incremental updates.
    sync_tokens: HashMap<String, String>,
    /// Calendar display metadata: id → (name, background_color).
    cal_meta: HashMap<String, (String, String)>,
}

static EVENT_CACHE: LazyLock<Mutex<HashMap<String, EventCache>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static POLL_ABORT: LazyLock<Mutex<HashMap<String, tokio::task::AbortHandle>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// ---------------------------------------------------------------------------
// Global auth state
// ---------------------------------------------------------------------------

enum AuthState {
    Uninitiated,
    PendingFlow { url: String },
    Authorized,
    Failed(String),
}

static AUTH_STATE: LazyLock<Mutex<HashMap<String, AuthState>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// ---------------------------------------------------------------------------
// Token storage path
// ---------------------------------------------------------------------------

fn token_path(source_id: &str) -> PathBuf {
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(p) if !p.is_empty() => PathBuf::from(p),
        _ => {
            let home = std::env::var_os("HOME").unwrap_or_default();
            PathBuf::from(home).join(".config")
        }
    };
    base.join("alice")
        .join("calendar_tokens")
        .join(format!("{source_id}.json"))
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn fetch_events(date: &str, config: &CalendarConfig) -> CalendarFetchResult {
    let date_naive = match chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d") {
        Ok(date) => date,
        Err(_) => return err_result(format!("invalid date: {date}")),
    };
    // Source workers own ICS acquisition. Date requests only query their
    // merged snapshot and therefore never cause an ICS network request.
    let merged_events = crate::calendar_sources::global_coordinator()
        .map(|coordinator| coordinator.events_for_date(date_naive))
        .unwrap_or_default();
    let has_google = config
        .calendars
        .iter()
        .any(|entry| matches!(entry.kind, CalendarEntryKind::Google { .. }));
    if !has_google {
        return CalendarFetchResult {
            status: "ready".into(),
            events: merged_events,
            ..Default::default()
        };
    }
    // Google authorization remains panel-driven; its results are merged by the
    // source coordinator once a source has completed device authorization.
    let Some(config) = config
        .calendars
        .iter()
        .find(|entry| matches!(entry.kind, CalendarEntryKind::Google { .. }))
    else {
        unreachable!("has_google was checked above");
    };
    let tp = token_path(&config.id);
    // If a token file already exists, ensure state reflects that.
    {
        let mut states = AUTH_STATE.lock().unwrap();
        if !states.contains_key(&config.id) && tp.exists() {
            states.insert(config.id.clone(), AuthState::Authorized);
        }
    }

    // Snapshot current state without holding the lock during I/O.
    enum Snap {
        Uninitiated,
        Pending(String),
        Authorized,
        Failed(String),
    }
    let snap = {
        let states = AUTH_STATE.lock().unwrap();
        match states.get(&config.id).unwrap_or(&AuthState::Uninitiated) {
            AuthState::Uninitiated => Snap::Uninitiated,
            AuthState::PendingFlow { url } => Snap::Pending(url.clone()),
            AuthState::Authorized => Snap::Authorized,
            AuthState::Failed(m) => Snap::Failed(m.clone()),
        }
    };

    match snap {
        Snap::Authorized => {
            let date_naive = match chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d") {
                Ok(d) => d,
                Err(_) => return err_result(format!("invalid date: {date}")),
            };

            // Cache hit: return immediately without any network call.
            {
                let caches = EVENT_CACHE.lock().unwrap();
                if let Some(c) = caches.get(&config.id)
                    && date_naive >= c.window_start
                    && date_naive < c.window_end
                {
                    return CalendarFetchResult {
                        status: "ready".into(),
                        events: merged_events_for_date(&c.entries, date_naive),
                        ..Default::default()
                    };
                }
            }

            // Cache miss — fetch a 60-day window and populate the cache.
            do_fetch_events(date, config)
        }

        Snap::Pending(url) => CalendarFetchResult {
            status: "polling".into(),
            auth_url: Some(url),
            auth_code: None,
            ..Default::default()
        },

        Snap::Failed(msg) => {
            // Reset so the next open of the panel retries rather than staying
            // stuck in the failed state permanently.
            {
                AUTH_STATE
                    .lock()
                    .unwrap()
                    .insert(config.id.clone(), AuthState::Uninitiated);
            }
            CalendarFetchResult {
                status: "error".into(),
                error_message: Some(msg),
                ..Default::default()
            }
        }

        Snap::Uninitiated => {
            // Mark as pending (empty URL until the background thread fills it).
            {
                AUTH_STATE.lock().unwrap().insert(
                    config.id.clone(),
                    AuthState::PendingFlow { url: String::new() },
                );
            }

            let (tx, rx) = std::sync::mpsc::channel::<String>();
            let cfg = config.clone();
            let source_id = config.id.clone();
            let tp_clone = tp.clone();
            std::thread::Builder::new()
                .name("alice-calendar-auth".into())
                .spawn(move || run_device_auth(cfg, source_id, tp_clone, tx))
                .ok();

            // Wait up to 15 s for the installed-flow URL (network round-trip).
            // The mutex is NOT held during this wait.
            match rx.recv_timeout(Duration::from_secs(15)) {
                Ok(url) => {
                    {
                        AUTH_STATE.lock().unwrap().insert(
                            config.id.clone(),
                            AuthState::PendingFlow { url: url.clone() },
                        );
                    }
                    CalendarFetchResult {
                        status: "needs_auth".into(),
                        auth_url: Some(url),
                        auth_code: None,
                        ..Default::default()
                    }
                }
                Err(_) => {
                    eprintln!(
                        "[alice/calendar] timed out waiting for present_user_url — check stderr for earlier errors from the auth thread"
                    );
                    let msg = "Timed out waiting for Google authorisation URL".to_string();
                    {
                        AUTH_STATE
                            .lock()
                            .unwrap()
                            .insert(config.id.clone(), AuthState::Failed(msg.clone()));
                    }
                    CalendarFetchResult {
                        status: "error".into(),
                        error_message: Some(msg),
                        ..Default::default()
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Installed-flow auth background thread
// ---------------------------------------------------------------------------

fn run_device_auth(
    config: CalendarEntry,
    source_id: String,
    token_path: PathBuf,
    url_tx: std::sync::mpsc::Sender<String>,
) {
    calendar_runtime().block_on(async move {
        let secret = make_app_secret(&config);
        let delegate = CodeCapture { sender: url_tx };

        if let Some(parent) = token_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let auth = match yup_oauth2::InstalledFlowAuthenticator::builder(
            secret,
            yup_oauth2::InstalledFlowReturnMethod::HTTPPortRedirect(8085),
        )
        .persist_tokens_to_disk(&token_path)
        .flow_delegate(Box::new(delegate))
        .build()
        .await
        {
            Ok(a) => a,
            Err(e) => {
                eprintln!("[alice/calendar] auth build failed: {e}");
                AUTH_STATE.lock().unwrap().insert(
                    source_id.clone(),
                    AuthState::Failed(format!("auth build failed: {e}")),
                );
                return;
            }
        };

        let scopes = ["https://www.googleapis.com/auth/calendar.readonly"];
        match auth.token(&scopes).await {
            Ok(_) => {
                // Store auth before marking Authorized so do_fetch_events
                // always finds a live instance with the token in memory.
                CALENDAR_AUTH
                    .lock()
                    .unwrap()
                    .insert(source_id.clone(), auth);
                AUTH_STATE
                    .lock()
                    .unwrap()
                    .insert(source_id.clone(), AuthState::Authorized);
            }
            Err(e) => {
                eprintln!("[alice/calendar] token request failed: {e}");
                AUTH_STATE
                    .lock()
                    .unwrap()
                    .insert(source_id, AuthState::Failed(format!("auth failed: {e}")));
            }
        }
    });
}

// ---------------------------------------------------------------------------
// FlowDelegate — captures the authorization URL
// ---------------------------------------------------------------------------

struct CodeCapture {
    sender: std::sync::mpsc::Sender<String>,
}

impl yup_oauth2::authenticator_delegate::InstalledFlowDelegate for CodeCapture {
    fn present_user_url<'a>(
        &'a self,
        url: &'a str,
        _need_code: bool,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<String, String>> + Send + 'a>>
    {
        let _ = self.sender.send(url.to_owned());
        Box::pin(std::future::ready(Ok(String::new())))
    }
}

// ---------------------------------------------------------------------------
// NoAuthDelegate — used for the app-restart auth build (token already on disk).
// If the token somehow isn't found, this returns an immediate error rather than
// trying to bind port 8085 and hanging indefinitely.
// ---------------------------------------------------------------------------

#[flutter_rust_bridge::frb(opaque)]
struct NoAuthDelegate;

impl yup_oauth2::authenticator_delegate::InstalledFlowDelegate for NoAuthDelegate {
    fn present_user_url<'a>(
        &'a self,
        _url: &'a str,
        _need_code: bool,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<String, String>> + Send + 'a>>
    {
        Box::pin(std::future::ready(Err(
            "token not in cache; re-authentication required".to_string(),
        )))
    }
}

// ---------------------------------------------------------------------------
// GetToken wrapper — always uses calendar.readonly regardless of requested scope
//
// google-calendar3 requests scopes like ["calendar", "calendarlist.readonly",
// "calendar.readonly"] as alternatives. yup-oauth2 treats them as a combined
// key and finds no cache entry. This wrapper ignores the hub's scope list and
// always retrieves the calendar.readonly token, which Google accepts for all
// read endpoints.
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct CalendarReadonlyAuth(CalendarAuth);

impl google_calendar3::common::GetToken for CalendarReadonlyAuth {
    fn get_token<'a>(
        &'a self,
        _scopes: &'a [&str],
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<
                    Output = Result<Option<String>, Box<dyn std::error::Error + Send + Sync>>,
                > + Send
                + 'a,
        >,
    > {
        Box::pin(async move {
            self.0
                .token(&["https://www.googleapis.com/auth/calendar.readonly"])
                .await
                .map(|t| t.token().map(|s| s.to_owned()))
                .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)
        })
    }
}

// ---------------------------------------------------------------------------
// Build a hub from a cloned auth instance
// ---------------------------------------------------------------------------

fn build_hub(
    auth: CalendarAuth,
) -> google_calendar3::CalendarHub<
    hyper_rustls::HttpsConnector<hyper_util::client::legacy::connect::HttpConnector>,
> {
    let https = hyper_rustls::HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http2()
        .build();
    let client = hyper_util::client::legacy::Client::builder(hyper_util::rt::TokioExecutor::new())
        .build(https);
    google_calendar3::CalendarHub::new(client, CalendarReadonlyAuth(auth))
}

// ---------------------------------------------------------------------------
// Fetch events from the Calendar API — 60-day window
// ---------------------------------------------------------------------------

fn do_fetch_events(date: &str, config: &CalendarEntry) -> CalendarFetchResult {
    let tp = token_path(&config.id);
    let secret = make_app_secret(config);
    let interval_secs = config.poll_interval_secs as u64;
    let date_owned = date.to_owned();

    calendar_runtime().block_on(async move {
        // Reuse the stored Authenticator from the initial flow if available.
        // On app restart (token on disk, no stored auth) build a new one using
        // Interactive + NoAuthDelegate so that if the token is somehow missing
        // we fail cleanly instead of trying to bind port 8085.
        let auth: CalendarAuth = {
            let maybe = CALENDAR_AUTH.lock().unwrap().get(&config.id).cloned();
            match maybe {
                Some(a) => a,
                None => {
                    match yup_oauth2::InstalledFlowAuthenticator::builder(
                        secret,
                        yup_oauth2::InstalledFlowReturnMethod::Interactive,
                    )
                    .persist_tokens_to_disk(&tp)
                    .flow_delegate(Box::new(NoAuthDelegate))
                    .build()
                    .await
                    {
                        Ok(a) => {
                            CALENDAR_AUTH
                                .lock()
                                .unwrap()
                                .insert(config.id.clone(), a.clone());
                            a
                        }
                        Err(e) => return err_result(format!("auth error: {e}")),
                    }
                }
            }
        };

        let hub = build_hub(auth);

        let date_naive = match chrono::NaiveDate::parse_from_str(&date_owned, "%Y-%m-%d") {
            Ok(d) => d,
            Err(_) => return err_result(format!("invalid date: {date_owned}")),
        };

        let window_start = date_naive - chrono::Months::new(3);
        let window_end = date_naive + chrono::Months::new(3) + chrono::Duration::days(1); // exclusive

        use chrono::TimeZone as _;
        let time_min = chrono::Utc.from_utc_datetime(&window_start.and_hms_opt(0, 0, 0).unwrap());
        let time_max = chrono::Utc.from_utc_datetime(&window_end.and_hms_opt(0, 0, 0).unwrap());

        // Fetch calendar list for names + colours.
        let cal_list = match hub.calendar_list().list().doit().await {
            Ok((_, list)) => list,
            Err(e) => return err_result(format!("calendar list failed: {e}")),
        };

        let mut entries: Vec<(chrono::NaiveDate, CalendarEvent)> = Vec::new();
        let mut sync_tokens: HashMap<String, String> = HashMap::new();
        let mut cal_meta: HashMap<String, (String, String)> = HashMap::new();

        for cal in cal_list.items.unwrap_or_default() {
            let cal_id = match &cal.id {
                Some(id) => id.clone(),
                None => continue,
            };
            let cal_name = cal.summary.clone().unwrap_or_default();
            let cal_color = cal.background_color.clone().unwrap_or_default();

            cal_meta.insert(cal_id.clone(), (cal_name.clone(), cal_color.clone()));

            let event_list = match hub
                .events()
                .list(&cal_id)
                .time_min(time_min)
                .time_max(time_max)
                .single_events(true)
                .doit()
                .await
            {
                Ok((_, list)) => list,
                Err(_) => continue, // skip calendars we cannot read
            };

            if let Some(tok) = event_list.next_sync_token.clone() {
                sync_tokens.insert(cal_id.clone(), tok);
            }

            for event in event_list.items.unwrap_or_default() {
                if let Some(mapped_event) =
                    map_event(&event, &cal_name, &cal_color, config.color.as_deref())
                {
                    entries.push(mapped_event);
                }
            }
        }

        // Populate the cache.
        EVENT_CACHE.lock().unwrap().insert(
            config.id.clone(),
            EventCache {
                window_start,
                window_end,
                entries: entries.clone(),
                sync_tokens,
                cal_meta,
            },
        );

        // Cancel only this source's previous poll task and start a fresh one.
        if let Some(handle) = POLL_ABORT.lock().unwrap().remove(&config.id) {
            handle.abort();
        }
        let source_id = config.id.clone();
        let source_color = config.color.clone();
        let join_handle = tokio::task::spawn(run_poll_loop(
            source_id.clone(),
            interval_secs,
            source_color,
        ));
        POLL_ABORT
            .lock()
            .unwrap()
            .insert(source_id, join_handle.abort_handle());

        if let Some(coordinator) = crate::calendar_sources::global_coordinator() {
            coordinator.replace_events(&config.id, entries.clone());
        }

        CalendarFetchResult {
            status: "ready".into(),
            events: merged_events_for_date(&entries, date_naive),
            ..Default::default()
        }
    })
}

// ---------------------------------------------------------------------------
// Incremental sync background task
// ---------------------------------------------------------------------------

async fn run_poll_loop(source_id: String, interval_secs: u64, entry_color: Option<String>) {
    let mut interval = tokio::time::interval(Duration::from_secs(interval_secs));
    loop {
        interval.tick().await;
        if let Err(e) = do_poll_incremental(&source_id, entry_color.as_deref()).await {
            eprintln!("[alice/calendar] incremental poll error: {e}");
        }
    }
}

async fn do_poll_incremental(
    source_id: &str,
    entry_color: Option<&str>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // Clone auth — return early if not yet available.
    let auth = match CALENDAR_AUTH.lock().unwrap().get(source_id).cloned() {
        Some(a) => a,
        None => return Ok(()),
    };

    // Snapshot sync tokens — return early if there is no cache yet.
    let sync_tokens: HashMap<String, String> = {
        let caches = EVENT_CACHE.lock().unwrap();
        match caches.get(source_id) {
            Some(c) if !c.sync_tokens.is_empty() => c.sync_tokens.clone(),
            _ => return Ok(()),
        }
    };

    let hub = build_hub(auth);

    for (cal_id, sync_token) in sync_tokens {
        let result = hub
            .events()
            .list(&cal_id)
            .sync_token(&sync_token)
            .single_events(true)
            .doit()
            .await;

        match result {
            Err(e) => {
                let e_str = e.to_string();
                // 410 Gone means the sync token has expired; clear the cache
                // so that the next fetch_events call triggers a full re-fetch.
                if e_str.contains("410") || e_str.contains("Gone") {
                    EVENT_CACHE.lock().unwrap().remove(source_id);
                    return Ok(());
                }
                eprintln!("[alice/calendar] incremental sync error for {cal_id}: {e}");
            }
            Ok((_, event_list)) => {
                let new_sync_token = event_list.next_sync_token.clone();

                let mut cache_lock = EVENT_CACHE.lock().unwrap();
                if let Some(cache) = cache_lock.get_mut(source_id) {
                    for event in event_list.items.unwrap_or_default() {
                        let event_id = event.id.clone().unwrap_or_default();

                        // Keep removal before cancellation so cancelled events disappear and
                        // cannot reach the mapper below. Exercising this network-bound loop in
                        // a unit test would require coupling tests to the hub and global cache.
                        cache.entries.retain(|(_, e)| e.id != event_id);

                        let is_cancelled = event
                            .status
                            .as_deref()
                            .map(|s| s == "cancelled")
                            .unwrap_or(false);

                        if !is_cancelled {
                            let (cal_name, cal_color) =
                                cache.cal_meta.get(&cal_id).cloned().unwrap_or_default();
                            if let Some(mapped_event) =
                                map_event(&event, &cal_name, &cal_color, entry_color)
                            {
                                cache.entries.push(mapped_event);
                            }
                        }
                    }

                    if let Some(tok) = new_sync_token {
                        cache.sync_tokens.insert(cal_id, tok);
                    }

                    // Re-sort: all-day first, then by start_label.
                    cache
                        .entries
                        .sort_by(|(_, a), (_, b)| match (a.is_all_day, b.is_all_day) {
                            (true, false) => std::cmp::Ordering::Less,
                            (false, true) => std::cmp::Ordering::Greater,
                            _ => a.start_label.cmp(&b.start_label),
                        });
                    if let Some(coordinator) = crate::calendar_sources::global_coordinator() {
                        coordinator.replace_events(source_id, cache.entries.clone());
                    }
                }
            }
        }
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn map_event(
    event: &google_calendar3::api::Event,
    calendar_name: &str,
    remote_calendar_color: &str,
    entry_color: Option<&str>,
) -> Option<(chrono::NaiveDate, CalendarEvent)> {
    let event_date = extract_event_date(event)?;
    let (is_all_day, start_label, end_label) = extract_time_labels(event);

    Some((
        event_date,
        CalendarEvent {
            id: event.id.clone().unwrap_or_default(),
            title: event.summary.clone().unwrap_or_else(|| "(No title)".into()),
            is_all_day,
            start_label,
            end_label,
            calendar_name: calendar_name.to_owned(),
            calendar_color: if remote_calendar_color.is_empty() {
                entry_color.unwrap_or_default().to_owned()
            } else {
                remote_calendar_color.to_owned()
            },
        },
    ))
}

fn make_app_secret(config: &CalendarEntry) -> yup_oauth2::ApplicationSecret {
    let CalendarEntryKind::Google {
        google_client_id,
        google_client_secret,
    } = &config.kind
    else {
        unreachable!("Google auth must only receive Google entries");
    };
    yup_oauth2::ApplicationSecret {
        client_id: google_client_id.clone(),
        client_secret: google_client_secret.clone(),
        token_uri: "https://oauth2.googleapis.com/token".to_string(),
        auth_uri: "https://accounts.google.com/o/oauth2/auth".to_string(),
        redirect_uris: vec!["http://localhost:8085".to_string()],
        project_id: None,
        client_email: None,
        auth_provider_x509_cert_url: None,
        client_x509_cert_url: None,
    }
}

fn err_result(msg: String) -> CalendarFetchResult {
    CalendarFetchResult {
        status: "error".into(),
        error_message: Some(msg),
        ..Default::default()
    }
}

/// Extract the calendar date for an event (all-day or timed).
fn extract_event_date(event: &google_calendar3::api::Event) -> Option<chrono::NaiveDate> {
    let start = event.start.as_ref()?;
    // All-day events have `date` set and `date_time` absent.
    if let Some(date) = start.date {
        return Some(date);
    }
    // Timed events.
    start.date_time.as_ref().map(|dt| dt.date_naive())
}

/// Return a sorted copy of the events in `entries` that fall on `date`.
fn merged_events_for_date(
    entries: &[(chrono::NaiveDate, CalendarEvent)],
    date: chrono::NaiveDate,
) -> Vec<CalendarEvent> {
    crate::calendar_sources::global_coordinator()
        .map(|coordinator| coordinator.events_for_date(date))
        .filter(|events| !events.is_empty())
        .unwrap_or_else(|| filter_for_date(entries, date))
}

fn filter_for_date(
    entries: &[(chrono::NaiveDate, CalendarEvent)],
    date: chrono::NaiveDate,
) -> Vec<CalendarEvent> {
    let mut events: Vec<CalendarEvent> = entries
        .iter()
        .filter(|(d, _)| *d == date)
        .map(|(_, e)| e.clone())
        .collect();

    events.sort_by(|a, b| match (a.is_all_day, b.is_all_day) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => a.start_label.cmp(&b.start_label),
    });

    events
}

fn extract_time_labels(event: &google_calendar3::api::Event) -> (bool, String, String) {
    let start = match event.start.as_ref() {
        Some(s) => s,
        None => return (false, String::new(), String::new()),
    };

    // All-day event: has `date` but not `date_time`.
    if start.date.is_some() && start.date_time.is_none() {
        return (true, String::new(), String::new());
    }

    if let Some(dt) = &start.date_time {
        let start_label = fmt_dt(dt);
        let end_label = event
            .end
            .as_ref()
            .and_then(|e| e.date_time.as_ref())
            .map(fmt_dt)
            .unwrap_or_default();
        return (false, start_label, end_label);
    }

    (false, String::new(), String::new())
}

fn fmt_dt(dt: &chrono::DateTime<chrono::Utc>) -> String {
    use chrono::Timelike as _;
    let local = dt.with_timezone(&chrono::Local);
    format!("{:02}:{:02}", local.hour(), local.minute())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{TimeZone as _, Timelike as _};
    use google_calendar3::api::{Event, EventDateTime};

    fn utc_datetime(
        year: i32,
        month: u32,
        day: u32,
        hour: u32,
        minute: u32,
    ) -> chrono::DateTime<chrono::Utc> {
        chrono::Utc
            .with_ymd_and_hms(year, month, day, hour, minute, 0)
            .single()
            .unwrap()
    }

    fn local_label(datetime: chrono::DateTime<chrono::Utc>) -> String {
        let local = datetime.with_timezone(&chrono::Local);
        format!("{:02}:{:02}", local.hour(), local.minute())
    }

    #[test]
    fn maps_timed_event() {
        let start = utc_datetime(2026, 7, 20, 14, 5);
        let end = utc_datetime(2026, 7, 20, 15, 45);
        let event = Event {
            id: Some("timed-id".into()),
            summary: Some("Timed event".into()),
            start: Some(EventDateTime {
                date_time: Some(start),
                ..Default::default()
            }),
            end: Some(EventDateTime {
                date_time: Some(end),
                ..Default::default()
            }),
            ..Default::default()
        };

        assert_eq!(
            map_event(&event, "Work", "#123456", None),
            Some((
                chrono::NaiveDate::from_ymd_opt(2026, 7, 20).unwrap(),
                CalendarEvent {
                    id: "timed-id".into(),
                    title: "Timed event".into(),
                    is_all_day: false,
                    start_label: local_label(start),
                    end_label: local_label(end),
                    calendar_name: "Work".into(),
                    calendar_color: "#123456".into(),
                },
            ))
        );
    }

    #[test]
    fn maps_all_day_event() {
        let date = chrono::NaiveDate::from_ymd_opt(2026, 7, 21).unwrap();
        let event = Event {
            id: Some("all-day-id".into()),
            summary: Some("All day event".into()),
            start: Some(EventDateTime {
                date: Some(date),
                ..Default::default()
            }),
            ..Default::default()
        };

        assert_eq!(
            map_event(&event, "Personal", "#abcdef", None),
            Some((
                date,
                CalendarEvent {
                    id: "all-day-id".into(),
                    title: "All day event".into(),
                    is_all_day: true,
                    start_label: String::new(),
                    end_label: String::new(),
                    calendar_name: "Personal".into(),
                    calendar_color: "#abcdef".into(),
                },
            ))
        );
    }

    #[test]
    fn uses_entry_color_only_when_remote_color_is_missing() {
        let date = chrono::NaiveDate::from_ymd_opt(2026, 7, 22).unwrap();
        let event = Event {
            start: Some(EventDateTime {
                date: Some(date),
                ..Default::default()
            }),
            ..Default::default()
        };
        assert_eq!(
            map_event(&event, "Work", "", Some("#654321"))
                .unwrap()
                .1
                .calendar_color,
            "#654321"
        );
        assert_eq!(
            map_event(&event, "Work", "#abcdef", Some("#654321"))
                .unwrap()
                .1
                .calendar_color,
            "#abcdef"
        );
    }

    #[test]
    fn uses_missing_title_fallback() {
        let date = chrono::NaiveDate::from_ymd_opt(2026, 7, 22).unwrap();
        let event = Event {
            start: Some(EventDateTime {
                date: Some(date),
                ..Default::default()
            }),
            ..Default::default()
        };

        let (_, mapped_event) = map_event(&event, "", "", None).unwrap();
        assert_eq!(mapped_event.id, "");
        assert_eq!(mapped_event.title, "(No title)");
    }

    #[test]
    fn google_state_and_token_paths_are_scoped_by_entry_id() {
        let work_path = token_path("work");
        let personal_path = token_path("personal");
        assert_ne!(work_path, personal_path);
        assert!(work_path.ends_with("calendar_tokens/work.json"));
        assert!(personal_path.ends_with("calendar_tokens/personal.json"));

        let mut cache = EVENT_CACHE.lock().unwrap();
        cache.clear();
        for id in ["work", "personal"] {
            cache.insert(
                id.into(),
                EventCache {
                    window_start: chrono::NaiveDate::from_ymd_opt(2026, 1, 1).unwrap(),
                    window_end: chrono::NaiveDate::from_ymd_opt(2026, 1, 2).unwrap(),
                    entries: Vec::new(),
                    sync_tokens: HashMap::new(),
                    cal_meta: HashMap::new(),
                },
            );
        }
        assert_eq!(cache.len(), 2);
        assert!(cache.contains_key("work"));
        assert!(cache.contains_key("personal"));
    }

    #[test]
    fn rejects_event_without_start() {
        assert_eq!(map_event(&Event::default(), "Work", "#123456", None), None);
    }
}
