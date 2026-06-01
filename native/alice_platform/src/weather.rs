use std::sync::{Arc, Mutex};

use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::{Request, Uri};
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::client::legacy::Client;
use hyper_util::rt::TokioExecutor;
use serde::Deserialize;

use crate::{
    PlatformError,
    config::ValidatedWeatherConfig,
    state::{WeatherAlert, WeatherDay, WeatherPoint, WeatherSnapshot},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WeatherError {
    Transport(String),
    HttpStatus(u16),
    JsonParse(String),
    MissingField(&'static str),
    InvalidUri(String),
}

impl WeatherError {
    pub fn log_message(&self) -> String {
        match self {
            Self::Transport(error) => format!("weather transport error: {error}"),
            Self::HttpStatus(status) => format!("weather HTTP status error: {status}"),
            Self::JsonParse(error) => format!("weather JSON parse error: {error}"),
            Self::MissingField(field) => {
                format!("weather response missing required field: {field}")
            }
            Self::InvalidUri(error) => format!("weather request URI error: {error}"),
        }
    }
}

#[derive(Clone, Default)]
pub struct WeatherCache {
    inner: Arc<Mutex<Option<WeatherSnapshot>>>,
}

impl WeatherCache {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self) -> Option<WeatherSnapshot> {
        self.inner.lock().ok().and_then(|guard| guard.clone())
    }

    pub fn set(&self, snapshot: WeatherSnapshot) -> bool {
        match self.inner.lock() {
            Ok(mut guard) => {
                let changed = guard.as_ref() != Some(&snapshot);
                *guard = Some(snapshot);
                changed
            }
            Err(_) => false,
        }
    }
}

pub struct CachedWeatherProvider {
    cache: WeatherCache,
}

impl CachedWeatherProvider {
    pub fn new(cache: WeatherCache) -> Self {
        Self { cache }
    }
}

impl crate::providers::WeatherProvider for CachedWeatherProvider {
    fn read_weather(&self) -> Result<Option<WeatherSnapshot>, PlatformError> {
        Ok(self.cache.get())
    }
}

pub fn build_forecast_url(config: &ValidatedWeatherConfig) -> String {
    format!(
        "https://dev.pirateweather.net/forecast/{}/{},{}?exclude=minutely&version=2&lang={}&units={}",
        config.pirate_weather_key,
        config.forecast_lat,
        config.forecast_long,
        config.forecast_language,
        config.forecast_units,
    )
}

pub fn redact_key(value: &str, key: &str) -> String {
    if key.is_empty() {
        value.to_string()
    } else {
        value.replace(key, "<redacted>")
    }
}

pub async fn fetch_weather(
    config: &ValidatedWeatherConfig,
) -> Result<WeatherSnapshot, WeatherError> {
    let url = build_forecast_url(config);
    let uri: Uri = url.parse().map_err(|error: hyper::http::uri::InvalidUri| {
        WeatherError::InvalidUri(error.to_string())
    })?;

    let https = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_or_http()
        .enable_http1()
        .enable_http2()
        .build();
    let client: Client<_, Empty<Bytes>> = Client::builder(TokioExecutor::new()).build(https);
    let request = Request::get(uri)
        .body(Empty::<Bytes>::new())
        .map_err(|error| WeatherError::InvalidUri(error.to_string()))?;
    let response = client.request(request).await.map_err(|error| {
        WeatherError::Transport(redact_key(&error.to_string(), &config.pirate_weather_key))
    })?;
    let status = response.status();
    if !status.is_success() {
        return Err(WeatherError::HttpStatus(status.as_u16()));
    }
    let bytes = response
        .into_body()
        .collect()
        .await
        .map_err(|error| {
            WeatherError::Transport(redact_key(&error.to_string(), &config.pirate_weather_key))
        })?
        .to_bytes();
    parse_weather_response(&bytes, &config.forecast_units)
}

pub fn parse_weather_response(bytes: &[u8], units: &str) -> Result<WeatherSnapshot, WeatherError> {
    let raw: RawWeatherResponse = serde_json::from_slice(bytes)
        .map_err(|error| WeatherError::JsonParse(error.to_string()))?;
    raw.into_snapshot(units)
}

#[derive(Debug, Deserialize)]
struct RawWeatherResponse {
    latitude: Option<f64>,
    longitude: Option<f64>,
    timezone: Option<String>,
    offset: Option<f64>,
    currently: Option<RawWeatherPoint>,
    hourly: Option<RawWeatherBlock<RawWeatherPoint>>,
    daily: Option<RawWeatherBlock<RawWeatherDay>>,
    #[serde(default)]
    alerts: Vec<RawWeatherAlert>,
    flags: Option<RawFlags>,
}

#[derive(Debug, Deserialize)]
struct RawFlags {
    units: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(bound(deserialize = "T: Deserialize<'de>"))]
struct RawWeatherBlock<T> {
    #[serde(default)]
    data: Vec<T>,
}

#[derive(Debug, Deserialize)]
struct RawWeatherPoint {
    time: Option<i64>,
    summary: Option<String>,
    icon: Option<String>,
    temperature: Option<f64>,
    humidity: Option<f64>,
    #[serde(rename = "precipProbability")]
    precip_probability: Option<f64>,
    #[serde(rename = "windSpeed")]
    wind_speed: Option<f64>,
    #[serde(rename = "windBearing")]
    wind_bearing: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct RawWeatherDay {
    time: Option<i64>,
    summary: Option<String>,
    icon: Option<String>,
    #[serde(rename = "moonPhase")]
    moon_phase: Option<f64>,
    #[serde(rename = "temperatureHigh")]
    temperature_high: Option<f64>,
    #[serde(rename = "temperatureLow")]
    temperature_low: Option<f64>,
    humidity: Option<f64>,
    #[serde(rename = "precipProbability")]
    precip_probability: Option<f64>,
    #[serde(rename = "windSpeed")]
    wind_speed: Option<f64>,
    #[serde(rename = "windBearing")]
    wind_bearing: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct RawWeatherAlert {
    title: Option<String>,
    description: Option<String>,
    severity: Option<String>,
    time: Option<i64>,
    expires: Option<i64>,
}

impl RawWeatherResponse {
    fn into_snapshot(self, fallback_units: &str) -> Result<WeatherSnapshot, WeatherError> {
        let latitude = clean_required(self.latitude, "latitude")?;
        let longitude = clean_required(self.longitude, "longitude")?;
        let timezone = self
            .timezone
            .filter(|value| !value.trim().is_empty())
            .ok_or(WeatherError::MissingField("timezone"))?;
        let currently = self
            .currently
            .ok_or(WeatherError::MissingField("currently"))?
            .into_point()?;
        let units = self
            .flags
            .and_then(|flags| flags.units)
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| fallback_units.to_string());

        Ok(WeatherSnapshot {
            latitude,
            longitude,
            timezone,
            offset: clean_f64(self.offset).unwrap_or(0.0),
            units,
            last_updated_unix_secs: chrono::Utc::now().timestamp(),
            currently,
            hourly: self
                .hourly
                .map(|block| {
                    block
                        .data
                        .into_iter()
                        .filter_map(|point| point.into_point().ok())
                        .collect()
                })
                .unwrap_or_default(),
            daily: self
                .daily
                .map(|block| {
                    block
                        .data
                        .into_iter()
                        .filter_map(|day| day.into_day().ok())
                        .collect()
                })
                .unwrap_or_default(),
            alerts: self
                .alerts
                .into_iter()
                .map(|alert| WeatherAlert {
                    title: alert.title.unwrap_or_default(),
                    description: alert.description.unwrap_or_default(),
                    severity: alert.severity.unwrap_or_default(),
                    time: clean_i64(alert.time),
                    expires: clean_i64(alert.expires),
                })
                .collect(),
        })
    }
}

impl RawWeatherPoint {
    fn into_point(self) -> Result<WeatherPoint, WeatherError> {
        Ok(WeatherPoint {
            time: self.time.ok_or(WeatherError::MissingField("time"))?,
            summary: self.summary.unwrap_or_default(),
            icon: self.icon.unwrap_or_default(),
            temperature: clean_f64(self.temperature),
            humidity: clean_f64(self.humidity),
            precip_probability: clean_f64(self.precip_probability),
            wind_speed: clean_f64(self.wind_speed),
            wind_bearing: clean_f64(self.wind_bearing),
        })
    }
}

impl RawWeatherDay {
    fn into_day(self) -> Result<WeatherDay, WeatherError> {
        Ok(WeatherDay {
            time: self.time.ok_or(WeatherError::MissingField("time"))?,
            summary: self.summary.unwrap_or_default(),
            icon: self.icon.unwrap_or_default(),
            moon_phase: clean_f64(self.moon_phase),
            temperature_high: clean_f64(self.temperature_high),
            temperature_low: clean_f64(self.temperature_low),
            humidity: clean_f64(self.humidity),
            precip_probability: clean_f64(self.precip_probability),
            wind_speed: clean_f64(self.wind_speed),
            wind_bearing: clean_f64(self.wind_bearing),
        })
    }
}

fn clean_required(value: Option<f64>, field: &'static str) -> Result<f64, WeatherError> {
    clean_f64(value).ok_or(WeatherError::MissingField(field))
}

fn clean_f64(value: Option<f64>) -> Option<f64> {
    value.filter(|value| value.is_finite() && (*value - -999.0).abs() > f64::EPSILON)
}

fn clean_i64(value: Option<i64>) -> Option<i64> {
    value.filter(|value| *value != -999)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &[u8] = include_bytes!("../tests/fixtures/pirate_weather_sample.json");

    #[test]
    fn builds_redactable_forecast_url() {
        let config = ValidatedWeatherConfig {
            pirate_weather_key: "secret".into(),
            forecast_lat: 43.407,
            forecast_long: -70.996,
            forecast_language: "en".into(),
            forecast_units: "us".into(),
            refresh_interval: 3600,
        };
        let url = build_forecast_url(&config);
        assert_eq!(
            url,
            "https://dev.pirateweather.net/forecast/secret/43.407,-70.996?exclude=minutely&version=2&lang=en&units=us"
        );
        assert_eq!(
            redact_key(&url, "secret"),
            "https://dev.pirateweather.net/forecast/<redacted>/43.407,-70.996?exclude=minutely&version=2&lang=en&units=us"
        );
    }

    #[test]
    fn parses_sample_response() {
        let snapshot = parse_weather_response(SAMPLE, "us").expect("sample should parse");
        assert_eq!(snapshot.latitude, 43.4);
        assert_eq!(snapshot.longitude, -70.9);
        assert_eq!(snapshot.timezone, "America/New_York");
        assert_eq!(snapshot.offset, -4.0);
        assert_eq!(snapshot.units, "us");
        assert_eq!(snapshot.currently.summary, "Clear");
        assert_eq!(snapshot.currently.icon, "clear-day");
        assert_eq!(snapshot.currently.temperature, Some(50.25));
        assert!(!snapshot.hourly.is_empty());
        assert!(!snapshot.daily.is_empty());
    }

    #[test]
    fn cleans_sentinel_values() {
        let json = br#"{
          "latitude": 1,
          "longitude": 2,
          "timezone": "UTC",
          "offset": 0,
          "currently": {"time": 1, "temperature": -999, "summary": "", "icon": "cloudy"}
        }"#;
        let snapshot = parse_weather_response(json, "si").expect("sentinel response should parse");
        assert_eq!(snapshot.currently.temperature, None);
    }
}
