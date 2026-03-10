use std::collections::HashMap;

use zbus::{
    blocking::{Connection, Proxy},
    zvariant::OwnedValue,
};

use crate::{PlatformError, providers::MediaProvider, state::MediaSnapshot};

const DBUS_SERVICE: &str = "org.freedesktop.DBus";
const DBUS_PATH: &str = "/org/freedesktop/DBus";
const DBUS_INTERFACE: &str = "org.freedesktop.DBus";
const MPRIS_PREFIX: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const MPRIS_PLAYER_INTERFACE: &str = "org.mpris.MediaPlayer2.Player";

pub enum MediaControlAction {
    Previous,
    PlayPause,
    Next,
}

pub struct MprisMediaProvider;

impl MprisMediaProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_from_connection(
        connection: &Connection,
    ) -> Result<Option<MediaSnapshot>, PlatformError> {
        let player_names = list_player_names(connection)?;
        let mut fallback = None;

        for name in player_names {
            let snapshot = read_player_snapshot(connection, &name)?;
            let Some(snapshot) = snapshot else {
                continue;
            };

            if snapshot.is_playing {
                return Ok(Some(snapshot));
            }

            if fallback.is_none() {
                fallback = Some(snapshot);
            }
        }

        Ok(fallback)
    }
}

impl MediaProvider for MprisMediaProvider {
    fn read_media(&self) -> Result<Option<MediaSnapshot>, PlatformError> {
        let connection = Connection::session().map_err(|error| {
            PlatformError::new(format!("failed to connect to session bus: {error}"))
        })?;
        Self::read_from_connection(&connection)
    }
}

pub fn send_media_action(action: MediaControlAction) -> Result<(), PlatformError> {
    let connection = Connection::session().map_err(|error| {
        PlatformError::new(format!("failed to connect to session bus: {error}"))
    })?;
    let player_names = list_player_names(&connection)?;
    if player_names.is_empty() {
        return Err(PlatformError::new("no MPRIS players are available"));
    }

    let target = choose_control_target(&connection, &player_names)?;
    let proxy = Proxy::new(
        &connection,
        target.as_str(),
        MPRIS_PATH,
        MPRIS_PLAYER_INTERFACE,
    )
    .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;

    let method_name = match action {
        MediaControlAction::Previous => "Previous",
        MediaControlAction::PlayPause => "PlayPause",
        MediaControlAction::Next => "Next",
    };

    proxy.call_noreply(method_name, &()).map_err(|error| {
        PlatformError::new(format!(
            "failed to send MPRIS command '{method_name}': {error}"
        ))
    })
}

fn choose_control_target(
    connection: &Connection,
    player_names: &[String],
) -> Result<String, PlatformError> {
    let mut fallback = None;

    for name in player_names {
        let proxy = Proxy::new(
            connection,
            name.as_str(),
            MPRIS_PATH,
            MPRIS_PLAYER_INTERFACE,
        )
        .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;
        let playback_status: String = proxy.get_property("PlaybackStatus").map_err(|error| {
            PlatformError::new(format!("failed to read PlaybackStatus: {error}"))
        })?;

        if playback_status == "Playing" {
            return Ok(name.clone());
        }
        if fallback.is_none() {
            fallback = Some(name.clone());
        }
    }

    fallback.ok_or_else(|| PlatformError::new("no MPRIS players are available"))
}

fn list_player_names(connection: &Connection) -> Result<Vec<String>, PlatformError> {
    let proxy = Proxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE)
        .map_err(|error| PlatformError::new(format!("failed to create DBus proxy: {error}")))?;
    let names: Vec<String> = proxy
        .call("ListNames", &())
        .map_err(|error| PlatformError::new(format!("failed to list DBus names: {error}")))?;

    Ok(names
        .into_iter()
        .filter(|name| name.starts_with(MPRIS_PREFIX))
        .collect())
}

fn read_player_snapshot(
    connection: &Connection,
    bus_name: &str,
) -> Result<Option<MediaSnapshot>, PlatformError> {
    let proxy = Proxy::new(connection, bus_name, MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
        .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;

    let playback_status: String = proxy
        .get_property("PlaybackStatus")
        .map_err(|error| PlatformError::new(format!("failed to read PlaybackStatus: {error}")))?;

    let metadata: HashMap<String, OwnedValue> = proxy
        .get_property("Metadata")
        .map_err(|error| PlatformError::new(format!("failed to read Metadata: {error}")))?;

    let title = metadata_string(&metadata, "xesam:title");
    if title.as_deref().unwrap_or("").is_empty() {
        return Ok(None);
    }

    let artist = metadata_artists(&metadata).unwrap_or_else(|| "Unknown artist".into());
    let length_micros = metadata_i64(&metadata, "mpris:length").unwrap_or(0);
    let position_micros: i64 = proxy.get_property("Position").unwrap_or(0_i64);

    Ok(Some(MediaSnapshot {
        title: title.unwrap_or_else(|| "Unknown title".into()),
        artist,
        position_label: format_duration(position_micros),
        length_label: format_duration(length_micros),
        is_playing: playback_status == "Playing",
    }))
}

fn metadata_string(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(|value| value.clone().try_into().ok())
}

fn metadata_artists(metadata: &HashMap<String, OwnedValue>) -> Option<String> {
    let artists: Vec<String> = metadata.get("xesam:artist")?.clone().try_into().ok()?;
    if artists.is_empty() {
        None
    } else {
        Some(artists.join(", "))
    }
}

fn metadata_i64(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<i64> {
    metadata
        .get(key)
        .and_then(|value| value.clone().try_into().ok())
}

fn format_duration(microseconds: i64) -> String {
    let total_seconds = (microseconds.max(0) / 1_000_000) as u64;
    let minutes = total_seconds / 60;
    let seconds = total_seconds % 60;
    format!("{minutes}:{seconds:02}")
}

#[cfg(test)]
mod tests {
    use super::{MediaControlAction, format_duration};

    #[test]
    fn formats_microseconds_as_clock_label() {
        assert_eq!(format_duration(0), "0:00");
        assert_eq!(format_duration(26_000_000), "0:26");
        assert_eq!(format_duration(130_000_000), "2:10");
    }

    #[test]
    fn media_control_action_variants_exist() {
        let _ = MediaControlAction::Previous;
        let _ = MediaControlAction::PlayPause;
        let _ = MediaControlAction::Next;
    }
}
