//! Real protocol tests on a private bus; never mutate the desktop session bus.
use super::*;
use std::{
    io::{BufRead, BufReader},
    process::{Child, Command, Stdio},
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
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
            .expect("start private dbus-daemon");
        let mut address = String::new();
        BufReader::new(child.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        Self {
            child,
            address: address.trim().into(),
        }
    }
    async fn publisher(&self) -> zbus::Connection {
        zbus::connection::Builder::address(self.address.as_str())
            .unwrap()
            .build()
            .await
            .unwrap()
    }
    async fn action(
        &self,
        service: String,
        action: TrayItemAction,
        timeout: Duration,
    ) -> TrayActionOutcome {
        let address = self.address.clone();
        tokio::task::spawn_blocking(move || {
            let connection = zbus::blocking::connection::Builder::address(address.as_str())
                .unwrap()
                .method_timeout(timeout)
                .build()
                .unwrap();
            send_tray_action_on_connection(&connection, &service, DEFAULT_ITEM_PATH, action, 12, 34)
                .unwrap()
        })
        .await
        .unwrap()
    }
}
impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

struct KdeItem {
    calls: Arc<AtomicUsize>,
    fail: bool,
    delay: Duration,
    runtime: tokio::runtime::Handle,
}
#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl KdeItem {
    #[zbus(property)]
    fn id(&self) -> &str {
        "test-kde"
    }
    async fn activate(&self, x: i32, y: i32) -> zbus::fdo::Result<()> {
        assert_eq!((x, y), (12, 34));
        self.calls.fetch_add(1, Ordering::SeqCst);
        // zbus's default executor is not a Tokio reactor. Schedule the test delay
        // explicitly on the fixture's runtime rather than assuming executor context.
        let delay = self.delay;
        self.runtime
            .spawn(async move { tokio::time::sleep(delay).await })
            .await
            .unwrap();
        if self.fail {
            Err(zbus::fdo::Error::Failed("publisher rejected action".into()))
        } else {
            Ok(())
        }
    }
}
struct FreedesktopItem {
    calls: Arc<AtomicUsize>,
}
#[zbus::interface(name = "org.freedesktop.StatusNotifierItem")]
impl FreedesktopItem {
    #[zbus(property)]
    fn status(&self) -> &str {
        "Active"
    }
    fn activate(&self, x: i32, y: i32) {
        assert_eq!((x, y), (12, 34));
        self.calls.fetch_add(1, Ordering::SeqCst);
    }
}
struct UnavailableIntrospection;
#[zbus::interface(name = "org.freedesktop.DBus.Introspectable")]
impl UnavailableIntrospection {
    fn introspect(&self) -> zbus::fdo::Result<String> {
        Err(zbus::fdo::Error::NotSupported(
            "introspection disabled".into(),
        ))
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kde_and_freedesktop_publishers_are_verified() {
    let bus = Bus::start();
    for kde in [true, false] {
        let publisher = bus.publisher().await;
        let calls = Arc::new(AtomicUsize::new(0));
        if kde {
            publisher
                .object_server()
                .at(
                    DEFAULT_ITEM_PATH,
                    KdeItem {
                        calls: calls.clone(),
                        fail: false,
                        delay: Duration::ZERO,
                        runtime: tokio::runtime::Handle::current(),
                    },
                )
                .await
                .unwrap();
        } else {
            publisher
                .object_server()
                .at(
                    DEFAULT_ITEM_PATH,
                    FreedesktopItem {
                        calls: calls.clone(),
                    },
                )
                .await
                .unwrap();
        }
        let service = publisher.unique_name().unwrap().to_string();
        assert_eq!(
            bus.action(
                service.clone(),
                TrayItemAction::Activate,
                Duration::from_secs(1)
            )
            .await,
            TrayActionOutcome::Executed
        );
        assert_eq!(
            bus.action(service, TrayItemAction::ContextMenu, Duration::from_secs(1))
                .await,
            TrayActionOutcome::Unsupported
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unavailable_introspection_preserves_unknown_capabilities() {
    let bus = Bus::start();
    let publisher = bus.publisher().await;
    let calls = Arc::new(AtomicUsize::new(0));
    publisher
        .object_server()
        .at(
            DEFAULT_ITEM_PATH,
            FreedesktopItem {
                calls: calls.clone(),
            },
        )
        .await
        .unwrap();
    // Removal is keyed by interface name, including the automatically installed interface.
    publisher
        .object_server()
        .remove::<UnavailableIntrospection, _>(DEFAULT_ITEM_PATH)
        .await
        .unwrap();
    publisher
        .object_server()
        .at(DEFAULT_ITEM_PATH, UnavailableIntrospection)
        .await
        .unwrap();
    let service = publisher.unique_name().unwrap().to_string();
    assert_eq!(
        bus.action(
            service.clone(),
            TrayItemAction::Activate,
            Duration::from_secs(1)
        )
        .await,
        TrayActionOutcome::Executed
    );
    assert_eq!(
        bus.action(service, TrayItemAction::ContextMenu, Duration::from_secs(1))
            .await,
        TrayActionOutcome::Unsupported
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn remote_errors_and_timeouts_never_duplicate_actions() {
    for (fail, delay) in [(true, Duration::ZERO), (false, Duration::from_secs(1))] {
        let bus = Bus::start();
        let publisher = bus.publisher().await;
        let kde_calls = Arc::new(AtomicUsize::new(0));
        let fd_calls = Arc::new(AtomicUsize::new(0));
        publisher
            .object_server()
            .at(
                DEFAULT_ITEM_PATH,
                KdeItem {
                    calls: kde_calls.clone(),
                    fail,
                    delay,
                    runtime: tokio::runtime::Handle::current(),
                },
            )
            .await
            .unwrap();
        publisher
            .object_server()
            .at(
                DEFAULT_ITEM_PATH,
                FreedesktopItem {
                    calls: fd_calls.clone(),
                },
            )
            .await
            .unwrap();
        let outcome = bus
            .action(
                publisher.unique_name().unwrap().to_string(),
                TrayItemAction::Activate,
                Duration::from_millis(150),
            )
            .await;
        assert!(
            matches!(outcome, TrayActionOutcome::Failed { .. }),
            "{outcome:?}"
        );
        assert_eq!(kde_calls.load(Ordering::SeqCst), 1);
        assert_eq!(fd_calls.load(Ordering::SeqCst), 0);
    }
}
