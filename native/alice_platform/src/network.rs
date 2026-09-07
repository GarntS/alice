pub mod transport;

use crate::{
    PlatformError,
    providers::NetworkProvider,
    state::{
        NetworkInterfaceSnapshot, NetworkKind, NetworkSnapshot, WifiAssociation, WifiSnapshot,
    },
};
use rtnetlink::packet_route::{
    address::AddressAttribute,
    link::{LinkAttribute, LinkFlags, LinkInfo},
};
use std::{
    collections::BTreeMap,
    net::IpAddr,
    path::Path,
    sync::{Arc, Mutex},
};
use transport::{CollectionError, RouteDump};
use wl_nl80211::{Nl80211Attr, Nl80211BssInfo, Nl80211Message};

#[derive(Clone, Default)]
pub struct CachedNetworkProvider(Arc<Mutex<NetworkSnapshot>>);

impl NetworkProvider for CachedNetworkProvider {
    fn read_network(&self) -> Result<NetworkSnapshot, PlatformError> {
        Ok(self.0.lock().unwrap_or_else(|e| e.into_inner()).clone())
    }
}

impl CachedNetworkProvider {
    fn set(&self, next: NetworkSnapshot) -> bool {
        let mut current = self.0.lock().unwrap_or_else(|e| e.into_inner());
        if *current == next {
            return false;
        }
        *current = next;
        true
    }
}

type WifiDump = BTreeMap<u32, WifiSnapshot>;

fn unavailable(reason: impl Into<String>) -> WifiSnapshot {
    WifiSnapshot {
        association: WifiAssociation::Unavailable,
        ssid: None,
        unavailable_reason: Some(reason.into()),
    }
}

fn error_reason(error: &CollectionError) -> String {
    match error {
        CollectionError::Kernel(-1 | -13) => "Permission denied".into(),
        CollectionError::Kernel(-2 | -19 | -95) => "Backend unsupported or device absent".into(),
        _ => format!("Network data unavailable: {error:?}"),
    }
}

/// Preserve valid text and escape invalid bytes and control characters. Never
/// log raw SSIDs, or let control bytes affect terminal/panel presentation.
pub fn display_ssid(mut bytes: &[u8]) -> String {
    let mut output = String::new();
    while !bytes.is_empty() {
        let (valid, invalid) = match std::str::from_utf8(bytes) {
            Ok(_) => (bytes.len(), 0),
            Err(error) => (
                error.valid_up_to(),
                error
                    .error_len()
                    .unwrap_or(bytes.len() - error.valid_up_to()),
            ),
        };
        for ch in std::str::from_utf8(&bytes[..valid])
            .expect("validated UTF-8 prefix")
            .chars()
        {
            if ch.is_control() {
                for byte in ch.to_string().bytes() {
                    output.push_str(&format!("\\x{byte:02X}"));
                }
            } else {
                output.push(ch);
            }
        }
        for byte in &bytes[valid..valid + invalid] {
            output.push_str(&format!("\\x{byte:02X}"));
        }
        bytes = &bytes[valid + invalid..];
    }
    output
}

/// Bounds-checked TLVs; do not use the library's String-based SSID parser.
fn ssid_bytes(mut ies: &[u8]) -> Result<Option<Vec<u8>>, &'static str> {
    let mut ssid = None;
    while !ies.is_empty() {
        if ies.len() < 2 {
            return Err("Truncated Wi-Fi information element");
        }
        let (id, size) = (ies[0], ies[1] as usize);
        ies = &ies[2..];
        if size > ies.len() {
            return Err("Truncated Wi-Fi information element");
        }
        if id == 0 {
            if size > 32 {
                return Err("Invalid SSID length");
            }
            if ssid.is_none() {
                ssid = Some(ies[..size].to_vec());
            }
        }
        ies = &ies[size..];
    }
    Ok(ssid)
}

fn association(rows: &[Nl80211Message]) -> WifiSnapshot {
    let bsses: Vec<_> = rows
        .iter()
        .flat_map(|row| &row.attributes)
        .filter_map(|attr| {
            if let Nl80211Attr::Bss(bss) = attr {
                Some(bss)
            } else {
                None
            }
        })
        .collect();
    if bsses.is_empty() {
        return unavailable("No cached BSS data");
    }
    // nl80211_bss_status: 1 = associated, 2 = IBSS joined. Authentication (0)
    // alone is deliberately not treated as association.
    let Some(bss) = bsses.iter().find(|bss| {
        bss.iter()
            .any(|attr| matches!(attr, Nl80211BssInfo::Status(1 | 2)))
    }) else {
        return WifiSnapshot {
            association: WifiAssociation::NotAssociated,
            ssid: None,
            unavailable_reason: None,
        };
    };
    let mut reason = "SSID absent from cached BSS".to_string();
    for attr in bss.iter() {
        let ies = match attr {
            Nl80211BssInfo::RawInformationElements(v)
            | Nl80211BssInfo::RawBeaconInformationElements(v)
            | Nl80211BssInfo::RawProbeResponseInformationElements(v) => v,
            _ => continue,
        };
        match ssid_bytes(ies) {
            Ok(Some(bytes)) => {
                return WifiSnapshot {
                    association: WifiAssociation::Associated,
                    ssid: Some(display_ssid(&bytes)),
                    unavailable_reason: None,
                };
            }
            Ok(None) => {}
            Err(error) => reason = error.into(),
        }
    }
    WifiSnapshot {
        association: WifiAssociation::Associated,
        ssid: None,
        unavailable_reason: Some(reason),
    }
}

async fn collect_wifi(handle: wl_nl80211::Nl80211Handle) -> Result<WifiDump, CollectionError> {
    let interfaces = transport::dump_wifi(handle.clone(), None).await?;
    let mut result = BTreeMap::new();
    for row in interfaces {
        for attr in row.attributes {
            if let Nl80211Attr::IfIndex(index) = attr {
                let state = match transport::dump_wifi(handle.clone(), Some(index)).await {
                    Ok(rows) => association(&rows),
                    // Device-specific permission/unsupported errors don't hide
                    // generic state or Wi-Fi classification. Transport loss must
                    // instead restart the generation and resolve the family anew.
                    Err(error @ CollectionError::Kernel(_)) => unavailable(error_reason(&error)),
                    Err(error) => return Err(error),
                };
                result.insert(index, state);
            }
        }
    }
    Ok(result)
}

fn interfaces(dump: &RouteDump, hardware: impl Fn(&str) -> bool) -> Vec<NetworkInterfaceSnapshot> {
    let mut result = Vec::new();
    for link in &dump.links {
        let name = link.attributes.iter().find_map(|attr| {
            if let LinkAttribute::IfName(name) = attr {
                Some(name.clone())
            } else {
                None
            }
        });
        let Some(name) = name else {
            continue;
        };
        if name == "lo" || link.header.flags.contains(LinkFlags::Loopback) {
            continue;
        }
        let mut iface = NetworkInterfaceSnapshot {
            index: link.header.index,
            hardware_backed: hardware(&name),
            name,
            flags: link.header.flags.bits(),
            admin_up: link.header.flags.contains(LinkFlags::Up),
            operational_state: None,
            link_kind: None,
            addresses: vec![],
            preferred_address: None,
            rx_bytes: None,
            tx_bytes: None,
            wifi: None,
            classification_error: None,
        };
        for attr in &link.attributes {
            match attr {
                LinkAttribute::OperState(state) => {
                    iface.operational_state = Some(state.to_string().to_ascii_lowercase())
                }
                LinkAttribute::LinkInfo(infos) => {
                    for info in infos {
                        if let LinkInfo::Kind(kind) = info {
                            iface.link_kind = Some(kind.to_string());
                        }
                    }
                }
                LinkAttribute::Stats64(stats) => {
                    iface.rx_bytes = Some(stats.rx_bytes);
                    iface.tx_bytes = Some(stats.tx_bytes);
                }
                _ => {}
            }
        }
        let mut ips = Vec::new();
        for addr in dump
            .addresses
            .iter()
            .filter(|addr| addr.header.index == iface.index)
        {
            // IFA_LOCAL is the host address on point-to-point links; IFA_ADDRESS
            // can be a peer and must not be substituted when LOCAL is present.
            let local = addr.attributes.iter().find_map(|attr| {
                if let AddressAttribute::Local(ip) = attr {
                    Some(*ip)
                } else {
                    None
                }
            });
            let ip = local.or_else(|| {
                addr.attributes.iter().find_map(|attr| {
                    if let AddressAttribute::Address(ip) = attr {
                        Some(*ip)
                    } else {
                        None
                    }
                })
            });
            if let Some(ip) = ip
                && !ips.contains(&ip)
            {
                ips.push(ip);
            }
        }
        iface.preferred_address = ips
            .iter()
            .find(|ip| ip.is_ipv4())
            .or_else(|| ips.first())
            .map(IpAddr::to_string);
        iface.addresses = ips.iter().map(IpAddr::to_string).collect();
        result.push(iface);
    }
    result.sort_by_key(|iface| iface.index);
    result
}

fn snapshot(
    mut interfaces: Vec<NetworkInterfaceSnapshot>,
    wifi: &WifiDump,
    wifi_error: Option<&str>,
) -> NetworkSnapshot {
    let mut result = NetworkSnapshot::default();
    let mut usable = false;
    let mut associated = false;
    let mut has_wifi = false;
    for mut iface in interfaces.drain(..) {
        let is_wireguard = iface.link_kind.as_deref() == Some("wireguard");
        if !is_wireguard {
            iface.wifi = wifi.get(&iface.index).cloned();
            if let Some(error) = wifi_error {
                if iface.wifi.is_some() {
                    iface.wifi = Some(unavailable(error));
                } else if iface.hardware_backed {
                    iface.classification_error = Some(error.into());
                }
            }
        }
        let addressed = iface.admin_up && iface.preferred_address.is_some();
        usable |= addressed;
        has_wifi |= iface.wifi.is_some();
        associated |= addressed
            && iface
                .wifi
                .as_ref()
                .is_some_and(|wifi| wifi.association == WifiAssociation::Associated);
        if is_wireguard {
            result.wireguard.push(iface);
        } else if iface.hardware_backed || iface.wifi.is_some() {
            result.adapters.push(iface);
        }
    }
    result.kind = if associated {
        NetworkKind::Wifi
    } else if usable {
        NetworkKind::Wired
    } else if has_wifi {
        NetworkKind::WifiDisconnected
    } else {
        NetworkKind::Disconnected
    };
    result
}

/// Independent supervisors ensure unavailable nl80211 never blocks route state.
/// These workers own no commands, D-Bus connections, or privileged operations.
pub async fn run_network_service(
    cache: CachedNetworkProvider,
    trigger: tokio::sync::mpsc::Sender<crate::runtime::Trigger>,
) {
    let (route_tx, mut route_rx) = tokio::sync::mpsc::channel(4);
    let (wifi_tx, mut wifi_rx) = tokio::sync::mpsc::channel(4);
    tokio::spawn(transport::supervise(
        transport::open_route,
        transport::dump_route,
        route_tx,
    ));
    tokio::spawn(transport::supervise(
        transport::open_wifi,
        collect_wifi,
        wifi_tx,
    ));
    let mut routes = Vec::new();
    let mut wifi = BTreeMap::new();
    let mut wifi_error = Some("Wi-Fi information is loading".to_string());
    let mut route_error = Some("Network information is loading".to_string());
    loop {
        tokio::select! {
            _ = trigger.closed() => break,
            update = route_rx.recv() => match update {
                Some(Ok(dump)) => {
                    routes = interfaces(&dump, |name| Path::new("/sys/class/net").join(name).join("device").exists());
                    // Discard wireless observations for interfaces no longer present.
                    wifi.retain(|index, _| routes.iter().any(|new| new.index == *index));
                    route_error = None;
                },
                Some(Err(error)) => route_error = Some(error_reason(&error)),
                None => break,
            },
            update = wifi_rx.recv() => match update {
                Some(Ok(next)) => { wifi = next; wifi_error = None; },
                Some(Err(error)) => wifi_error = Some(error_reason(&error)),
                None => break,
            },
        }
        let mut next = snapshot(routes.clone(), &wifi, wifi_error.as_deref());
        next.error = route_error.clone();
        if cache.set(next) && trigger.send(crate::runtime::Trigger::Event).await.is_err() {
            break;
        }
    }
}

#[cfg(test)]
mod tests;
