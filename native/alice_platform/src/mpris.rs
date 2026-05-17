use std::{
    collections::HashMap,
    sync::{Arc, OnceLock, RwLock},
    time::{Duration, Instant},
};

use futures_util::StreamExt;
use tokio::sync::mpsc;
use zbus::{
    blocking::{Connection as BlockingConnection, Proxy as BlockingProxy},
    fdo::DBusProxy,
    zvariant::OwnedValue,
};

use crate::{PlatformError, providers::MediaProvider, runtime::Trigger, state::MediaSnapshot};

const DBUS_SERVICE: &str = "org.freedesktop.DBus";
const DBUS_PATH: &str = "/org/freedesktop/DBus";
const DBUS_INTERFACE: &str = "org.freedesktop.DBus";
const MPRIS_PREFIX: &str = "org.mpris.MediaPlayer2.";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const MPRIS_PLAYER_INTERFACE: &str = "org.mpris.MediaPlayer2.Player";
const NO_TRACK_PATH: &str = "/org/mpris/MediaPlayer2/TrackList/NoTrack";

static GLOBAL_CACHE: OnceLock<Arc<MprisCache>> = OnceLock::new();

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlaybackState {
    Playing,
    Paused,
    Stopped,
    Other(String),
}

impl PlaybackState {
    fn from_status(status: String) -> Self {
        match status.as_str() {
            "Playing" => Self::Playing,
            "Paused" => Self::Paused,
            "Stopped" => Self::Stopped,
            _ => Self::Other(status),
        }
    }

    fn is_playing(&self) -> bool {
        matches!(self, Self::Playing)
    }
}

#[derive(Debug, Clone)]
pub struct CachedMprisPlayer {
    pub bus_name: String,
    pub title: String,
    pub artist: String,
    pub album_title: String,
    pub art_url: String,
    pub playback_state: PlaybackState,
    pub track_id: String,
    pub base_position_micros: i64,
    pub observed_at: Instant,
    pub length_micros: i64,
}

#[derive(Debug, Default)]
struct MprisCacheInner {
    players: Vec<CachedMprisPlayer>,
}

#[derive(Debug, Default)]
pub struct MprisCache {
    inner: RwLock<MprisCacheInner>,
}

impl MprisCache {
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn install_global(cache: Arc<Self>) {
        let _ = GLOBAL_CACHE.set(cache);
    }

    pub fn global() -> Option<Arc<Self>> {
        GLOBAL_CACHE.get().cloned()
    }

    pub fn upsert_player(&self, player: CachedMprisPlayer) -> bool {
        let before = self.project();
        let mut guard = self.inner.write().unwrap_or_else(|e| e.into_inner());
        if let Some(existing) = guard.players.iter_mut().find(|p| p.bus_name == player.bus_name) {
            *existing = player;
        } else {
            guard.players.push(player);
        }
        drop(guard);
        before != self.project()
    }

    pub fn remove_player(&self, bus_name: &str) -> bool {
        let before = self.project();
        let mut guard = self.inner.write().unwrap_or_else(|e| e.into_inner());
        guard.players.retain(|p| p.bus_name != bus_name);
        drop(guard);
        before != self.project()
    }

    pub fn replace_players(&self, players: Vec<CachedMprisPlayer>) -> bool {
        let before = self.project();
        let mut guard = self.inner.write().unwrap_or_else(|e| e.into_inner());
        guard.players = players;
        drop(guard);
        before != self.project()
    }

    pub fn selected_player_bus_name(&self) -> Option<String> {
        self.selected_player().map(|p| p.bus_name)
    }

    pub fn selected_track_id(&self) -> Option<String> {
        self.selected_player().map(|p| p.track_id)
    }

    pub fn has_playing_selection(&self) -> bool {
        self.selected_player()
            .map(|p| p.playback_state.is_playing())
            .unwrap_or(false)
    }

    fn selected_player(&self) -> Option<CachedMprisPlayer> {
        let guard = self.inner.read().unwrap_or_else(|e| e.into_inner());
        guard
            .players
            .iter()
            .find(|p| p.playback_state.is_playing() && !p.title.is_empty())
            .or_else(|| guard.players.iter().find(|p| !p.title.is_empty()))
            .cloned()
    }

    pub fn project(&self) -> Option<MediaSnapshot> {
        self.selected_player().and_then(|player| project_player(&player, Instant::now()))
    }
}

pub struct CachedMprisMediaProvider {
    cache: Arc<MprisCache>,
}

impl CachedMprisMediaProvider {
    pub fn new(cache: Arc<MprisCache>) -> Self {
        Self { cache }
    }
}

impl MediaProvider for CachedMprisMediaProvider {
    fn read_media(&self) -> Result<Option<MediaSnapshot>, PlatformError> {
        Ok(self.cache.project())
    }
}

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
        connection: &BlockingConnection,
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
        let connection = BlockingConnection::session().map_err(|error| {
            PlatformError::new(format!("failed to connect to session bus: {error}"))
        })?;
        Self::read_from_connection(&connection)
    }
}

pub async fn run_mpris_runtime_service(
    cache: Arc<MprisCache>,
    tx: mpsc::Sender<Trigger>,
) -> Result<(), PlatformError> {
    let connection = zbus::Connection::session()
        .await
        .map_err(|error| PlatformError::new(format!("failed to connect to session bus: {error}")))?;

    refresh_cache_from_connection(&connection, &cache).await?;
    let _ = tx.send(Trigger::Event).await;

    let dbus = DBusProxy::new(&connection)
        .await
        .map_err(|error| PlatformError::new(format!("failed to create DBus proxy: {error}")))?;
    let mut names = dbus
        .receive_name_owner_changed()
        .await
        .map_err(|error| PlatformError::new(format!("failed to watch DBus names: {error}")))?;

    let props_rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")
        .map_err(|error| PlatformError::new(format!("failed to build MPRIS match rule: {error}")))?
        .member("PropertiesChanged")
        .map_err(|error| PlatformError::new(format!("failed to build MPRIS match rule: {error}")))?
        .path(MPRIS_PATH)
        .map_err(|error| PlatformError::new(format!("failed to build MPRIS match rule: {error}")))?
        .build();
    let mut props = zbus::MessageStream::for_match_rule(props_rule, &connection, None)
        .await
        .map_err(|error| PlatformError::new(format!("failed to watch MPRIS properties: {error}")))?;

    loop {
        tokio::select! {
            maybe_changed = names.next() => {
                let Some(changed) = maybe_changed else { break; };
                let Ok(args) = changed.args() else { continue; };
                let name = args.name().to_string();
                if !name.starts_with(MPRIS_PREFIX) {
                    continue;
                }
                let changed = if args.new_owner().is_some() {
                    match read_player_cached_async(&connection, &name).await {
                        Ok(Some(player)) => cache.upsert_player(player),
                        Ok(None) => cache.remove_player(&name),
                        Err(error) => {
                            eprintln!("alice: failed to inspect MPRIS player {name}: {error:?}");
                            false
                        }
                    }
                } else {
                    cache.remove_player(&name)
                };
                if changed && tx.send(Trigger::Event).await.is_err() {
                    break;
                }
            }
            maybe_message = props.next() => {
                let Some(Ok(message)) = maybe_message else { break; };
                let Ok((interface,)): Result<(String,), _> = message.body().deserialize() else {
                    // Body has more fields; deserialize prefix-only is not always supported.
                    // If this is an MPRIS property signal, a cheap known-player refresh is still safe.
                    if refresh_known_players(&connection, &cache).await.unwrap_or(false)
                        && tx.send(Trigger::Event).await.is_err() {
                        break;
                    }
                    continue;
                };
                if interface == MPRIS_PLAYER_INTERFACE
                    && refresh_known_players(&connection, &cache).await.unwrap_or(false)
                    && tx.send(Trigger::Event).await.is_err() {
                    break;
                }
            }
        }
    }

    Ok(())
}

pub async fn media_position_trigger(cache: Arc<MprisCache>, tx: mpsc::Sender<Trigger>) {
    let mut interval = tokio::time::interval(Duration::from_secs(1));
    loop {
        interval.tick().await;
        if cache.has_playing_selection() && tx.send(Trigger::Event).await.is_err() {
            break;
        }
    }
}

async fn refresh_cache_from_connection(
    connection: &zbus::Connection,
    cache: &MprisCache,
) -> Result<bool, PlatformError> {
    let mut players = Vec::new();
    for name in list_player_names_async(connection).await? {
        if let Some(player) = read_player_cached_async(connection, &name).await? {
            players.push(player);
        }
    }
    Ok(cache.replace_players(players))
}

async fn refresh_known_players(
    connection: &zbus::Connection,
    cache: &MprisCache,
) -> Result<bool, PlatformError> {
    // Property signals expose the unique sender name, while the cache keys by well-known
    // MPRIS name. Refresh discovered MPRIS players without rediscovering during snapshot reads.
    refresh_cache_from_connection(connection, cache).await
}

async fn list_player_names_async(connection: &zbus::Connection) -> Result<Vec<String>, PlatformError> {
    let proxy = DBusProxy::new(connection)
        .await
        .map_err(|error| PlatformError::new(format!("failed to create DBus proxy: {error}")))?;
    let names = proxy
        .list_names()
        .await
        .map_err(|error| PlatformError::new(format!("failed to list DBus names: {error}")))?;
    Ok(names
        .into_iter()
        .map(|name| name.to_string())
        .filter(|name| name.starts_with(MPRIS_PREFIX))
        .collect())
}

async fn read_player_cached_async(
    connection: &zbus::Connection,
    bus_name: &str,
) -> Result<Option<CachedMprisPlayer>, PlatformError> {
    let proxy = zbus::Proxy::new(connection, bus_name, MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
        .await
        .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;
    let playback_status: String = proxy
        .get_property("PlaybackStatus")
        .await
        .map_err(|error| PlatformError::new(format!("failed to read PlaybackStatus: {error}")))?;
    let metadata: HashMap<String, OwnedValue> = proxy
        .get_property("Metadata")
        .await
        .map_err(|error| PlatformError::new(format!("failed to read Metadata: {error}")))?;
    let position_micros: i64 = proxy.get_property("Position").await.unwrap_or(0_i64);
    Ok(cached_player_from_parts(bus_name, playback_status, metadata, position_micros))
}

fn cached_player_from_parts(
    bus_name: &str,
    playback_status: String,
    metadata: HashMap<String, OwnedValue>,
    position_micros: i64,
) -> Option<CachedMprisPlayer> {
    let title = metadata_string(&metadata, "xesam:title").unwrap_or_default();
    if title.is_empty() {
        return None;
    }

    Some(CachedMprisPlayer {
        bus_name: bus_name.into(),
        title,
        artist: metadata_artists(&metadata).unwrap_or_else(|| "Unknown artist".into()),
        album_title: metadata_string(&metadata, "xesam:album").unwrap_or_default(),
        art_url: metadata_string(&metadata, "mpris:artUrl").unwrap_or_default(),
        playback_state: PlaybackState::from_status(playback_status),
        track_id: metadata_object_path(&metadata, "mpris:trackid").unwrap_or_else(|| NO_TRACK_PATH.into()),
        base_position_micros: position_micros,
        observed_at: Instant::now(),
        length_micros: metadata_i64(&metadata, "mpris:length").unwrap_or(0),
    })
}

fn project_player(player: &CachedMprisPlayer, now: Instant) -> Option<MediaSnapshot> {
    if player.title.is_empty() {
        return None;
    }

    let elapsed_micros = if player.playback_state.is_playing() {
        now.saturating_duration_since(player.observed_at).as_micros() as i64
    } else {
        0
    };
    let mut position_micros = player.base_position_micros.saturating_add(elapsed_micros).max(0);
    if player.length_micros > 0 {
        position_micros = position_micros.min(player.length_micros);
    }

    Some(MediaSnapshot {
        title: player.title.clone(),
        artist: player.artist.clone(),
        album_title: player.album_title.clone(),
        art_url: player.art_url.clone(),
        position_label: format_duration(position_micros),
        length_label: format_duration(player.length_micros),
        position_micros,
        length_micros: player.length_micros,
        is_playing: player.playback_state.is_playing(),
    })
}

pub fn send_media_action(action: MediaControlAction) -> Result<(), PlatformError> {
    let method_name = match action {
        MediaControlAction::Previous => "Previous",
        MediaControlAction::PlayPause => "PlayPause",
        MediaControlAction::Next => "Next",
    };
    with_control_target(|connection, target| {
        let proxy = BlockingProxy::new(connection, target.as_str(), MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
            .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;
        proxy.call_noreply(method_name, &()).map_err(|error| {
            PlatformError::new(format!("failed to send MPRIS command '{method_name}': {error}"))
        })
    })
}

pub fn seek_to_position(position_micros: i64) -> Result<(), PlatformError> {
    with_control_target(|connection, target| {
        let proxy = BlockingProxy::new(connection, target.as_str(), MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
            .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;
        let track_id = MprisCache::global()
            .and_then(|cache| cache.selected_track_id())
            .and_then(|path| zbus::zvariant::OwnedObjectPath::try_from(path).ok())
            .unwrap_or_else(|| read_track_id_for_seek(&proxy));

        proxy
            .call::<_, _, ()>("SetPosition", &(track_id, position_micros))
            .map_err(|error| PlatformError::new(format!("failed to send MPRIS SetPosition: {error}")))
    })
}

fn with_control_target<F>(operation: F) -> Result<(), PlatformError>
where
    F: Fn(&BlockingConnection, String) -> Result<(), PlatformError>,
{
    let connection = BlockingConnection::session().map_err(|error| {
        PlatformError::new(format!("failed to connect to session bus: {error}"))
    })?;

    if let Some(target) = cached_control_target(&connection) {
        match operation(&connection, target.clone()) {
            Ok(()) => return Ok(()),
            Err(error) => eprintln!("alice: cached MPRIS target {target} failed, falling back: {error:?}"),
        }
    }

    let player_names = list_player_names(&connection)?;
    if player_names.is_empty() {
        return Err(PlatformError::new("no MPRIS players are available"));
    }
    let target = choose_control_target(&connection, &player_names)?;
    operation(&connection, target)
}

fn cached_control_target(connection: &BlockingConnection) -> Option<String> {
    let target = MprisCache::global()?.selected_player_bus_name()?;
    let proxy = BlockingProxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE).ok()?;
    let has_owner: bool = proxy.call("NameHasOwner", &(target.as_str())).ok()?;
    has_owner.then_some(target)
}

fn read_track_id_for_seek(proxy: &BlockingProxy<'_>) -> zbus::zvariant::OwnedObjectPath {
    let metadata: HashMap<String, OwnedValue> = proxy.get_property("Metadata").unwrap_or_default();
    metadata
        .get("mpris:trackid")
        .and_then(|v| v.clone().try_into().ok())
        .unwrap_or_else(|| zbus::zvariant::OwnedObjectPath::try_from(NO_TRACK_PATH).unwrap())
}

fn choose_control_target(
    connection: &BlockingConnection,
    player_names: &[String],
) -> Result<String, PlatformError> {
    let mut fallback = None;

    for name in player_names {
        let proxy = BlockingProxy::new(connection, name.as_str(), MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
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

fn list_player_names(connection: &BlockingConnection) -> Result<Vec<String>, PlatformError> {
    let proxy = BlockingProxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE)
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
    connection: &BlockingConnection,
    bus_name: &str,
) -> Result<Option<MediaSnapshot>, PlatformError> {
    let proxy = BlockingProxy::new(connection, bus_name, MPRIS_PATH, MPRIS_PLAYER_INTERFACE)
        .map_err(|error| PlatformError::new(format!("failed to create MPRIS proxy: {error}")))?;

    let playback_status: String = proxy
        .get_property("PlaybackStatus")
        .map_err(|error| PlatformError::new(format!("failed to read PlaybackStatus: {error}")))?;

    let metadata: HashMap<String, OwnedValue> = proxy
        .get_property("Metadata")
        .map_err(|error| PlatformError::new(format!("failed to read Metadata: {error}")))?;

    let position_micros: i64 = proxy.get_property("Position").unwrap_or(0_i64);
    Ok(cached_player_from_parts(bus_name, playback_status, metadata, position_micros)
        .and_then(|player| project_player(&player, player.observed_at)))
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

fn metadata_object_path(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(|value| value.clone().try_into().ok())
        .map(|path: zbus::zvariant::OwnedObjectPath| path.to_string())
}

fn format_duration(microseconds: i64) -> String {
    let total_seconds = (microseconds.max(0) / 1_000_000) as u64;
    let minutes = total_seconds / 60;
    let seconds = total_seconds % 60;
    format!("{minutes}:{seconds:02}")
}

#[cfg(test)]
mod tests {
    use super::{
        CachedMprisMediaProvider, CachedMprisPlayer, MediaControlAction, MprisCache,
        PlaybackState, format_duration, project_player,
    };
    use crate::providers::MediaProvider;
    use std::time::{Duration, Instant};

    fn cached_player(bus_name: &str, title: &str, playback_state: PlaybackState) -> CachedMprisPlayer {
        CachedMprisPlayer {
            bus_name: bus_name.into(),
            title: title.into(),
            artist: "Artist".into(),
            album_title: "Album".into(),
            art_url: "".into(),
            playback_state,
            track_id: "/track/1".into(),
            base_position_micros: 1_000_000,
            observed_at: Instant::now(),
            length_micros: 10_000_000,
        }
    }

    #[test]
    fn formats_microseconds_as_clock_label() {
        assert_eq!(format_duration(0), "0:00");
        assert_eq!(format_duration(26_000_000), "0:26");
        assert_eq!(format_duration(130_000_000), "2:10");
    }

    #[test]
    fn projection_advances_playing_position() {
        let mut player = cached_player("org.mpris.MediaPlayer2.one", "Song", PlaybackState::Playing);
        player.observed_at = Instant::now() - Duration::from_secs(2);
        let snapshot = project_player(&player, Instant::now()).unwrap();
        assert!(snapshot.position_micros >= 3_000_000);
        assert_eq!(snapshot.position_label, "0:03");
        assert!(snapshot.is_playing);
    }

    #[test]
    fn projection_keeps_paused_position_stable() {
        let mut player = cached_player("org.mpris.MediaPlayer2.one", "Song", PlaybackState::Paused);
        player.observed_at = Instant::now() - Duration::from_secs(2);
        let snapshot = project_player(&player, Instant::now()).unwrap();
        assert_eq!(snapshot.position_micros, 1_000_000);
        assert_eq!(snapshot.position_label, "0:01");
        assert!(!snapshot.is_playing);
    }

    #[test]
    fn projection_filters_empty_titles() {
        let player = cached_player("org.mpris.MediaPlayer2.one", "", PlaybackState::Playing);
        assert!(project_player(&player, Instant::now()).is_none());
    }

    #[test]
    fn cache_prefers_playing_player_over_first_fallback() {
        let cache = MprisCache::new();
        cache.upsert_player(cached_player("org.mpris.MediaPlayer2.first", "Paused", PlaybackState::Paused));
        cache.upsert_player(cached_player("org.mpris.MediaPlayer2.second", "Playing", PlaybackState::Playing));
        let snapshot = cache.project().unwrap();
        assert_eq!(snapshot.title, "Playing");
        assert_eq!(cache.selected_player_bus_name().as_deref(), Some("org.mpris.MediaPlayer2.second"));
    }

    #[test]
    fn cached_provider_reads_without_dbus() {
        let cache = MprisCache::new();
        cache.upsert_player(cached_player("org.mpris.MediaPlayer2.one", "Song", PlaybackState::Paused));
        let provider = CachedMprisMediaProvider::new(cache);
        let snapshot = provider.read_media().unwrap().unwrap();
        assert_eq!(snapshot.title, "Song");
        assert_eq!(snapshot.position_micros, 1_000_000);
    }

    #[test]
    fn media_control_action_variants_exist() {
        let _ = MediaControlAction::Previous;
        let _ = MediaControlAction::PlayPause;
        let _ = MediaControlAction::Next;
    }
}
