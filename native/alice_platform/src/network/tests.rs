use super::*;
use rtnetlink::packet_route::{
    address::AddressMessage,
    link::{InfoKind, LinkMessage, State, Stats64},
};
use wl_nl80211::Nl80211Command;

fn link(index: u32, name: &str, kind: Option<InfoKind>, up: bool) -> LinkMessage {
    let mut link = LinkMessage::default();
    link.header.index = index;
    if up {
        link.header.flags = LinkFlags::Up;
    }
    link.attributes.push(LinkAttribute::IfName(name.into()));
    link.attributes
        .push(LinkAttribute::OperState(State::Unknown));
    if let Some(kind) = kind {
        link.attributes
            .push(LinkAttribute::LinkInfo(vec![LinkInfo::Kind(kind)]));
    }
    link
}

fn address(index: u32, address: &str) -> AddressMessage {
    let mut result = AddressMessage::default();
    result.header.index = index;
    result
        .attributes
        .push(AddressAttribute::Address(address.parse().unwrap()));
    result
}

fn wifi(ies: Vec<u8>, status: u32) -> Nl80211Message {
    Nl80211Message {
        cmd: Nl80211Command::NewScanResults,
        attributes: vec![Nl80211Attr::Bss(vec![
            Nl80211BssInfo::Status(status),
            Nl80211BssInfo::RawInformationElements(ies),
        ])],
    }
}

#[test]
fn route_observations_keep_unknown_counters_host_addresses_and_hardware_separate() {
    let mut wg = link(3, "wg0", Some(InfoKind::Wireguard), true);
    let mut stats = Stats64::default();
    stats.rx_bytes = 900;
    stats.tx_bytes = 700;
    wg.attributes.push(LinkAttribute::Stats64(stats));
    let mut host = address(3, "10.0.0.2");
    host.attributes
        .push(AddressAttribute::Local("10.0.0.1".parse().unwrap()));
    let dump = RouteDump {
        links: vec![link(1, "lo", None, true), link(2, "eth0", None, false), wg],
        addresses: vec![address(3, "fd00::1"), host],
    };
    let observed = interfaces(&dump, |name| name == "eth0");
    assert_eq!(observed.len(), 2);
    assert!(observed[0].hardware_backed);
    assert!(!observed[0].admin_up);
    assert_eq!(observed[0].rx_bytes, None);
    assert_eq!(observed[1].operational_state.as_deref(), Some("unknown"));
    assert_eq!(observed[1].preferred_address.as_deref(), Some("10.0.0.1"));
    assert!(!observed[1].addresses.contains(&"10.0.0.2".into()));
    assert_eq!(observed[1].rx_bytes, Some(900));
    let snapshot = snapshot(observed, &BTreeMap::new(), None);
    assert_eq!(snapshot.adapters.len(), 1);
    assert_eq!(snapshot.wireguard.len(), 1);
    assert_eq!(snapshot.kind, NetworkKind::Wired);
    assert!(snapshot.wireguard[0].wifi.is_none());
}

#[test]
fn precedence_includes_usable_virtual_interfaces_but_excludes_them_from_cards() {
    let dump = RouteDump {
        links: vec![
            link(2, "wlan0", None, true),
            link(3, "veth0", Some(InfoKind::Veth), true),
        ],
        addresses: vec![address(2, "fd00::1"), address(3, "10.0.0.1")],
    };
    let mut observed = interfaces(&dump, |_| false);
    let wifi = BTreeMap::from([(2, association(&[wifi(vec![0, 3, b'a', b'b', b'c'], 1)]))]);
    let s = snapshot(observed.clone(), &wifi, None);
    assert_eq!(s.kind, NetworkKind::Wifi);
    assert_eq!(s.adapters.len(), 1);
    assert_eq!(s.adapters[0].preferred_address.as_deref(), Some("fd00::1"));
    observed[0].admin_up = false;
    assert_eq!(
        snapshot(observed.clone(), &wifi, None).kind,
        NetworkKind::Wired
    );
    observed[1].admin_up = false;
    assert_eq!(
        snapshot(observed.clone(), &wifi, None).kind,
        NetworkKind::WifiDisconnected
    );
    assert_eq!(
        snapshot(observed, &BTreeMap::new(), None).kind,
        NetworkKind::Disconnected
    );
}

#[test]
fn ssid_preserves_unicode_invalid_bytes_and_empty_names_and_checks_bounds() {
    assert_eq!(display_ssid(b"a\xff\xc3\xa9\xe2\x82"), "a\\xFFé\\xE2\\x82");
    assert_eq!(display_ssid(b"a\n"), "a\\x0A");
    assert_eq!(ssid_bytes(&[0, 0]), Ok(Some(vec![])));
    for ies in [vec![0], vec![0, 3, b'a'], vec![0, 33]] {
        assert!(ssid_bytes(&ies).is_err());
    }
    assert_eq!(
        association(&[wifi(vec![0, 2, b'a', 255], 1)])
            .ssid
            .as_deref(),
        Some("a\\xFF")
    );
}

#[test]
fn missing_denied_unassociated_and_associated_without_ssid_are_distinct() {
    assert_eq!(association(&[]).association, WifiAssociation::Unavailable);
    assert_eq!(
        association(&[wifi(vec![], 0)]).association,
        WifiAssociation::NotAssociated
    );
    let missing = association(&[wifi(vec![], 1)]);
    assert_eq!(missing.association, WifiAssociation::Associated);
    assert!(missing.unavailable_reason.is_some());
    assert_eq!(
        error_reason(&CollectionError::Kernel(-13)),
        "Permission denied"
    );
    let observed = interfaces(
        &RouteDump {
            links: vec![link(2, "wlan0", None, true)],
            addresses: vec![],
        },
        |_| true,
    );
    let s = snapshot(
        observed.clone(),
        &BTreeMap::new(),
        Some("Permission denied"),
    );
    assert_eq!(s.adapters.len(), 1);
    assert_eq!(
        s.adapters[0].classification_error.as_deref(),
        Some("Permission denied")
    );
    let known = BTreeMap::from([(2, missing)]);
    assert_eq!(
        snapshot(observed, &known, Some("Permission denied")).adapters[0]
            .wifi
            .as_ref()
            .unwrap()
            .association,
        WifiAssociation::Unavailable
    );
}

#[test]
fn cached_provider_is_hermetic_and_suppresses_unchanged_publications() {
    let provider = CachedNetworkProvider::default();
    assert!(!provider.set(NetworkSnapshot::default()));
    let error = NetworkSnapshot {
        error: Some("unavailable".into()),
        ..NetworkSnapshot::default()
    };
    assert!(provider.set(error.clone()));
    for _ in 0..20 {
        assert_eq!(provider.read_network().unwrap(), error);
    }
}
