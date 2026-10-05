use super::*;
use std::{
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    time::Duration,
};

struct MutableItem {
    title: Arc<Mutex<String>>,
    icon: Arc<Mutex<String>>,
    status: Arc<Mutex<String>>,
}
#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl MutableItem {
    #[zbus(property)]
    fn id(&self) -> &str {
        "lifecycle"
    }
    #[zbus(property)]
    fn title(&self) -> String {
        self.title.lock().unwrap().clone()
    }
    #[zbus(property)]
    fn icon_name(&self) -> String {
        self.icon.lock().unwrap().clone()
    }
    #[zbus(property)]
    fn status(&self) -> String {
        self.status.lock().unwrap().clone()
    }
}
async fn wait_for(phase: &str, mut condition: impl FnMut() -> bool) {
    tokio::time::timeout(Duration::from_secs(8), async {
        while !condition() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .unwrap_or_else(|_| panic!("tray runtime failed to converge: {phase}"));
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn runtime_refreshes_artwork_properties_and_removes_lost_owner() {
    let mut daemon = Command::new("dbus-daemon")
        .args(["--session", "--nofork", "--print-address=1"])
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    struct Cleanup(std::process::Child);
    impl Drop for Cleanup {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    let mut address = String::new();
    BufReader::new(daemon.stdout.take().unwrap())
        .read_line(&mut address)
        .unwrap();
    let _cleanup = Cleanup(daemon);
    let address = address.trim();
    let publisher = zbus::connection::Builder::address(address)
        .unwrap()
        .build()
        .await
        .unwrap();
    let host = zbus::connection::Builder::address(address)
        .unwrap()
        .build()
        .await
        .unwrap();
    let directory = tempfile::tempdir().unwrap();
    let artwork = directory.path().join("late.png");
    let title = Arc::new(Mutex::new("Initial".into()));
    let icon = Arc::new(Mutex::new(artwork.to_str().unwrap().into()));
    let status = Arc::new(Mutex::new("Active".into()));
    publisher
        .object_server()
        .at(
            DEFAULT_ITEM_PATH,
            MutableItem {
                title: title.clone(),
                icon,
                status: status.clone(),
            },
        )
        .await
        .unwrap();
    publisher
        .request_name("org.kde.StatusNotifierItem.lifecycle")
        .await
        .unwrap();
    let (trigger, mut triggers) = mpsc::channel(32);
    let runtime = tokio::spawn(async move {
        let result = item_runtime::run_on_connection(host, trigger).await;
        assert!(result.is_ok(), "tray runtime stopped: {result:?}");
        result
    });
    struct Stop(tokio::task::JoinHandle<zbus::Result<()>>);
    impl Drop for Stop {
        fn drop(&mut self) {
            self.0.abort();
        }
    }
    let _stop = Stop(runtime);
    let current = || item_runtime::cached_snapshots().unwrap_or_default();
    wait_for("initial snapshot", || {
        current()
            .first()
            .is_some_and(|item| item.label == "Initial")
    })
    .await;
    assert!(current()[0].icon_png_bytes.is_none());
    // Missing artwork is retried without a publisher event or re-registration.
    image::RgbaImage::from_pixel(64, 64, image::Rgba([10, 20, 30, 255]))
        .save(&artwork)
        .unwrap();
    wait_for("missing artwork retry", || {
        current()
            .first()
            .is_some_and(|item| item.icon_png_bytes.is_some())
    })
    .await;
    let original = current()[0].icon_png_bytes.clone();
    *title.lock().unwrap() = "Updated".into();
    for _ in 0..8 {
        publisher
            .emit_signal(
                None::<&str>,
                DEFAULT_ITEM_PATH,
                ITEM_INTERFACE_KDE,
                "NewTitle",
                &(),
            )
            .await
            .unwrap();
    }
    wait_for("title update", || {
        current()
            .first()
            .is_some_and(|item| item.label == "Updated")
    })
    .await;
    assert_eq!(current()[0].icon_png_bytes, original);
    image::RgbaImage::from_pixel(64, 64, image::Rgba([200, 100, 50, 255]))
        .save(&artwork)
        .unwrap();
    *status.lock().unwrap() = "NeedsAttention".into();
    publisher
        .emit_signal(
            None::<&str>,
            DEFAULT_ITEM_PATH,
            ITEM_INTERFACE_KDE,
            "NewStatus",
            &("NeedsAttention",),
        )
        .await
        .unwrap();
    wait_for("status and artwork update", || {
        current()
            .first()
            .is_some_and(|item| item.icon_png_bytes != original)
    })
    .await;
    publisher
        .release_name("org.kde.StatusNotifierItem.lifecycle")
        .await
        .unwrap();
    wait_for("owner removal", || current().is_empty()).await;
    // Removal also publishes a fresh snapshot rather than relying on a stats tick.
    assert!(triggers.try_recv().is_ok());
}
