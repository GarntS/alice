//! Receipt regressions use a private bus and a fake playback-request recorder.
use super::*;
use crate::{
    config::AliceConfig,
    notification_sound::{SoundPolicy, SoundRequest},
};
use std::{
    io::{BufRead, BufReader},
    process::{Child, Command, Stdio},
    sync::atomic::AtomicUsize,
};

struct Bus {
    child: Child,
    address: String,
}
impl Bus {
    fn start() -> Self {
        let mut child = Command::new("dbus-daemon")
            .args(["--session", "--nofork", "--print-address=1"])
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut address = String::new();
        BufReader::new(child.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        Self {
            child,
            address: address.trim().into(),
        }
    }
    async fn connection(&self) -> Arc<zbus::Connection> {
        Arc::new(
            zbus::connection::Builder::address(self.address.as_str())
                .unwrap()
                .build()
                .await
                .unwrap(),
        )
    }
}
impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}
#[derive(Default)]
struct Recorder(AtomicUsize);
impl SoundRequest for Recorder {
    fn request(&self) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
}
impl Recorder {
    fn count(&self) -> usize {
        self.0.load(Ordering::SeqCst)
    }
}

async fn receive(
    server: &NotificationServer,
    replaces_id: u32,
    hints: HashMap<String, OwnedValue>,
) -> u32 {
    server
        .notify(
            "sender",
            replaces_id,
            "",
            "summary",
            "body",
            vec![],
            hints,
            -1,
        )
        .await
}

#[tokio::test]
async fn external_and_internal_admission_policy_and_non_receipt_activity() {
    let bus = Bus::start();
    let connection = bus.connection().await;
    // Popups have no influence on native audio eligibility.
    for popups in [false, true] {
        let config = AliceConfig::from_yaml_str(&format!(
            "notifications: {{show_notification_popup: {popups}}}"
        ))
        .unwrap();
        let recorder = Arc::new(Recorder::default());
        let requests: Arc<dyn SoundRequest> = recorder.clone();
        let sound = Arc::new(SoundPolicy::new(config.notifications.sound, &requests));
        let (trigger, mut events) = mpsc::channel(32);
        let server = NotificationServer {
            store: Arc::new(Mutex::new(NotificationStore::default())),
            trigger,
            next_id: Arc::new(AtomicU32::new(1)),
            default_timeout_ms: 5000,
            connection: connection.clone(),
            sound: Some(sound.clone()),
        };
        let first = receive(&server, 0, HashMap::new()).await;
        assert_eq!(recorder.count(), 1);
        assert!(events.try_recv().is_ok());
        assert_eq!(receive(&server, first, HashMap::new()).await, first);
        assert_eq!(recorder.count(), 1);
        assert!(events.try_recv().is_ok());
        let missing = receive(&server, 999, HashMap::new()).await;
        assert_ne!(missing, 999);
        assert_eq!(recorder.count(), 2);
        let mut hints = HashMap::new();
        hints.insert("suppress-sound".into(), OwnedValue::from(true));
        receive(&server, 0, hints).await;
        assert_eq!(recorder.count(), 2);
        for suppress in [
            OwnedValue::from(false),
            OwnedValue::try_from(Value::from("true")).unwrap(),
        ] {
            let mut hints = HashMap::new();
            hints.insert("suppress-sound".into(), suppress);
            hints.insert(
                "sound-file".into(),
                OwnedValue::try_from(Value::from("/sender/override.wav")).unwrap(),
            );
            hints.insert(
                "sound-name".into(),
                OwnedValue::try_from(Value::from("sender-theme")).unwrap(),
            );
            receive(&server, 0, hints).await;
        }
        assert_eq!(recorder.count(), 4);
        let internal = push_internal_into(
            &server.store,
            Some(&server.trigger),
            Some(&sound),
            "Calendar".into(),
            "Reminder".into(),
        )
        .unwrap();
        assert_eq!(recorder.count(), 5);
        assert_eq!(server.store.lock().unwrap().get_all().len(), 6);
        while events.try_recv().is_ok() {}
        assert!(
            push_internal_into(
                &server.store,
                Some(&server.trigger),
                Some(&sound),
                "Calendar 2".into(),
                "Reminder".into()
            )
            .is_some()
        );
        assert!(events.try_recv().is_ok());
        assert_eq!(recorder.count(), 6);
        // Snapshot refresh, read state, dismissal, and panel commands are projections,
        // not admission. Removed IDs are eligible when later sent as replacements.
        for _ in 0..3 {
            let _ = server.store.lock().unwrap().get_all();
        }
        server.store.lock().unwrap().mark_read(first);
        server.store.lock().unwrap().remove(internal);
        crate::runtime::push_panel_show(
            1,
            "notifications".into(),
            1,
            false,
            0.0,
            0.0,
            100.0,
            100.0,
        );
        crate::runtime::push_panel_hide(2, "notifications".into(), 1);
        assert_eq!(recorder.count(), 6);
        server.store.lock().unwrap().remove(first);
        assert_ne!(receive(&server, first, HashMap::new()).await, first);
        assert_eq!(recorder.count(), 7);
        server.store.lock().unwrap().remove_all();
        assert_eq!(recorder.count(), 7);
    }
}

#[tokio::test]
async fn disabled_muted_or_unavailable_output_preserves_storage_and_triggers() {
    let bus = Bus::start();
    let connection = bus.connection().await;
    for yaml in ["{enable: false}", "{volume: 0}", "{}"] {
        let config =
            AliceConfig::from_yaml_str(&format!("notifications: {{sound: {yaml}}}")).unwrap();
        let recorder = Arc::new(Recorder::default());
        let requests: Arc<dyn SoundRequest> = recorder.clone();
        let sound = Arc::new(SoundPolicy::new(config.notifications.sound, &requests));
        // Simulate an initialization failure or a stopped worker: no live output.
        drop(requests);
        let unavailable = yaml == "{}";
        let observed = if unavailable {
            None
        } else {
            Some(recorder.clone())
        };
        drop(recorder);
        let (trigger, mut events) = mpsc::channel(4);
        let server = NotificationServer {
            store: Arc::new(Mutex::new(NotificationStore::default())),
            trigger,
            next_id: Arc::new(AtomicU32::new(1)),
            default_timeout_ms: 5000,
            connection: connection.clone(),
            sound: Some(sound.clone()),
        };
        receive(&server, 0, HashMap::new()).await;
        assert!(events.try_recv().is_ok());
        push_internal_into(
            &server.store,
            Some(&server.trigger),
            Some(&sound),
            "Calendar".into(),
            "Reminder".into(),
        )
        .unwrap();
        assert!(events.try_recv().is_ok());
        assert_eq!(server.store.lock().unwrap().get_all().len(), 2);
        if let Some(recorder) = observed {
            assert_eq!(recorder.count(), 0);
        }
    }
}
