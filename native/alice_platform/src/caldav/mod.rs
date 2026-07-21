//! CalDAV protocol, parsing, and cache support.
//!
//! Keep URL and redaction helpers here so configuration, transport, and
//! protocol errors all apply the same origin and credential rules.

use url::Url;

pub mod cache;
pub mod client;
pub mod ical;
pub mod models;
pub mod protocol;
pub mod provider;
pub mod service;
pub use models::*;

/// Parse and canonicalize the URL used as the CalDAV trust origin.
pub fn canonicalize_principal_url(value: &str, allow_http: bool) -> Result<Url, String> {
    let url = Url::parse(value.trim()).map_err(|_| "caldav.principal_url must be a URL")?;
    validate_caldav_url(&url, "caldav.principal_url", allow_http)?;
    Ok(url)
}

/// Resolve a WebDAV href against the principal URL and require the same origin.
pub fn canonicalize_href(principal: &Url, href: &str) -> Result<Url, String> {
    let href = href.trim();
    if href.is_empty() {
        return Err("caldav.collection_hrefs must not contain empty values".into());
    }

    let url = principal
        .join(href)
        .map_err(|_| "caldav.collection_hrefs contains an invalid href")?;
    validate_caldav_url(
        &url,
        "caldav.collection_hrefs",
        principal.scheme() == "http",
    )?;
    if !same_origin(principal, &url) {
        return Err("caldav.collection_hrefs must use the principal origin".into());
    }
    Ok(url)
}

/// Return whether two HTTP URLs have the same scheme, host, and effective port.
pub fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme().eq_ignore_ascii_case(right.scheme())
        && left.host_str().map(str::to_ascii_lowercase)
            == right.host_str().map(str::to_ascii_lowercase)
        && left.port_or_known_default() == right.port_or_known_default()
}

/// Stable comparison key for collection URLs.
///
/// DAV servers commonly advertise a collection both with and without a
/// trailing slash. Those forms identify the same configured allowlist entry,
/// but requests continue using the server-advertised URL unchanged.
pub fn collection_url_key(url: &Url) -> String {
    let mut normalized = url.clone();
    let path = normalized.path().trim_end_matches('/').to_string();
    if !path.is_empty() {
        normalized.set_path(&path);
    }
    normalized.to_string()
}

/// Remove configured secrets and complete Authorization header values from text.
///
/// This is intended for errors and logs only. Raw CalDAV bodies must never be
/// passed into user-visible errors in the first place.
pub fn redact_sensitive(input: &str, secrets: &[&str]) -> String {
    let mut redacted = input
        .split('\n')
        .map(redact_authorization_line)
        .collect::<Vec<_>>()
        .join("\n");

    for secret in secrets {
        if !secret.is_empty() {
            redacted = redacted.replace(secret, "[REDACTED]");
        }
    }
    redacted
}

fn validate_caldav_url(url: &Url, field: &str, allow_http: bool) -> Result<(), String> {
    match url.scheme() {
        "https" => {}
        "http" if allow_http => {}
        "http" => {
            return Err(format!(
                "{field} must use HTTPS unless caldav.allow_http is true"
            ));
        }
        _ => return Err(format!("{field} must use HTTP or HTTPS")),
    }
    if url.host_str().is_none() {
        return Err(format!("{field} must include a host"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(format!("{field} must not contain credentials"));
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(format!("{field} must not contain a query or fragment"));
    }
    Ok(())
}

fn redact_authorization_line(line: &str) -> String {
    const HEADER: &str = "authorization:";
    let lowercase = line.to_ascii_lowercase();
    match lowercase.find(HEADER) {
        Some(index) => format!("{}Authorization: [REDACTED]", &line[..index]),
        None => line.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonicalizes_relative_and_default_port_hrefs() {
        let principal = canonicalize_principal_url(
            "https://TASKS.example.test:443/dav/principals/alice/",
            false,
        )
        .unwrap();
        let collection =
            canonicalize_href(&principal, "/dav/calendars/alice/./work/../work/").unwrap();

        assert_eq!(
            principal.as_str(),
            "https://tasks.example.test/dav/principals/alice/"
        );
        assert_eq!(
            collection.as_str(),
            "https://tasks.example.test/dav/calendars/alice/work/"
        );
        assert!(same_origin(&principal, &collection));
        assert_eq!(
            collection_url_key(&collection),
            "https://tasks.example.test/dav/calendars/alice/work"
        );
        assert_eq!(
            collection_url_key(
                &Url::parse("https://tasks.example.test/dav/calendars/alice/work").unwrap()
            ),
            collection_url_key(&collection)
        );
    }

    #[test]
    fn rejects_insecure_or_cross_origin_urls() {
        assert_eq!(
            canonicalize_principal_url("http://tasks.example.test/dav/", false).unwrap_err(),
            "caldav.principal_url must use HTTPS unless caldav.allow_http is true"
        );
        let http = canonicalize_principal_url("http://tasks.example.test/dav/", true).unwrap();
        assert_eq!(http.as_str(), "http://tasks.example.test/dav/");

        let principal =
            canonicalize_principal_url("https://tasks.example.test/dav/", false).unwrap();
        assert_eq!(
            canonicalize_href(&principal, "https://other.example.test/tasks/").unwrap_err(),
            "caldav.collection_hrefs must use the principal origin"
        );
        assert!(
            canonicalize_href(&principal, "https://alice:secret@tasks.example.test/tasks/")
                .unwrap_err()
                .contains("must not contain credentials")
        );
    }

    #[test]
    fn redacts_tokens_and_authorization_headers_case_insensitively() {
        let message = "request failed with token secret-token\nAUTHORIZATION: Basic dXNlcjp0b2tlbg==\nretry failed";
        let redacted = redact_sensitive(message, &["secret-token"]);

        assert_eq!(
            redacted,
            "request failed with token [REDACTED]\nAuthorization: [REDACTED]\nretry failed"
        );
        assert!(!redacted.contains("dXNlc"));
        assert!(!redacted.contains("secret-token"));
    }
}
