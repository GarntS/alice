use super::*;
use std::{
    collections::HashMap,
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::Arc,
};
use zbus::zvariant::OwnedValue;

#[derive(Default)]
struct Data {
    prepared: Vec<i32>,
    clicked: Vec<(i32, String, i32, u32)>,
    hidden: bool,
}
struct Menu(Arc<Mutex<Data>>);
fn string(value: &str) -> OwnedValue {
    OwnedValue::try_from(Value::from(value)).unwrap()
}
fn variant(node: RawNode) -> OwnedValue {
    OwnedValue::try_from(Value::from(node)).unwrap()
}
#[zbus::interface(name = "com.canonical.dbusmenu")]
impl Menu {
    fn about_to_show(&self, id: i32) -> bool {
        self.0.lock().unwrap().prepared.push(id);
        true
    }
    fn get_layout(&self, parent: i32, depth: i32, properties: Vec<String>) -> (u32, RawNode) {
        assert_eq!((parent, depth), (0, -1));
        assert!(properties.is_empty());
        let hidden = self.0.lock().unwrap().hidden;
        let leaf = (
            2,
            HashMap::from([
                ("label".into(), string("Choice")),
                ("visible".into(), OwnedValue::from(!hidden)),
            ]),
            vec![],
        );
        let submenu = (
            1,
            HashMap::from([("label".into(), string("Models"))]),
            vec![variant(leaf)],
        );
        (1, (0, HashMap::new(), vec![variant(submenu)]))
    }
    fn event(&self, id: i32, event_id: String, data: OwnedValue, timestamp: u32) {
        self.0.lock().unwrap().clicked.push((
            id,
            event_id,
            i32::try_from(data).unwrap(),
            timestamp,
        ));
    }
}

struct OptionalAbsent {
    mode: Arc<Mutex<u8>>,
    runtime: tokio::runtime::Handle,
}
#[zbus::interface(name = "com.canonical.dbusmenu")]
impl OptionalAbsent {
    async fn get_layout(
        &self,
        _parent: i32,
        _depth: i32,
        _properties: Vec<String>,
    ) -> (u32, RawNode) {
        let mode = *self.mode.lock().unwrap();
        if mode == 2 {
            self.runtime
                .spawn(async { tokio::time::sleep(Duration::from_secs(2)).await })
                .await
                .unwrap();
        }
        let mut properties = HashMap::from([("label".into(), string("Entry"))]);
        if mode == 1 {
            properties.insert("enabled".into(), string("not a boolean"));
        }
        (
            2,
            (0, HashMap::new(), vec![variant((3, properties, vec![]))]),
        )
    }
}

struct SecondaryItem(Arc<Mutex<Vec<(i32, i32)>>>);
#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl SecondaryItem {
    #[zbus(property)]
    fn id(&self) -> &str {
        "secondary"
    }
    fn secondary_activate(&self, x: i32, y: i32) {
        self.0.lock().unwrap().push((x, y));
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn prepares_refreshes_validates_events_and_cancels_sessions() {
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
        .method_timeout(Duration::from_secs(1))
        .build()
        .await
        .unwrap();
    let data = Arc::new(Mutex::new(Data::default()));
    publisher
        .object_server()
        .at("/Menu", Menu(data.clone()))
        .await
        .unwrap();
    let secondary_calls = Arc::new(Mutex::new(Vec::new()));
    publisher
        .object_server()
        .at("/Item", SecondaryItem(secondary_calls.clone()))
        .await
        .unwrap();
    let owner = publisher.unique_name().unwrap().to_string();
    let source = MenuSource {
        owner: owner.clone(),
        menu_path: "/Menu".into(),
        secondary_supported: false,
    };
    let id = begin_request();
    let snapshot = load_on_connection(
        id,
        host.clone(),
        owner.clone(),
        "/Item".into(),
        source.clone(),
    )
    .await
    .unwrap();
    assert_eq!(snapshot.root.children[0].children[0].id, 2);
    assert_eq!(data.lock().unwrap().prepared, vec![0]);
    assert!(matches!(
        refresh(id, Some(1)).await.unwrap(),
        TrayMenuUpdate::Updated { .. }
    ));
    assert_eq!(data.lock().unwrap().prepared, vec![0, 1]);
    assert!(
        select(id, TrayMenuSelection::Remote { id: 1 }, 0, 0, 42)
            .await
            .is_err()
    );
    assert!(
        select(id, TrayMenuSelection::Secondary, 0, 0, 42)
            .await
            .is_err()
    );
    data.lock().unwrap().hidden = true;
    publisher
        .emit_signal(
            None::<&str>,
            "/Menu",
            INTERFACE,
            "ItemsPropertiesUpdated",
            &(
                Vec::<(i32, HashMap<String, OwnedValue>)>::new(),
                Vec::<(i32, Vec<String>)>::new(),
            ),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        loop {
            let dirty = state()
                .lock()
                .unwrap()
                .active
                .as_ref()
                .is_some_and(|session| session.dirty);
            if dirty {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    assert!(
        select(id, TrayMenuSelection::Remote { id: 2 }, 0, 0, 42)
            .await
            .is_err()
    );
    refresh(id, None).await.unwrap();
    assert!(
        select(id, TrayMenuSelection::Remote { id: 2 }, 0, 0, 42)
            .await
            .is_err()
    );
    data.lock().unwrap().hidden = false;
    refresh(id, Some(1)).await.unwrap();
    assert_eq!(
        select(id, TrayMenuSelection::Remote { id: 2 }, 0, 0, 42)
            .await
            .unwrap(),
        TrayActionOutcome::Executed
    );
    assert_eq!(
        data.lock().unwrap().clicked,
        vec![(2, "clicked".into(), 0, 42)]
    );
    assert_eq!(refresh(id, None).await.unwrap(), TrayMenuUpdate::Closed);
    assert!(
        select(id, TrayMenuSelection::Remote { id: 2 }, 0, 0, 42)
            .await
            .is_err()
    );
    let secondary_id = begin_request();
    let mut secondary_source = source.clone();
    secondary_source.secondary_supported = true;
    load_on_connection(
        secondary_id,
        host.clone(),
        owner.clone(),
        "/Item".into(),
        secondary_source,
    )
    .await
    .unwrap();
    assert_eq!(
        select(secondary_id, TrayMenuSelection::Secondary, 120, 340, 0)
            .await
            .unwrap(),
        TrayActionOutcome::Executed
    );
    assert_eq!(*secondary_calls.lock().unwrap(), vec![(120, 340)]);
    assert_eq!(
        data.lock().unwrap().clicked.len(),
        1,
        "synthetic action is not a remote Event"
    );
    let id = begin_request();
    load_on_connection(
        id,
        host.clone(),
        owner.clone(),
        "/Item".into(),
        source.clone(),
    )
    .await
    .unwrap();
    let newer = begin_request();
    cancel(id);
    assert_eq!(state().lock().unwrap().request_id, newer);
    assert!(
        load_on_connection(id, host, owner, "/Item".into(), source)
            .await
            .is_err()
    );
    cancel(newer);
    let mode = Arc::new(Mutex::new(0));
    publisher
        .object_server()
        .at(
            "/Optional",
            OptionalAbsent {
                mode: mode.clone(),
                runtime: tokio::runtime::Handle::current(),
            },
        )
        .await
        .unwrap();
    let optional_source = MenuSource {
        owner: publisher.unique_name().unwrap().to_string(),
        menu_path: "/Optional".into(),
        secondary_supported: false,
    };
    let short_host = zbus::connection::Builder::address(address)
        .unwrap()
        .method_timeout(Duration::from_millis(150))
        .build()
        .await
        .unwrap();
    let optional_id = begin_request();
    assert!(
        load_on_connection(
            optional_id,
            short_host.clone(),
            optional_source.owner.clone(),
            "/Item".into(),
            optional_source.clone()
        )
        .await
        .is_ok()
    );
    cancel(optional_id);
    for value in [1, 2] {
        *mode.lock().unwrap() = value;
        let id = begin_request();
        assert!(
            load_on_connection(
                id,
                short_host.clone(),
                optional_source.owner.clone(),
                "/Item".into(),
                optional_source.clone()
            )
            .await
            .is_err()
        );
        assert!(
            state().lock().unwrap().active.is_none(),
            "failed loads release subscriptions"
        );
    }
    *mode.lock().unwrap() = 0;
    publisher
        .request_name("org.example.TrayMenuTests")
        .await
        .unwrap();
    let id = begin_request();
    load_on_connection(
        id,
        short_host,
        "org.example.TrayMenuTests".into(),
        "/Item".into(),
        optional_source,
    )
    .await
    .unwrap();
    publisher
        .release_name("org.example.TrayMenuTests")
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while state().lock().unwrap().active.is_some() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
    assert_eq!(refresh(id, None).await.unwrap(), TrayMenuUpdate::Closed);
}
