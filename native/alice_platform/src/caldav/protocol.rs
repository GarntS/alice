use std::collections::{BTreeMap, BTreeSet};

use chrono::{Local, Months};
use quick_xml::{Reader, events::Event};
use reqwest::{Method, StatusCode, header};
use url::Url;

use super::{
    CalDavCollection, EventWindow, LosslessCalDavResource, canonicalize_href,
    client::{CalDavClient, CalDavClientError, validate_safe_xml},
    collection_url_key,
    ical::{parse_caldav_resource, patch_vtodo_completion},
};

const DISCOVER_PRINCIPAL_BODY: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:current-user-principal/><c:calendar-home-set/></d:prop>
</d:propfind>"#;
const DISCOVER_HOME_BODY: &str = r#"<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:displayname/><d:resourcetype/><c:supported-calendar-component-set/>
    <d:supported-report-set/><d:sync-token/>
  </d:prop>
</d:propfind>"#;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveryResult {
    pub principal_url: Url,
    pub calendar_home_url: Url,
    pub collections: Vec<CalDavCollection>,
    pub errors: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectionSyncResult {
    pub collection: CalDavCollection,
    pub resources: BTreeMap<String, LosslessCalDavResource>,
    pub removed_hrefs: Vec<String>,
    pub event_window: Option<EventWindow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InitialSyncBatch {
    pub successful: Vec<CollectionSyncResult>,
    pub errors: Vec<String>,
}

impl CalDavClient {
    /// Discover the current principal, calendar home, and strictly allowlisted
    /// readable collection metadata.
    pub async fn discover(&self) -> Result<DiscoveryResult, CalDavClientError> {
        let configured_principal = self.principal_url().clone();
        let initial = self
            .propfind(&configured_principal, "0", DISCOVER_PRINCIPAL_BODY)
            .await?;
        let initial_responses = parse_multistatus(&initial)?;
        let principal_url = initial_responses
            .iter()
            .find_map(|response| response.current_user_principal.as_deref())
            .map(|href| canonicalize_protocol_href(&configured_principal, href))
            .transpose()?
            .unwrap_or(configured_principal.clone());
        let mut calendar_home = initial_responses
            .iter()
            .find_map(|response| response.calendar_home.as_deref())
            .map(|href| canonicalize_protocol_href(&configured_principal, href))
            .transpose()?;

        if calendar_home.is_none() || principal_url != configured_principal {
            let principal = self
                .propfind(&principal_url, "0", DISCOVER_PRINCIPAL_BODY)
                .await?;
            calendar_home = parse_multistatus(&principal)?
                .iter()
                .find_map(|response| response.calendar_home.as_deref())
                .map(|href| canonicalize_protocol_href(&principal_url, href))
                .transpose()?;
        }
        let calendar_home_url = calendar_home.ok_or_else(|| {
            CalDavClientError::new("CalDAV discovery did not return a calendar home")
        })?;

        let home = self
            .propfind(&calendar_home_url, "1", DISCOVER_HOME_BODY)
            .await?;
        let responses = parse_multistatus(&home)?;
        let allowlist = self
            .allowed_collection_urls()
            .iter()
            .map(|url| (collection_url_key(url), url.clone()))
            .collect::<BTreeMap<_, _>>();
        let mut found = BTreeSet::new();
        let mut collections = Vec::new();
        for response in responses {
            if !response.is_calendar {
                continue;
            }
            let Some(href) = response.href else {
                continue;
            };
            let href = canonicalize_protocol_href(&calendar_home_url, &href)?;
            let key = collection_url_key(&href);
            if !allowlist.contains_key(&key) {
                continue;
            }
            found.insert(key);
            collections.push(CalDavCollection {
                display_name: response
                    .display_name
                    .filter(|name| !name.trim().is_empty())
                    .unwrap_or_else(|| collection_name_fallback(&href)),
                href,
                supports_vtodo: response.components.contains("VTODO"),
                supports_vevent: response.components.contains("VEVENT"),
                supports_sync_collection: response.supports_sync_collection,
                sync_token: response.sync_token,
            });
        }
        collections.sort_by(|left, right| left.href.as_str().cmp(right.href.as_str()));

        let calendar_home_key = collection_url_key(&calendar_home_url);
        let errors = allowlist
            .iter()
            .filter(|(key, _)| !found.contains(*key))
            .map(|(key, href)| {
                if key.as_str() == calendar_home_key.as_str() {
                    format!(
                        "Configured CalDAV href is the calendar home, not a task collection: {href}"
                    )
                } else {
                    format!("Configured CalDAV collection is unavailable: {href}")
                }
            })
            .collect();
        Ok(DiscoveryResult {
            principal_url,
            calendar_home_url,
            collections,
            errors,
        })
    }

    /// Fully synchronize each collection independently so one failure does not
    /// discard successful collection data.
    pub async fn initial_sync(
        &self,
        collections: &[CalDavCollection],
        existing_hrefs: &BTreeMap<String, BTreeSet<String>>,
    ) -> InitialSyncBatch {
        let mut batch = InitialSyncBatch {
            successful: Vec::new(),
            errors: Vec::new(),
        };
        for collection in collections {
            let existing = existing_hrefs
                .get(collection.href.as_str())
                .cloned()
                .unwrap_or_default();
            match self.full_sync_collection(collection, existing).await {
                Ok(result) => batch.successful.push(result),
                Err(error) => batch.errors.push(format!(
                    "CalDAV collection {} failed: {}",
                    collection.display_name,
                    self.redact(error.message())
                )),
            }
        }
        batch
    }

    /// Apply RFC 6578 changes when a token is available, otherwise fall back
    /// to authoritative bounded synchronization for this collection only.
    pub async fn synchronize_collection(
        &self,
        collection: &CalDavCollection,
        existing: &BTreeMap<String, LosslessCalDavResource>,
    ) -> Result<CollectionSyncResult, CalDavClientError> {
        if !collection.supports_sync_collection || collection.sync_token.is_none() {
            return self
                .full_sync_collection(collection, existing.keys().cloned().collect())
                .await;
        }
        let token = collection.sync_token.as_deref().unwrap_or_default();
        let body = sync_collection_body(token);
        let method = Method::from_bytes(b"REPORT")
            .map_err(|_| CalDavClientError::new("failed to construct REPORT request"))?;
        let request = self
            .request(method, collection.href.clone())?
            .header("Depth", "1")
            .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
            .body(body);
        let response = self.send(request).await?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(|error| {
            CalDavClientError::new(self.redact(&format!("failed to read CalDAV response: {error}")))
        })?;
        if status == StatusCode::FORBIDDEN || status == StatusCode::CONFLICT {
            let mut reset = collection.clone();
            reset.sync_token = None;
            return self
                .full_sync_collection(&reset, existing.keys().cloned().collect())
                .await;
        }
        if status != StatusCode::MULTI_STATUS && !status.is_success() {
            return Err(CalDavClientError::new(format!(
                "CalDAV sync-collection failed with HTTP {}",
                status.as_u16()
            )));
        }
        validate_safe_xml(&bytes)?;

        let mut resources = existing.clone();
        let mut removed_hrefs = Vec::new();
        for response in parse_multistatus(&bytes)? {
            let Some(href) = response.href else { continue };
            let href = canonicalize_collection_child_href(&collection.href, &href)?;
            let href_string = href.to_string();
            if response
                .status
                .as_deref()
                .is_some_and(|status| status.contains(" 404 ") || status.ends_with(" 404"))
            {
                if resources.remove(&href_string).is_some() {
                    removed_hrefs.push(href_string);
                }
                continue;
            }
            if let Some(calendar_data) = response.calendar_data
                && let Some(resource) = parse_caldav_resource(
                    &calendar_data,
                    &collection.href,
                    &href,
                    &collection.display_name,
                    response.etag,
                )
                .map_err(|error| CalDavClientError::new(error.to_string()))?
            {
                resources.insert(href_string, resource);
            }
        }
        let mut updated = collection.clone();
        updated.sync_token =
            find_last_element_text(&bytes, "sync-token").or_else(|| collection.sync_token.clone());
        Ok(CollectionSyncResult {
            collection: updated,
            resources,
            removed_hrefs,
            event_window: None,
        })
    }

    /// Patch and PUT one task with If-Match. A single 412 response refetches
    /// and repatches the authoritative resource before retrying once.
    pub async fn mutate_task_completion(
        &self,
        resource: &LosslessCalDavResource,
        completed: bool,
        completed_at: chrono::DateTime<chrono::Utc>,
        collection_name: &str,
    ) -> Result<LosslessCalDavResource, CalDavClientError> {
        let url =
            canonicalize_protocol_href(self.principal_url(), &resource.identity.resource_href)?;
        let mut latest = resource.clone();
        for attempt in 0..2 {
            let etag = latest
                .etag
                .as_deref()
                .ok_or_else(|| CalDavClientError::new("CalDAV task has no ETag"))?;
            let patched = patch_vtodo_completion(&latest.icalendar, completed, completed_at)
                .map_err(|error| CalDavClientError::new(error.to_string()))?;
            let request = self
                .request(Method::PUT, url.clone())?
                .header(header::IF_MATCH, etag)
                .header(header::CONTENT_TYPE, "text/calendar; charset=utf-8")
                .body(patched);
            let response = self.send(request).await?;
            if response.status() == StatusCode::PRECONDITION_FAILED {
                if attempt == 0 {
                    latest = self
                        .get_resource(&url, &resource.identity.collection_href, collection_name)
                        .await?;
                    continue;
                }
                return Err(CalDavClientError::new(
                    "CalDAV task changed concurrently after one retry",
                ));
            }
            if !response.status().is_success() {
                return Err(CalDavClientError::new(format!(
                    "CalDAV task PUT failed with HTTP {}",
                    response.status().as_u16()
                )));
            }

            let response_etag = response
                .headers()
                .get(header::ETAG)
                .and_then(|value| value.to_str().ok())
                .map(str::to_string);
            let body = response.bytes().await.map_err(|error| {
                CalDavClientError::new(
                    self.redact(&format!("failed to read CalDAV response: {error}")),
                )
            })?;
            if !body.is_empty() {
                return parse_caldav_resource(
                    std::str::from_utf8(&body)
                        .map_err(|_| CalDavClientError::new("invalid CalDAV task response"))?,
                    &Url::parse(&resource.identity.collection_href)
                        .map_err(|_| CalDavClientError::new("invalid task collection identity"))?,
                    &url,
                    collection_name,
                    response_etag,
                )
                .map_err(|error| CalDavClientError::new(error.to_string()))?
                .ok_or_else(|| CalDavClientError::new("CalDAV task response contains no VTODO"));
            }
            return self
                .get_resource(&url, &resource.identity.collection_href, collection_name)
                .await;
        }
        unreachable!("completion mutation loop returns on success or second failure")
    }

    async fn get_resource(
        &self,
        url: &Url,
        collection_href: &str,
        collection_name: &str,
    ) -> Result<LosslessCalDavResource, CalDavClientError> {
        let response = self.send(self.request(Method::GET, url.clone())?).await?;
        if !response.status().is_success() {
            return Err(CalDavClientError::new(format!(
                "CalDAV task GET failed with HTTP {}",
                response.status().as_u16()
            )));
        }
        let etag = response
            .headers()
            .get(header::ETAG)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let body = response.bytes().await.map_err(|error| {
            CalDavClientError::new(self.redact(&format!("failed to read CalDAV response: {error}")))
        })?;
        let source = std::str::from_utf8(&body)
            .map_err(|_| CalDavClientError::new("invalid CalDAV task response"))?;
        parse_caldav_resource(
            source,
            &Url::parse(collection_href)
                .map_err(|_| CalDavClientError::new("invalid task collection identity"))?,
            url,
            collection_name,
            etag,
        )
        .map_err(|error| CalDavClientError::new(error.to_string()))?
        .ok_or_else(|| CalDavClientError::new("CalDAV task response contains no VTODO"))
    }

    async fn full_sync_collection(
        &self,
        collection: &CalDavCollection,
        existing_hrefs: BTreeSet<String>,
    ) -> Result<CollectionSyncResult, CalDavClientError> {
        let today = Local::now().date_naive();
        let event_start = today.checked_sub_months(Months::new(3)).unwrap_or(today);
        let event_end = today.checked_add_months(Months::new(3)).unwrap_or(today);
        let event_window = collection
            .supports_vevent
            .then(|| event_window_for_date(today));
        let mut resources = BTreeMap::new();
        if collection.supports_vtodo {
            self.apply_calendar_query(
                collection,
                &calendar_query_body("VTODO", None),
                &mut resources,
            )
            .await?;
        }
        if collection.supports_vevent {
            let range = format!(
                "{}T000000Z/{}T235959Z",
                event_start.format("%Y%m%d"),
                event_end.format("%Y%m%d")
            );
            self.apply_calendar_query(
                collection,
                &calendar_query_body("VEVENT", Some(&range)),
                &mut resources,
            )
            .await?;
        }
        let fetched = resources.keys().cloned().collect::<BTreeSet<_>>();
        let removed_hrefs = existing_hrefs.difference(&fetched).cloned().collect();
        Ok(CollectionSyncResult {
            collection: collection.clone(),
            resources,
            removed_hrefs,
            event_window,
        })
    }

    async fn apply_calendar_query(
        &self,
        collection: &CalDavCollection,
        body: &str,
        resources: &mut BTreeMap<String, LosslessCalDavResource>,
    ) -> Result<(), CalDavClientError> {
        for response in parse_multistatus(&self.report(&collection.href, body).await?)? {
            let (Some(href), Some(calendar_data)) = (response.href, response.calendar_data) else {
                continue;
            };
            let href = canonicalize_collection_child_href(&collection.href, &href)?;
            if let Some(resource) = parse_caldav_resource(
                &calendar_data,
                &collection.href,
                &href,
                &collection.display_name,
                response.etag,
            )
            .map_err(|error| CalDavClientError::new(error.to_string()))?
            {
                resources.insert(href.to_string(), resource);
            }
        }
        Ok(())
    }

    async fn report(&self, url: &Url, body: &str) -> Result<Vec<u8>, CalDavClientError> {
        let method = Method::from_bytes(b"REPORT")
            .map_err(|_| CalDavClientError::new("failed to construct REPORT request"))?;
        let request = self
            .request(method, url.clone())?
            .header("Depth", "1")
            .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
            .body(body.to_string());
        let response = self.send(request).await?;
        self.read_xml_response(response, "REPORT").await
    }

    async fn propfind(
        &self,
        url: &Url,
        depth: &'static str,
        body: &'static str,
    ) -> Result<Vec<u8>, CalDavClientError> {
        let method = Method::from_bytes(b"PROPFIND")
            .map_err(|_| CalDavClientError::new("failed to construct PROPFIND request"))?;
        let request = self
            .request(method, url.clone())?
            .header("Depth", depth)
            .header(header::CONTENT_TYPE, "application/xml; charset=utf-8")
            .body(body);
        let response = self.send(request).await?;
        self.read_xml_response(response, "PROPFIND").await
    }

    async fn read_xml_response(
        &self,
        response: reqwest::Response,
        operation: &str,
    ) -> Result<Vec<u8>, CalDavClientError> {
        let status = response.status();
        if status != StatusCode::MULTI_STATUS && !status.is_success() {
            return Err(CalDavClientError::new(format!(
                "CalDAV {operation} failed with HTTP {}",
                status.as_u16()
            )));
        }
        if response
            .content_length()
            .is_some_and(|length| length > 8 * 1024 * 1024)
        {
            return Err(CalDavClientError::new("CalDAV XML response is too large"));
        }
        let bytes = response.bytes().await.map_err(|error| {
            CalDavClientError::new(self.redact(&format!("failed to read CalDAV response: {error}")))
        })?;
        validate_safe_xml(&bytes)?;
        Ok(bytes.to_vec())
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct DavResponse {
    href: Option<String>,
    etag: Option<String>,
    calendar_data: Option<String>,
    status: Option<String>,
    display_name: Option<String>,
    current_user_principal: Option<String>,
    calendar_home: Option<String>,
    components: BTreeSet<String>,
    is_calendar: bool,
    supports_sync_collection: bool,
    sync_token: Option<String>,
}

fn parse_multistatus(bytes: &[u8]) -> Result<Vec<DavResponse>, CalDavClientError> {
    validate_safe_xml(bytes)?;
    let mut reader = Reader::from_reader(bytes);
    reader.config_mut().check_comments = true;
    let mut stack: Vec<String> = Vec::new();
    let mut responses = Vec::new();
    let mut current: Option<DavResponse> = None;
    let mut text = String::new();

    loop {
        match reader.read_event() {
            Ok(Event::Start(start)) => {
                let name =
                    String::from_utf8_lossy(start.local_name().as_ref()).to_ascii_lowercase();
                if name == "response" {
                    current = Some(DavResponse::default());
                }
                apply_capability_element(&reader, &start, &name, current.as_mut())?;
                stack.push(name);
                text.clear();
            }
            Ok(Event::Empty(empty)) => {
                let name =
                    String::from_utf8_lossy(empty.local_name().as_ref()).to_ascii_lowercase();
                apply_capability_element(&reader, &empty, &name, current.as_mut())?;
            }
            Ok(Event::Text(value)) => {
                let decoded = value
                    .decode()
                    .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?;
                let decoded = quick_xml::escape::unescape(&decoded)
                    .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?;
                text.push_str(&decoded);
            }
            Ok(Event::GeneralRef(value)) => {
                let name = value
                    .decode()
                    .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?;
                let reference = format!("&{name};");
                text.push_str(
                    &quick_xml::escape::unescape(&reference)
                        .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?,
                );
            }
            Ok(Event::CData(value)) => {
                text.push_str(
                    &value
                        .decode()
                        .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?,
                );
            }
            Ok(Event::End(end)) => {
                let name = String::from_utf8_lossy(end.local_name().as_ref()).to_ascii_lowercase();
                if let Some(response) = current.as_mut() {
                    let value = text.trim().to_string();
                    match name.as_str() {
                        "href" => match stack.iter().rev().nth(1).map(String::as_str) {
                            Some("current-user-principal") => {
                                response.current_user_principal = Some(value)
                            }
                            Some("calendar-home-set") => response.calendar_home = Some(value),
                            _ if response.href.is_none() => response.href = Some(value),
                            _ => {}
                        },
                        "displayname" => response.display_name = Some(value),
                        "getetag" if !value.is_empty() => response.etag = Some(value),
                        "calendar-data" => response.calendar_data = Some(value),
                        "status" if !value.is_empty() => response.status = Some(value),
                        "sync-token" if !value.is_empty() => response.sync_token = Some(value),
                        _ => {}
                    }
                }
                if name == "response"
                    && let Some(response) = current.take()
                {
                    responses.push(response);
                }
                stack.pop();
                text.clear();
            }
            Ok(Event::DocType(_)) => {
                return Err(CalDavClientError::new(
                    "CalDAV XML response contains a forbidden DTD",
                ));
            }
            Ok(Event::Eof) => return Ok(responses),
            Ok(_) => {}
            Err(_) => return Err(CalDavClientError::new("invalid CalDAV XML response")),
        }
    }
}

fn apply_capability_element(
    reader: &Reader<&[u8]>,
    element: &quick_xml::events::BytesStart<'_>,
    name: &str,
    response: Option<&mut DavResponse>,
) -> Result<(), CalDavClientError> {
    let Some(response) = response else {
        return Ok(());
    };
    match name {
        "calendar" => response.is_calendar = true,
        "sync-collection" => response.supports_sync_collection = true,
        "comp" => {
            for attribute in element.attributes() {
                let attribute =
                    attribute.map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?;
                if attribute
                    .key
                    .local_name()
                    .as_ref()
                    .eq_ignore_ascii_case(b"name")
                {
                    let value = attribute
                        .decode_and_unescape_value(reader.decoder())
                        .map_err(|_| CalDavClientError::new("invalid CalDAV XML response"))?;
                    response.components.insert(value.to_ascii_uppercase());
                }
            }
        }
        _ => {}
    }
    Ok(())
}

pub fn event_window_for_date(today: chrono::NaiveDate) -> EventWindow {
    let start = today.checked_sub_months(Months::new(3)).unwrap_or(today);
    let end = today.checked_add_months(Months::new(3)).unwrap_or(today);
    EventWindow {
        start_date: start.format("%Y-%m-%d").to_string(),
        end_date: end.format("%Y-%m-%d").to_string(),
    }
}

pub fn event_window_needs_reconciliation(
    cached: Option<&EventWindow>,
    today: chrono::NaiveDate,
) -> bool {
    cached != Some(&event_window_for_date(today))
}

fn canonicalize_protocol_href(request_url: &Url, href: &str) -> Result<Url, String> {
    canonicalize_href(request_url, href)
}

fn canonicalize_collection_child_href(collection: &Url, href: &str) -> Result<Url, String> {
    let mut base = collection.clone();
    if !base.path().ends_with('/') {
        let path = format!("{}/", base.path());
        base.set_path(&path);
    }
    canonicalize_protocol_href(&base, href)
}

fn sync_collection_body(token: &str) -> String {
    format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:sync-token>{}</d:sync-token><d:sync-level>1</d:sync-level>
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
</d:sync-collection>"#,
        quick_xml::escape::escape(token)
    )
}

fn find_last_element_text(bytes: &[u8], target: &str) -> Option<String> {
    let mut reader = Reader::from_reader(bytes);
    let mut active = false;
    let mut value = String::new();
    let mut result = None;
    loop {
        match reader.read_event().ok()? {
            Event::Start(start) => {
                active = start
                    .local_name()
                    .as_ref()
                    .eq_ignore_ascii_case(target.as_bytes());
                if active {
                    value.clear();
                }
            }
            Event::Text(text) if active => value.push_str(&text.decode().ok()?),
            Event::End(end)
                if active
                    && end
                        .local_name()
                        .as_ref()
                        .eq_ignore_ascii_case(target.as_bytes()) =>
            {
                result = Some(value.trim().to_string());
                active = false;
            }
            Event::Eof => return result.filter(|value| !value.is_empty()),
            _ => {}
        }
    }
}

fn calendar_query_body(component: &str, range: Option<&str>) -> String {
    let time_range = range
        .map(|range| {
            let (start, end) = range.split_once('/').unwrap_or((range, range));
            format!(r#"<c:time-range start="{start}" end="{end}"/>"#)
        })
        .unwrap_or_default();
    format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="{component}">{time_range}</c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>"#
    )
}

fn collection_name_fallback(url: &Url) -> String {
    url.path_segments()
        .and_then(|mut segments| segments.rfind(|segment| !segment.is_empty()))
        .filter(|segment| !segment.is_empty())
        .unwrap_or("CalDAV")
        .to_string()
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    use super::*;
    use chrono::TimeZone;
    use wiremock::{Mock, MockServer, ResponseTemplate, matchers::*};

    const DISCOVERY_XML: &[u8] = br#"<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:response>
    <d:href>/dav/principals/alice/</d:href>
    <d:propstat><d:prop>
      <d:current-user-principal><d:href>/dav/principals/alice/</d:href></d:current-user-principal>
      <c:calendar-home-set><d:href>/dav/calendars/alice/</d:href></c:calendar-home-set>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/calendars/alice/work/</d:href>
    <d:propstat><d:prop>
      <d:displayname>Work &amp; Tasks</d:displayname>
      <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
      <c:supported-calendar-component-set><c:comp name="VTODO"/><c:comp name="VEVENT"/></c:supported-calendar-component-set>
      <d:supported-report-set><d:supported-report><d:report><d:sync-collection/></d:report></d:supported-report></d:supported-report-set>
      <d:sync-token>https://example.test/sync/1</d:sync-token>
    </d:prop></d:propstat>
  </d:response>
</d:multistatus>"#;

    #[test]
    fn parses_principal_home_collection_metadata_and_capabilities() {
        let responses = parse_multistatus(DISCOVERY_XML).unwrap();
        assert_eq!(responses.len(), 2);
        assert_eq!(
            responses[0].current_user_principal.as_deref(),
            Some("/dav/principals/alice/")
        );
        assert_eq!(
            responses[0].calendar_home.as_deref(),
            Some("/dav/calendars/alice/")
        );
        let collection = &responses[1];
        assert_eq!(
            collection.href.as_deref(),
            Some("/dav/calendars/alice/work/")
        );
        assert_eq!(collection.display_name.as_deref(), Some("Work & Tasks"));
        assert!(collection.is_calendar);
        assert!(collection.components.contains("VTODO"));
        assert!(collection.components.contains("VEVENT"));
        assert!(collection.supports_sync_collection);
        assert_eq!(
            collection.sync_token.as_deref(),
            Some("https://example.test/sync/1")
        );
    }

    #[test]
    fn parses_calendar_data_etag_and_builds_bounded_event_query() {
        let xml = br#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/tasks/1.ics</d:href><d:propstat><d:prop><d:getetag>&quot;one&quot;</d:getetag><c:calendar-data><![CDATA[BEGIN:VCALENDAR
BEGIN:VTODO
UID:1
END:VTODO
END:VCALENDAR
]]></c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>"#;
        let response = parse_multistatus(xml).unwrap().remove(0);
        assert_eq!(response.etag.as_deref(), Some("\"one\""));
        assert!(response.calendar_data.unwrap().contains("BEGIN:VTODO"));

        let query = calendar_query_body("VEVENT", Some("20260401T000000Z/20261001T235959Z"));
        assert!(query.contains("name=\"VEVENT\""));
        assert!(query.contains("start=\"20260401T000000Z\""));
        assert!(query.contains("end=\"20261001T235959Z\""));
    }

    #[test]
    fn parses_incremental_deletion_status_and_replacement_token() {
        let xml = br#"<d:multistatus xmlns:d="DAV:"><d:response><d:href>/tasks/deleted.ics</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response><d:sync-token>next-token</d:sync-token></d:multistatus>"#;
        let response = parse_multistatus(xml).unwrap().remove(0);
        assert_eq!(response.status.as_deref(), Some("HTTP/1.1 404 Not Found"));
        assert_eq!(
            find_last_element_text(xml, "sync-token").as_deref(),
            Some("next-token")
        );
        let body = sync_collection_body("token&one");
        assert!(body.contains("token&amp;one"));
        assert!(body.contains("calendar-data"));
    }

    #[test]
    fn event_window_reconciles_when_local_date_changes() {
        let first = chrono::NaiveDate::from_ymd_opt(2026, 7, 20).unwrap();
        let next = chrono::NaiveDate::from_ymd_opt(2026, 7, 21).unwrap();
        let window = event_window_for_date(first);
        assert_eq!(window.start_date, "2026-04-20");
        assert_eq!(window.end_date, "2026-10-20");
        assert!(!event_window_needs_reconciliation(Some(&window), first));
        assert!(event_window_needs_reconciliation(Some(&window), next));
        assert!(event_window_needs_reconciliation(None, first));
    }

    #[tokio::test]
    async fn mock_vikunja_projects_cover_discovery_sync_and_etag_retry() {
        let server = MockServer::start().await;
        let principal = Url::parse(&format!("{}/dav/principals/alice/", server.uri())).unwrap();
        // Vikunja documents a trailing slash, but advertises project hrefs
        // without one. Both forms must identify the same allowlist entry.
        let collection_url = Url::parse(&format!("{}/dav/projects/36/", server.uri())).unwrap();
        let config = crate::config::ValidatedCalDavConfig::for_test(
            principal.clone(),
            "alice",
            "token",
            vec![collection_url.clone()],
        );
        let client = CalDavClient::new_for_test(config).unwrap();

        Mock::given(method("PROPFIND"))
            .and(path("/dav/principals/alice/"))
            .and(header("authorization", "Basic YWxpY2U6dG9rZW4="))
            .respond_with(ResponseTemplate::new(207).set_body_string(
                r#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/dav/principals/alice/</d:href><d:propstat><d:prop><d:current-user-principal><d:href>/dav/principals/alice/</d:href></d:current-user-principal><c:calendar-home-set><d:href>/dav/projects/</d:href></c:calendar-home-set></d:prop></d:propstat></d:response></d:multistatus>"#,
            ))
            .mount(&server)
            .await;
        Mock::given(method("PROPFIND"))
            .and(path("/dav/projects/"))
            .and(header("authorization", "Basic YWxpY2U6dG9rZW4="))
            .respond_with(ResponseTemplate::new(207).set_body_string(
                r#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/dav/projects/36</d:href><d:propstat><d:prop><d:displayname>Work</d:displayname><d:resourcetype><d:collection/><c:calendar/></d:resourcetype><c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set><d:supported-report-set><d:supported-report><d:report><d:sync-collection/></d:report></d:supported-report></d:supported-report-set><d:sync-token>token-one</d:sync-token></d:prop></d:propstat></d:response><d:response><d:href>/dav/projects/38</d:href><d:propstat><d:prop><d:displayname>Private</d:displayname><d:resourcetype><d:collection/><c:calendar/></d:resourcetype><c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop></d:propstat></d:response></d:multistatus>"#,
            ))
            .mount(&server)
            .await;

        let task_source = "BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:one\r\nSUMMARY:One\r\nSTATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
        let report_xml = format!(
            r#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/dav/projects/36/one.ics</d:href><d:propstat><d:prop><d:getetag>&quot;one&quot;</d:getetag><c:calendar-data><![CDATA[{task_source}]]></c:calendar-data></d:prop></d:propstat></d:response></d:multistatus>"#
        );
        Mock::given(method("REPORT"))
            .and(path("/dav/projects/36"))
            .and(body_string_contains("calendar-query"))
            .and(header("authorization", "Basic YWxpY2U6dG9rZW4="))
            .respond_with(ResponseTemplate::new(207).set_body_string(report_xml))
            .mount(&server)
            .await;
        Mock::given(method("REPORT"))
            .and(path("/dav/projects/36"))
            .and(body_string_contains("sync-collection"))
            .respond_with(
                ResponseTemplate::new(403)
                    .set_body_string(r#"<d:error xmlns:d="DAV:"><d:valid-sync-token/></d:error>"#),
            )
            .mount(&server)
            .await;

        let discovery = client.discover().await.unwrap();
        assert_eq!(
            discovery.collections.len(),
            1,
            "unallowlisted collection rejected"
        );
        let collection = &discovery.collections[0];
        assert_eq!(collection.href.path(), "/dav/projects/36");
        assert!(discovery.errors.is_empty());
        let existing = BTreeMap::from([(
            collection.href.to_string(),
            BTreeSet::from([format!("{}/deleted.ics", collection.href)]),
        )]);
        let initial = client.initial_sync(&discovery.collections, &existing).await;
        assert!(initial.errors.is_empty());
        assert_eq!(initial.successful[0].removed_hrefs.len(), 1);

        let mut broken = collection.clone();
        broken.href = Url::parse(&format!("{}/dav/projects/999", server.uri())).unwrap();
        broken.display_name = "Broken".into();
        let isolated = client
            .initial_sync(&[collection.clone(), broken], &BTreeMap::new())
            .await;
        assert_eq!(isolated.successful.len(), 1);
        assert_eq!(
            isolated.errors.len(),
            1,
            "collection failure must be isolated"
        );

        let synced = client
            .synchronize_collection(collection, &initial.successful[0].resources)
            .await
            .unwrap();
        assert_eq!(
            synced.resources.len(),
            1,
            "invalid token fell back to full sync"
        );

        let get_count = Arc::new(AtomicUsize::new(0));
        let get_counter = get_count.clone();
        Mock::given(method("GET"))
            .and(path("/dav/projects/36/one.ics"))
            .respond_with(move |_: &wiremock::Request| {
                let completed = get_counter.fetch_add(1, Ordering::SeqCst) > 0;
                let status = if completed { "COMPLETED" } else { "NEEDS-ACTION" };
                let completed_line = if completed { "COMPLETED:20260720T120000Z\r\n" } else { "" };
                ResponseTemplate::new(200)
                    .insert_header("etag", if completed { "\"three\"" } else { "\"two\"" })
                    .set_body_string(format!("BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:one\r\nSUMMARY:One\r\nSTATUS:{status}\r\n{completed_line}END:VTODO\r\nEND:VCALENDAR\r\n"))
            })
            .mount(&server)
            .await;
        let put_count = Arc::new(AtomicUsize::new(0));
        let put_counter = put_count.clone();
        Mock::given(method("PUT"))
            .and(path("/dav/projects/36/one.ics"))
            .respond_with(move |_: &wiremock::Request| {
                if put_counter.fetch_add(1, Ordering::SeqCst) == 0 {
                    ResponseTemplate::new(412)
                } else {
                    ResponseTemplate::new(204)
                }
            })
            .mount(&server)
            .await;
        let resource = synced.resources.values().next().unwrap();
        let mutated = client
            .mutate_task_completion(
                resource,
                true,
                chrono::Utc.with_ymd_and_hms(2026, 7, 20, 12, 0, 0).unwrap(),
                "Work",
            )
            .await
            .unwrap();
        assert_eq!(
            mutated.task.unwrap().status,
            super::super::TaskStatus::Completed
        );
        assert_eq!(put_count.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn relative_resource_hrefs_resolve_below_slashless_collection() {
        let collection = Url::parse("https://example.test/dav/projects/36").unwrap();
        assert_eq!(
            canonicalize_collection_child_href(&collection, "one.ics")
                .unwrap()
                .as_str(),
            "https://example.test/dav/projects/36/one.ics"
        );
    }

    #[test]
    fn fallback_collection_name_uses_last_path_segment() {
        assert_eq!(
            collection_name_fallback(&Url::parse("https://example.test/tasks/work/").unwrap()),
            "work"
        );
    }
}
