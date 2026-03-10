use zbus::blocking::{Connection, Proxy};

use crate::{PlatformError, providers::TrayProvider, state::TrayItemSnapshot};

const DBUS_SERVICE: &str = "org.freedesktop.DBus";
const DBUS_PATH: &str = "/org/freedesktop/DBus";
const DBUS_INTERFACE: &str = "org.freedesktop.DBus";
const KDE_SNI_PREFIX: &str = "org.kde.StatusNotifierItem";
const FREEDESKTOP_SNI_PREFIX: &str = "org.freedesktop.StatusNotifierItem";

pub struct StatusNotifierTrayProvider;

impl StatusNotifierTrayProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_from_connection(
        connection: &Connection,
    ) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
        let proxy = Proxy::new(connection, DBUS_SERVICE, DBUS_PATH, DBUS_INTERFACE)
            .map_err(|error| PlatformError::new(format!("failed to create DBus proxy: {error}")))?;
        let names: Vec<String> = proxy
            .call("ListNames", &())
            .map_err(|error| PlatformError::new(format!("failed to list DBus names: {error}")))?;

        Ok(filter_status_notifier_names(&names)
            .into_iter()
            .map(|name| TrayItemSnapshot {
                id: name.clone(),
                label: simplify_status_notifier_label(&name),
            })
            .collect())
    }
}

impl TrayProvider for StatusNotifierTrayProvider {
    fn read_tray_items(&self) -> Result<Vec<TrayItemSnapshot>, PlatformError> {
        let connection = Connection::session().map_err(|error| {
            PlatformError::new(format!("failed to connect to session bus: {error}"))
        })?;
        Self::read_from_connection(&connection)
    }
}

fn filter_status_notifier_names(names: &[String]) -> Vec<String> {
    let mut filtered = names
        .iter()
        .filter(|name| name.starts_with(KDE_SNI_PREFIX) || name.starts_with(FREEDESKTOP_SNI_PREFIX))
        .cloned()
        .collect::<Vec<_>>();
    filtered.sort();
    filtered
}

fn simplify_status_notifier_label(name: &str) -> String {
    let suffix = name
        .strip_prefix(KDE_SNI_PREFIX)
        .or_else(|| name.strip_prefix(FREEDESKTOP_SNI_PREFIX))
        .unwrap_or(name)
        .trim_start_matches('.');

    if suffix.is_empty() {
        return "Tray Item".into();
    }

    suffix
        .split(['-', '.', '_'])
        .filter(|segment| !segment.is_empty())
        .map(|segment| {
            let mut chars = segment.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::{filter_status_notifier_names, simplify_status_notifier_label};

    #[test]
    fn filters_status_notifier_services() {
        let names = vec![
            "org.freedesktop.DBus".to_string(),
            "org.kde.StatusNotifierItem-1-1".to_string(),
            "org.freedesktop.StatusNotifierItem.discord".to_string(),
        ];

        let filtered = filter_status_notifier_names(&names);
        assert_eq!(filtered.len(), 2);
        assert!(filtered.contains(&"org.kde.StatusNotifierItem-1-1".to_string()));
        assert!(filtered.contains(&"org.freedesktop.StatusNotifierItem.discord".to_string()));
    }

    #[test]
    fn simplifies_service_name_to_human_label() {
        assert_eq!(
            simplify_status_notifier_label("org.freedesktop.StatusNotifierItem.discord"),
            "Discord"
        );
        assert_eq!(
            simplify_status_notifier_label("org.kde.StatusNotifierItem-nm_applet-1"),
            "Nm Applet 1"
        );
    }
}
