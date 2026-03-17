//! Google Calendar integration.
//!
//! Fetches events for a given date using the Google Calendar API with
//! installed-flow OAuth2 authentication (yup-oauth2 + google-calendar3).
//!
//! Authentication state is held in a process-global `Mutex` so that:
//! - The first call initiates an installed flow and returns the auth URL.
//! - Subsequent calls while polling return the same URL.
//! - Once authorised, calls proceed to the Calendar API.

use std::{path::PathBuf, sync::Mutex, sync::OnceLock, time::Duration};

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
static CALENDAR_AUTH: Mutex<Option<CalendarAuth>> = Mutex::new(None);

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
    config::CalendarConfig,
    state::{CalendarEvent, CalendarFetchResult},
};

// ---------------------------------------------------------------------------
// Global auth state
// ---------------------------------------------------------------------------

enum AuthState {
    Uninitiated,
    PendingFlow { url: String },
    Authorized,
    Failed(String),
}

static AUTH_STATE: Mutex<AuthState> = Mutex::new(AuthState::Uninitiated);

// ---------------------------------------------------------------------------
// Token storage path
// ---------------------------------------------------------------------------

fn token_path() -> PathBuf {
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(p) if !p.is_empty() => PathBuf::from(p),
        _ => {
            let home = std::env::var_os("HOME").unwrap_or_default();
            PathBuf::from(home).join(".config")
        }
    };
    base.join("alice").join("calendar_token.json")
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

pub fn fetch_events(date: &str, config: &CalendarConfig) -> CalendarFetchResult {
    let tp = token_path();

    // If a token file already exists, ensure state reflects that.
    {
        let mut s = AUTH_STATE.lock().unwrap();
        if matches!(&*s, AuthState::Uninitiated) && tp.exists() {
            *s = AuthState::Authorized;
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
        let s = AUTH_STATE.lock().unwrap();
        match &*s {
            AuthState::Uninitiated => Snap::Uninitiated,
            AuthState::PendingFlow { url } => Snap::Pending(url.clone()),
            AuthState::Authorized => Snap::Authorized,
            AuthState::Failed(m) => Snap::Failed(m.clone()),
        }
    };

    match snap {
        Snap::Authorized => do_fetch_events(date, config),

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
                let mut s = AUTH_STATE.lock().unwrap();
                *s = AuthState::Uninitiated;
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
                let mut s = AUTH_STATE.lock().unwrap();
                *s = AuthState::PendingFlow { url: String::new() };
            }

            let (tx, rx) = std::sync::mpsc::channel::<String>();
            let cfg = config.clone();
            let tp_clone = tp.clone();
            std::thread::Builder::new()
                .name("alice-calendar-auth".into())
                .spawn(move || run_device_auth(cfg, tp_clone, tx))
                .ok();

            // Wait up to 15 s for the installed-flow URL (network round-trip).
            // The mutex is NOT held during this wait.
            match rx.recv_timeout(Duration::from_secs(15)) {
                Ok(url) => {
                    {
                        let mut s = AUTH_STATE.lock().unwrap();
                        *s = AuthState::PendingFlow { url: url.clone() };
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
                        let mut s = AUTH_STATE.lock().unwrap();
                        *s = AuthState::Failed(msg.clone());
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
    config: CalendarConfig,
    token_path: PathBuf,
    url_tx: std::sync::mpsc::Sender<String>,
) {
    eprintln!("[alice/calendar] auth thread started");

    calendar_runtime().block_on(async move {
        let secret = make_app_secret(&config);
        let delegate = CodeCapture { sender: url_tx };

        if let Some(parent) = token_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        eprintln!("[alice/calendar] building InstalledFlowAuthenticator…");
        let auth = match yup_oauth2::InstalledFlowAuthenticator::builder(
            secret,
            yup_oauth2::InstalledFlowReturnMethod::HTTPPortRedirect(8085),
        )
        .persist_tokens_to_disk(&token_path)
        .flow_delegate(Box::new(delegate))
        .build()
        .await
        {
            Ok(a) => {
                eprintln!("[alice/calendar] authenticator built OK");
                a
            }
            Err(e) => {
                eprintln!("[alice/calendar] auth build failed: {e}");
                let mut s = AUTH_STATE.lock().unwrap();
                *s = AuthState::Failed(format!("auth build failed: {e}"));
                return;
            }
        };

        eprintln!("[alice/calendar] requesting token (will trigger installed flow)…");
        let scopes = ["https://www.googleapis.com/auth/calendar.readonly"];
        match auth.token(&scopes).await {
            Ok(_) => {
                eprintln!("[alice/calendar] token obtained — authorised");
                // Store auth before marking Authorized so do_fetch_events
                // always finds a live instance with the token in memory.
                *CALENDAR_AUTH.lock().unwrap() = Some(auth);
                let mut s = AUTH_STATE.lock().unwrap();
                *s = AuthState::Authorized;
            }
            Err(e) => {
                eprintln!("[alice/calendar] token request failed: {e}");
                let mut s = AUTH_STATE.lock().unwrap();
                *s = AuthState::Failed(format!("auth failed: {e}"));
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
        eprintln!("[alice/calendar] present_user_url called — url={url}");
        let _ = self.sender.send(url.to_owned());
        Box::pin(std::future::ready(Ok(String::new())))
    }
}

// ---------------------------------------------------------------------------
// NoAuthDelegate — used for the app-restart auth build (token already on disk).
// If the token somehow isn't found, this returns an immediate error rather than
// trying to bind port 8085 and hanging indefinitely.
// ---------------------------------------------------------------------------

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
                    Output = Result<
                        Option<String>,
                        Box<dyn std::error::Error + Send + Sync>,
                    >,
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
// Fetch events from the Calendar API (happy path)
// ---------------------------------------------------------------------------

fn do_fetch_events(date: &str, config: &CalendarConfig) -> CalendarFetchResult {
    let tp = token_path();
    // Pre-compute secret outside the async block; only used in the restart path.
    let secret = make_app_secret(config);

    calendar_runtime().block_on(async move {
        // Reuse the stored Authenticator from the initial flow if available.
        // On app restart (token on disk, no stored auth) build a new one using
        // Interactive + NoAuthDelegate so that if the token is somehow missing
        // we fail cleanly instead of trying to bind port 8085.
        let auth: CalendarAuth = {
            let maybe = CALENDAR_AUTH.lock().unwrap().clone();
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
                            *CALENDAR_AUTH.lock().unwrap() = Some(a.clone());
                            a
                        }
                        Err(e) => return err_result(format!("auth error: {e}")),
                    }
                }
            }
        };

        let https = hyper_rustls::HttpsConnectorBuilder::new()
            .with_webpki_roots()
            .https_or_http()
            .enable_http2()
            .build();

        let client =
            hyper_util::client::legacy::Client::builder(hyper_util::rt::TokioExecutor::new())
                .build(https);

        let hub = google_calendar3::CalendarHub::new(client, CalendarReadonlyAuth(auth));

        let date_naive = match chrono::NaiveDate::parse_from_str(date, "%Y-%m-%d") {
            Ok(d) => d,
            Err(_) => return err_result(format!("invalid date: {date}")),
        };

        use chrono::TimeZone as _;
        let time_min = chrono::Utc.from_utc_datetime(&date_naive.and_hms_opt(0, 0, 0).unwrap());
        let next = date_naive.succ_opt().unwrap_or(date_naive);
        let time_max = chrono::Utc.from_utc_datetime(&next.and_hms_opt(0, 0, 0).unwrap());

        // Fetch calendar list for names + colours.
        let cal_list = match hub.calendar_list().list().doit().await {
            Ok((_, list)) => list,
            Err(e) => return err_result(format!("calendar list failed: {e}")),
        };

        let mut all_events: Vec<CalendarEvent> = Vec::new();

        for cal in cal_list.items.unwrap_or_default() {
            let cal_id = match &cal.id {
                Some(id) => id.clone(),
                None => continue,
            };
            let cal_name = cal.summary.clone().unwrap_or_default();
            let cal_color = cal.background_color.clone().unwrap_or_default();

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

            for event in event_list.items.unwrap_or_default() {
                let id = event.id.clone().unwrap_or_default();
                let title = event.summary.clone().unwrap_or_else(|| "(No title)".into());
                let (is_all_day, start_label, end_label) = extract_time_labels(&event);

                all_events.push(CalendarEvent {
                    id,
                    title,
                    is_all_day,
                    start_label,
                    end_label,
                    calendar_name: cal_name.clone(),
                    calendar_color: cal_color.clone(),
                });
            }
        }

        // All-day first, then timed events sorted by start label.
        all_events.sort_by(|a, b| match (a.is_all_day, b.is_all_day) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => a.start_label.cmp(&b.start_label),
        });

        CalendarFetchResult {
            status: "ready".into(),
            events: all_events,
            ..Default::default()
        }
    })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_app_secret(config: &CalendarConfig) -> yup_oauth2::ApplicationSecret {
    yup_oauth2::ApplicationSecret {
        client_id: config.google_client_id.clone(),
        client_secret: config.google_client_secret.clone(),
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
