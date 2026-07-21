use std::{error::Error, fmt, fs, time::Duration};

use quick_xml::{Reader, events::Event};
use reqwest::{Method, RequestBuilder, Response, redirect};
use url::Url;

use crate::config::ValidatedCalDavConfig;

use super::same_origin;

const MAX_XML_BYTES: usize = 8 * 1024 * 1024;
const MAX_REDIRECTS: usize = 10;

/// Authenticated client constrained to the configured principal origin.
#[derive(Clone)]
pub struct CalDavClient {
    http: reqwest::Client,
    config: ValidatedCalDavConfig,
}

impl CalDavClient {
    pub fn new(config: ValidatedCalDavConfig) -> Result<Self, CalDavClientError> {
        Self::build(config)
    }

    #[cfg(test)]
    pub(crate) fn new_for_test(config: ValidatedCalDavConfig) -> Result<Self, CalDavClientError> {
        Self::build(config)
    }

    fn build(config: ValidatedCalDavConfig) -> Result<Self, CalDavClientError> {
        let principal_origin = config.principal_url.clone();
        let redirect_policy = redirect::Policy::custom(move |attempt| {
            if attempt.previous().len() >= MAX_REDIRECTS {
                return attempt.error("too many CalDAV redirects");
            }
            if !same_origin(&principal_origin, attempt.url()) {
                return attempt.error("CalDAV redirect changed origin");
            }
            attempt.follow()
        });
        let mut builder = reqwest::Client::builder()
            .https_only(!config.allow_http)
            .redirect(redirect_policy)
            .connect_timeout(Duration::from_secs(15))
            .timeout(Duration::from_secs(60))
            .user_agent("alicebar-caldav/0.1");

        if let Some(path) = &config.ca_certificate_path {
            let pem = fs::read(path).map_err(|error| {
                CalDavClientError::new(config.redact(&format!(
                    "failed to read caldav.ca_certificate_path: {error}"
                )))
            })?;
            let certificates = reqwest::Certificate::from_pem_bundle(&pem).map_err(|_| {
                CalDavClientError::new("caldav.ca_certificate_path is not a valid PEM certificate")
            })?;
            if certificates.is_empty() {
                return Err(CalDavClientError::new(
                    "caldav.ca_certificate_path is not a valid PEM certificate",
                ));
            }
            for certificate in certificates {
                builder = builder.add_root_certificate(certificate);
            }
        }

        let http = builder.build().map_err(|error| {
            CalDavClientError::new(
                config.redact(&format!("failed to build CalDAV client: {error}")),
            )
        })?;
        Ok(Self { http, config })
    }

    /// Build an authenticated request only for the configured origin.
    pub fn request(&self, method: Method, url: Url) -> Result<RequestBuilder, CalDavClientError> {
        if !same_origin(&self.config.principal_url, &url) {
            return Err(CalDavClientError::new(
                "CalDAV request URL changed configured origin",
            ));
        }
        if url.scheme() != "https" && !(url.scheme() == "http" && self.config.allow_http) {
            return Err(CalDavClientError::new(
                "CalDAV request URL must use HTTPS unless caldav.allow_http is true",
            ));
        }
        Ok(self
            .http
            .request(method, url)
            .basic_auth(&self.config.username, Some(self.config.token())))
    }

    pub async fn send(&self, request: RequestBuilder) -> Result<Response, CalDavClientError> {
        request.send().await.map_err(|error| {
            CalDavClientError::new(
                self.config
                    .redact(&format!("CalDAV transport request failed: {error}")),
            )
        })
    }

    pub fn redact(&self, message: &str) -> String {
        self.config.redact(message)
    }

    pub fn principal_url(&self) -> &Url {
        &self.config.principal_url
    }

    pub fn allowed_collection_urls(&self) -> &[Url] {
        &self.config.collection_urls
    }
}

impl fmt::Debug for CalDavClient {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("CalDavClient")
            .field("principal_url", &self.config.principal_url)
            .field("username", &self.config.username)
            .field("credential", &"[REDACTED]")
            .finish_non_exhaustive()
    }
}

/// Validate a WebDAV XML body using a non-networking pull parser and reject
/// DTD declarations before protocol-specific parsing occurs.
pub fn validate_safe_xml(bytes: &[u8]) -> Result<(), CalDavClientError> {
    if bytes.len() > MAX_XML_BYTES {
        return Err(CalDavClientError::new("CalDAV XML response is too large"));
    }

    let mut reader = Reader::from_reader(bytes);
    reader.config_mut().check_comments = true;
    loop {
        match reader.read_event() {
            Ok(Event::DocType(_)) => {
                return Err(CalDavClientError::new(
                    "CalDAV XML response contains a forbidden DTD",
                ));
            }
            Ok(Event::Eof) => return Ok(()),
            Ok(_) => {}
            Err(_) => return Err(CalDavClientError::new("invalid CalDAV XML response")),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalDavClientError {
    message: String,
}

impl CalDavClientError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for CalDavClientError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for CalDavClientError {}

impl From<String> for CalDavClientError {
    fn from(message: String) -> Self {
        Self::new(message)
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn config(ca_certificate_path: Option<PathBuf>) -> ValidatedCalDavConfig {
        crate::config::AliceConfig::from_yaml_str(&format!(
            "caldav:\n  principal_url: https://tasks.example.test/dav/\n  username: alice\n  token: never-log-this-token\n  collection_hrefs: [/tasks/]\n{}",
            ca_certificate_path
                .map(|path| format!("  ca_certificate_path: {}\n", path.display()))
                .unwrap_or_default()
        ))
        .unwrap()
        .caldav
        .unwrap()
        .validated_for_runtime()
        .unwrap()
    }

    #[test]
    fn request_is_https_same_origin_and_authorization_is_sensitive() {
        let client = CalDavClient::new(config(None)).unwrap();
        let request = client
            .request(
                Method::from_bytes(b"PROPFIND").unwrap(),
                Url::parse("https://tasks.example.test/tasks/").unwrap(),
            )
            .unwrap()
            .build()
            .unwrap();
        let authorization = request
            .headers()
            .get(reqwest::header::AUTHORIZATION)
            .unwrap();
        assert!(authorization.is_sensitive());
        assert!(format!("{request:?}").contains("Sensitive"));
        assert!(!format!("{request:?}").contains("never-log-this-token"));

        let error = client
            .request(
                Method::GET,
                Url::parse("https://other.example.test/tasks/").unwrap(),
            )
            .unwrap_err();
        assert!(error.to_string().contains("changed configured origin"));
    }

    #[test]
    fn explicitly_enabled_http_is_supported_in_production_client() {
        let config = crate::config::AliceConfig::from_yaml_str(
            "caldav:\n  principal_url: http://tasks.example.test/dav/\n  allow_http: true\n  username: alice\n  token: never-log-this-token\n  collection_hrefs: [/tasks/]\n",
        )
        .unwrap()
        .caldav
        .unwrap()
        .validated_for_runtime()
        .unwrap();
        let client = CalDavClient::new(config).unwrap();
        let request = client
            .request(
                Method::from_bytes(b"PROPFIND").unwrap(),
                Url::parse("http://tasks.example.test/tasks/").unwrap(),
            )
            .unwrap()
            .build()
            .unwrap();

        assert_eq!(request.url().scheme(), "http");
        assert!(
            request
                .headers()
                .get(reqwest::header::AUTHORIZATION)
                .unwrap()
                .is_sensitive()
        );
        assert!(
            client
                .request(
                    Method::GET,
                    Url::parse("http://other.example.test/tasks/").unwrap(),
                )
                .unwrap_err()
                .to_string()
                .contains("changed configured origin")
        );
    }

    #[test]
    fn debug_and_redaction_never_expose_token_or_authorization_value() {
        let client = CalDavClient::new(config(None)).unwrap();
        let debug = format!("{client:?}");
        assert!(debug.contains("[REDACTED]"));
        assert!(!debug.contains("never-log-this-token"));
        let redacted =
            client.redact("token=never-log-this-token\nAuthorization: Basic dXNlcjpzZWNyZXQ=");
        assert!(!redacted.contains("never-log-this-token"));
        assert!(!redacted.contains("dXNlc"));
    }

    #[test]
    fn invalid_custom_ca_fails_without_echoing_contents() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("ca.pem");
        fs::write(&path, "secret invalid certificate body").unwrap();
        let error = CalDavClient::new(config(Some(path))).unwrap_err();
        assert!(error.to_string().contains("not a valid PEM certificate"));
        assert!(!error.to_string().contains("secret"));
    }

    #[test]
    fn safe_xml_accepts_webdav_and_rejects_dtd_or_oversized_input() {
        validate_safe_xml(
            br#"<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response/></d:multistatus>"#,
        )
        .unwrap();
        assert!(
            validate_safe_xml(
                br#"<?xml version="1.0"?><!DOCTYPE x [<!ENTITY ext SYSTEM "file:///etc/passwd">]><x>&ext;</x>"#
            )
            .unwrap_err()
            .to_string()
            .contains("forbidden DTD")
        );
        assert!(
            validate_safe_xml(&vec![b'x'; MAX_XML_BYTES + 1])
                .unwrap_err()
                .to_string()
                .contains("too large")
        );
    }
}
