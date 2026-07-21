use std::{
    env, fs,
    io::{self, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};

use super::CalDavCacheModel;

const CACHE_VERSION: u32 = 1;

#[derive(Debug, Serialize, Deserialize)]
struct CacheDocument {
    version: u32,
    state: CalDavCacheModel,
}

#[derive(Debug, PartialEq, Eq)]
pub enum CacheLoad {
    Missing,
    Loaded(CalDavCacheModel),
    Invalid,
}

pub fn default_cache_path() -> Result<PathBuf, io::Error> {
    let base = match env::var_os("XDG_CACHE_HOME") {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => PathBuf::from(
            env::var_os("HOME")
                .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "HOME is not set"))?,
        )
        .join(".cache"),
    };
    Ok(base.join("alice").join("caldav-v1.json"))
}

pub fn load_cache(path: &Path) -> Result<CacheLoad, io::Error> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(CacheLoad::Missing),
        Err(error) => return Err(error),
    };
    let document = match serde_json::from_slice::<CacheDocument>(&bytes) {
        Ok(document) if document.version == CACHE_VERSION => document,
        _ => {
            quarantine_invalid_cache(path)?;
            return Ok(CacheLoad::Invalid);
        }
    };
    Ok(CacheLoad::Loaded(document.state))
}

pub fn store_cache(path: &Path, state: &CalDavCacheModel) -> Result<(), io::Error> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "cache path has no parent"))?;
    fs::create_dir_all(parent)?;
    let bytes = serde_json::to_vec(&CacheDocument {
        version: CACHE_VERSION,
        state: state.clone(),
    })
    .map_err(io::Error::other)?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temporary = parent.join(format!(".caldav-cache-{nonce}.tmp"));

    #[cfg(unix)]
    let mut file = {
        use std::os::unix::fs::OpenOptionsExt;
        fs::OpenOptions::new()
            .create_new(true)
            .write(true)
            .mode(0o600)
            .open(&temporary)?
    };
    #[cfg(not(unix))]
    let mut file = fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temporary)?;

    let result = (|| {
        file.write_all(&bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        }
        fs::File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn quarantine_invalid_cache(path: &Path) -> Result<(), io::Error> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let quarantine = path.with_extension(format!("invalid-{nonce}"));
    match fs::rename(path, quarantine) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_round_trips_atomically_with_owner_only_mode() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("alice/caldav-v1.json");
        let mut state = CalDavCacheModel::default();
        state.sync_state.last_success_unix_secs = Some(123);
        store_cache(&path, &state).unwrap();
        let persisted = fs::read_to_string(&path).unwrap();
        assert!(!persisted.contains("authorization"));
        assert!(!persisted.contains("principal_url"));
        assert_eq!(load_cache(&path).unwrap(), CacheLoad::Loaded(state));
        assert!(
            directory
                .path()
                .join("alice")
                .read_dir()
                .unwrap()
                .all(|entry| {
                    !entry
                        .unwrap()
                        .file_name()
                        .to_string_lossy()
                        .ends_with(".tmp")
                })
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
    }

    #[test]
    fn corrupt_or_unknown_version_is_quarantined() {
        let directory = tempfile::tempdir().unwrap();
        let corrupt = directory.path().join("cache.json");
        fs::write(&corrupt, b"configured-token-must-not-be-logged{broken").unwrap();
        assert_eq!(load_cache(&corrupt).unwrap(), CacheLoad::Invalid);
        assert!(!corrupt.exists());
        assert_eq!(directory.path().read_dir().unwrap().count(), 1);

        let unknown = directory.path().join("unknown.json");
        fs::write(&unknown, br#"{"version":999,"state":{}}"#).unwrap();
        assert_eq!(load_cache(&unknown).unwrap(), CacheLoad::Invalid);
        assert!(!unknown.exists());
    }

    #[test]
    fn missing_cache_does_not_fail_startup() {
        let directory = tempfile::tempdir().unwrap();
        assert_eq!(
            load_cache(&directory.path().join("missing.json")).unwrap(),
            CacheLoad::Missing
        );
    }
}
