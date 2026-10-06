//! Best-effort native notification audio, independent of UI projections.

use crate::config::NotificationSoundConfig;
use std::{
    fs::File,
    io::{BufReader, Cursor},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, SyncSender},
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

pub(crate) const BUNDLED_CHIME: &[u8] = include_bytes!("../../../assets/sounds/notification.wav");

static POLICY: std::sync::OnceLock<Arc<SoundPolicy>> = std::sync::OnceLock::new();

pub(crate) struct SoundPolicy {
    config: NotificationSoundConfig,
    requests: std::sync::Weak<dyn SoundRequest>,
}
impl SoundPolicy {
    pub(crate) fn new(config: NotificationSoundConfig, requests: &Arc<dyn SoundRequest>) -> Self {
        Self {
            config,
            requests: Arc::downgrade(requests),
        }
    }
    pub(crate) fn admitted(&self, is_new: bool, suppressed: bool) {
        if is_new
            && !suppressed
            && self.config.enable
            && self.config.volume > 0
            && let Some(requests) = self.requests.upgrade()
        {
            requests.request();
        }
    }
}
pub(crate) fn current_policy() -> Option<Arc<SoundPolicy>> {
    POLICY.get().cloned()
}

pub(crate) trait SoundRequest: Send + Sync {
    fn request(&self);
}

struct Diagnostics(std::sync::Mutex<Option<Instant>>);
impl Diagnostics {
    fn report(&self, error: &str) {
        if let Ok(mut last) = self.0.lock()
            && last.is_none_or(|time| time.elapsed() >= Duration::from_secs(30))
        {
            eprintln!("alice: notification sound: {error}");
            *last = Some(Instant::now());
        }
    }
}

struct RequestHandle {
    queue: SyncSender<()>,
    diagnostics: Arc<Diagnostics>,
}
impl SoundRequest for RequestHandle {
    fn request(&self) {
        if let Err(error) = self.queue.try_send(()) {
            self.diagnostics.report(&error.to_string());
        }
    }
}

fn gain(config: &NotificationSoundConfig) -> f32 {
    f32::from(config.volume) / 100.0
}

type DecodedSound = Box<dyn rodio::Source<Item = i16> + Send>;

fn decode(config: &NotificationSoundConfig) -> Result<DecodedSound, String> {
    if let Some(path) = &config.file {
        let file = File::open(path).map_err(|e| e.to_string())?;
        Ok(Box::new(
            rodio::Decoder::new(BufReader::new(file)).map_err(|e| e.to_string())?,
        ))
    } else {
        Ok(Box::new(
            rodio::Decoder::new(Cursor::new(BUNDLED_CHIME)).map_err(|e| e.to_string())?,
        ))
    }
}

trait Backend {
    fn play(&mut self, source: DecodedSound, gain: f32, stop: &AtomicBool) -> Result<(), String>;
}

struct RodioBackend {
    // Keep the stream alive for the entire worker lifetime.
    _stream: rodio::OutputStream,
    handle: rodio::OutputStreamHandle,
}
impl RodioBackend {
    fn new() -> Result<Self, String> {
        let (stream, handle) = rodio::OutputStream::try_default().map_err(|e| e.to_string())?;
        Ok(Self {
            _stream: stream,
            handle,
        })
    }
}
impl Backend for RodioBackend {
    fn play(&mut self, source: DecodedSound, gain: f32, stop: &AtomicBool) -> Result<(), String> {
        let sink = rodio::Sink::try_new(&self.handle).map_err(|e| e.to_string())?;
        sink.set_volume(gain);
        sink.append(source);
        while !sink.empty() && !stop.load(Ordering::Acquire) {
            thread::sleep(Duration::from_millis(20));
        }
        sink.stop();
        Ok(())
    }
}

/// Runtime-owned worker. Dropping it interrupts playback and releases output.
pub(crate) struct AudioWorker {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
    pub(crate) requests: Arc<dyn SoundRequest>,
    #[cfg(test)]
    diagnostics: Arc<Diagnostics>,
}
impl AudioWorker {
    pub(crate) fn start(config: NotificationSoundConfig) -> std::io::Result<Self> {
        let worker = Self::start_with(config.clone(), RodioBackend::new)?;
        let _ = POLICY.set(Arc::new(SoundPolicy::new(config, &worker.requests)));
        Ok(worker)
    }

    fn start_with<B: Backend + 'static>(
        config: NotificationSoundConfig,
        initialize: impl FnOnce() -> Result<B, String> + Send + 'static,
    ) -> std::io::Result<Self> {
        let (queue, receiver) = mpsc::sync_channel(4);
        let stop = Arc::new(AtomicBool::new(false));
        let diagnostics = Arc::new(Diagnostics(std::sync::Mutex::new(None)));
        let requests = Arc::new(RequestHandle {
            queue,
            diagnostics: diagnostics.clone(),
        });
        #[cfg(test)]
        let test_diagnostics = diagnostics.clone();
        let worker_stop = stop.clone();
        let thread = thread::Builder::new()
            .name("notification-audio".into())
            .spawn(move || {
                if !config.enable || config.volume == 0 {
                    return;
                }
                let mut backend = match initialize() {
                    Ok(backend) => backend,
                    Err(error) => {
                        diagnostics.report(&error);
                        return;
                    }
                };
                while !worker_stop.load(Ordering::Acquire) {
                    match receiver.recv_timeout(Duration::from_millis(20)) {
                        Ok(()) => {
                            if let Err(error) = decode(&config).and_then(|source| {
                                backend.play(source, gain(&config), &worker_stop)
                            }) {
                                diagnostics.report(&error);
                            }
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {}
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    }
                }
            })?;
        Ok(Self {
            stop,
            thread: Some(thread),
            requests,
            #[cfg(test)]
            diagnostics: test_diagnostics,
        })
    }
}
impl Drop for AudioWorker {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct FakeBackend {
        played: mpsc::Sender<(f32, Vec<i16>)>,
        dropped: Arc<AtomicBool>,
        fail: bool,
    }
    impl Backend for FakeBackend {
        fn play(&mut self, source: DecodedSound, gain: f32, _: &AtomicBool) -> Result<(), String> {
            self.played.send((gain, source.collect())).unwrap();
            if self.fail {
                Err("fake decode failure".into())
            } else {
                Ok(())
            }
        }
    }
    impl Drop for FakeBackend {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::Release);
        }
    }

    #[test]
    fn selection_volume_failures_and_cleanup() {
        let custom = tempfile::NamedTempFile::new().unwrap();
        let mut bytes = BUNDLED_CHIME.to_vec();
        // Change a sample so selecting custom bytes is observable at the fake output.
        bytes[44..46].copy_from_slice(&1234_i16.to_le_bytes());
        std::fs::write(custom.path(), bytes).unwrap();
        for file in [None, Some(custom.path().to_str().unwrap().into())] {
            let config = NotificationSoundConfig {
                enable: true,
                file,
                volume: 75,
            };
            let expected = decode(&config).unwrap().collect::<Vec<_>>();
            assert_eq!(expected[0], if config.file.is_some() { 1234 } else { 0 });
            let (played, received) = mpsc::channel();
            let dropped = Arc::new(AtomicBool::new(false));
            let flag = dropped.clone();
            let worker = AudioWorker::start_with(config, move || {
                Ok(FakeBackend {
                    played,
                    dropped: flag,
                    fail: true,
                })
            })
            .unwrap();
            for _ in 0..2 {
                worker.requests.request();
                assert_eq!(
                    received.recv_timeout(Duration::from_secs(1)).unwrap(),
                    (0.75, expected.clone())
                );
            }
            drop(worker);
            assert!(dropped.load(Ordering::Acquire));
        }
    }

    #[test]
    fn initialization_failure_and_queue_saturation_are_nonblocking() {
        let (ready_tx, ready_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let worker =
            AudioWorker::start_with::<FakeBackend>(NotificationSoundConfig::default(), move || {
                ready_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Err("no output".into())
            })
            .unwrap();
        ready_rx.recv_timeout(Duration::from_secs(1)).unwrap();
        for _ in 0..100 {
            worker.requests.request();
        }
        release_tx.send(()).unwrap();
        drop(worker);
    }

    #[test]
    fn gain_and_receipt_policy() {
        struct Recorder(std::sync::atomic::AtomicUsize);
        impl SoundRequest for Recorder {
            fn request(&self) {
                self.0.fetch_add(1, Ordering::SeqCst);
            }
        }
        let recorder = Arc::new(Recorder(std::sync::atomic::AtomicUsize::new(0)));
        let requests: Arc<dyn SoundRequest> = recorder.clone();
        let mut policy = SoundPolicy {
            config: NotificationSoundConfig::default(),
            requests: Arc::downgrade(&requests),
        };
        assert_eq!(gain(&policy.config), 0.5);
        policy.admitted(true, false); // external or internal new receipt
        policy.admitted(false, false); // retained replacement
        policy.admitted(true, true); // sender suppression
        assert_eq!(recorder.0.load(Ordering::SeqCst), 1);
        policy.config.enable = false;
        policy.admitted(true, false);
        policy.config.enable = true;
        policy.config.volume = 0;
        assert_eq!(gain(&policy.config), 0.0);
        policy.admitted(true, false);
        assert_eq!(recorder.0.load(Ordering::SeqCst), 1);
        drop(requests);
        drop(recorder);
        policy.config.volume = 100;
        policy.admitted(true, false); // worker unavailable remains best-effort
    }

    #[test]
    fn custom_file_failures_never_reach_output_or_fall_back() {
        let directory = tempfile::tempdir().unwrap();
        for exists in [false, true] {
            let path = directory.path().join("custom.wav");
            if exists {
                std::fs::write(&path, b"invalid audio").unwrap();
            }
            let (played, received) = mpsc::channel();
            let worker = AudioWorker::start_with(
                NotificationSoundConfig {
                    file: Some(path.to_str().unwrap().into()),
                    ..Default::default()
                },
                move || {
                    Ok(FakeBackend {
                        played,
                        dropped: Arc::new(AtomicBool::new(false)),
                        fail: false,
                    })
                },
            )
            .unwrap();
            worker.requests.request();
            let deadline = Instant::now() + Duration::from_secs(1);
            while worker.diagnostics.0.lock().unwrap().is_none() {
                assert!(Instant::now() < deadline, "failure was not diagnosed");
                thread::sleep(Duration::from_millis(1));
            }
            assert!(received.try_recv().is_err());
            drop(worker);
        }
    }

    #[test]
    fn saturated_queue_discards_requests_and_rate_limits_diagnostics() {
        let (queue, receiver) = mpsc::sync_channel(4);
        let diagnostics = Arc::new(Diagnostics(std::sync::Mutex::new(None)));
        let handle = RequestHandle {
            queue,
            diagnostics: diagnostics.clone(),
        };
        for _ in 0..100 {
            handle.request();
        }
        assert_eq!(receiver.try_iter().count(), 4);
        let first = *diagnostics.0.lock().unwrap();
        assert!(first.is_some());
        diagnostics.report("another failure");
        assert_eq!(*diagnostics.0.lock().unwrap(), first);
    }

    #[test]
    fn shutdown_interrupts_active_playback() {
        struct BlockingBackend(mpsc::Sender<()>);
        impl Backend for BlockingBackend {
            fn play(&mut self, _: DecodedSound, _: f32, stop: &AtomicBool) -> Result<(), String> {
                self.0.send(()).unwrap();
                while !stop.load(Ordering::Acquire) {
                    thread::sleep(Duration::from_millis(1));
                }
                Ok(())
            }
        }
        let (started, received) = mpsc::channel();
        let worker = AudioWorker::start_with(NotificationSoundConfig::default(), move || {
            Ok(BlockingBackend(started))
        })
        .unwrap();
        worker.requests.request();
        received.recv_timeout(Duration::from_secs(1)).unwrap();
        drop(worker);
    }

    #[test]
    fn bundled_wav_decodes() {
        let source = rodio::Decoder::new(Cursor::new(BUNDLED_CHIME)).unwrap();
        assert!(source.count() > 0);
    }
}
