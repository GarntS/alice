//! Bounded, typed adapter for com.canonical.dbusmenu.
use crate::PlatformError;
use std::collections::{HashMap, HashSet};
use zbus::zvariant::OwnedValue;

const MAX_DEPTH: usize = 16;
const MAX_NODES: usize = 1024;
const MAX_LABEL_BYTES: usize = 4096;
pub(super) type RawNode = (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TrayMenuToggle {
    None,
    Check,
    Radio,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrayMenuNode {
    pub id: i32,
    pub label: String,
    pub visible: bool,
    pub enabled: bool,
    pub separator: bool,
    pub submenu: bool,
    pub toggle: TrayMenuToggle,
    /// -1: indeterminate, 0: off, 1: on.
    pub toggle_state: i32,
    pub children: Vec<TrayMenuNode>,
}

fn malformed(property: &str) -> PlatformError {
    PlatformError::new(format!("malformed D-Bus menu property: {property}"))
}
fn text(
    properties: &HashMap<String, OwnedValue>,
    key: &str,
    default: &str,
) -> Result<String, PlatformError> {
    match properties.get(key) {
        None => Ok(default.to_owned()),
        Some(value) => <&str>::try_from(value)
            .map(str::to_owned)
            .map_err(|_| malformed(key)),
    }
}
fn boolean(properties: &HashMap<String, OwnedValue>, key: &str) -> Result<bool, PlatformError> {
    properties
        .get(key)
        .map(|value| bool::try_from(value).map_err(|_| malformed(key)))
        .unwrap_or(Ok(true))
}

pub(super) fn parse_layout(root: RawNode) -> Result<TrayMenuNode, PlatformError> {
    fn parse(
        raw: RawNode,
        depth: usize,
        count: &mut usize,
        ids: &mut HashSet<i32>,
    ) -> Result<TrayMenuNode, PlatformError> {
        *count += 1;
        if depth > MAX_DEPTH || *count > MAX_NODES {
            return Err(PlatformError::new("D-Bus menu exceeds tree limits"));
        }
        let (id, properties, children) = raw;
        if id < 0 || !ids.insert(id) {
            return Err(PlatformError::new("invalid or duplicate D-Bus menu id"));
        }
        let label = text(&properties, "label", "")?;
        if label.len() > MAX_LABEL_BYTES {
            return Err(PlatformError::new("D-Bus menu label exceeds limit"));
        }
        let toggle = match text(&properties, "toggle-type", "")?.as_str() {
            "" => TrayMenuToggle::None,
            "checkmark" => TrayMenuToggle::Check,
            "radio" => TrayMenuToggle::Radio,
            _ => return Err(malformed("toggle-type")),
        };
        let toggle_state = properties
            .get("toggle-state")
            .map(|value| i32::try_from(value).map_err(|_| malformed("toggle-state")))
            .unwrap_or(Ok(-1))?;
        if !(-1..=1).contains(&toggle_state) {
            return Err(malformed("toggle-state"));
        }
        let separator = match text(&properties, "type", "standard")?.as_str() {
            "standard" => false,
            "separator" => true,
            _ => return Err(malformed("type")),
        };
        let submenu =
            !children.is_empty() || text(&properties, "children-display", "")? == "submenu";
        let visible = boolean(&properties, "visible")?;
        let enabled = boolean(&properties, "enabled")?;
        let children = children
            .into_iter()
            .map(|child| {
                let raw: RawNode = child
                    .try_into()
                    .map_err(|_| PlatformError::new("malformed D-Bus menu child"))?;
                parse(raw, depth + 1, count, ids)
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(TrayMenuNode {
            id,
            label,
            visible,
            enabled,
            separator,
            submenu,
            toggle,
            toggle_state,
            children,
        })
    }
    parse(root, 0, &mut 0, &mut HashSet::new())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn child(raw: RawNode) -> OwnedValue {
        OwnedValue::try_from(zbus::zvariant::Value::from(raw)).unwrap()
    }
    #[test]
    fn defaults_and_nested_states_are_typed() {
        let mut properties = HashMap::new();
        properties.insert(
            "label".into(),
            OwnedValue::try_from(zbus::zvariant::Value::from("_Choice")).unwrap(),
        );
        properties.insert("enabled".into(), OwnedValue::from(false));
        properties.insert(
            "toggle-type".into(),
            OwnedValue::try_from(zbus::zvariant::Value::from("radio")).unwrap(),
        );
        properties.insert("toggle-state".into(), OwnedValue::from(1i32));
        let tree = parse_layout((0, HashMap::new(), vec![child((1, properties, vec![]))])).unwrap();
        assert!(tree.visible && tree.enabled);
        let choice = &tree.children[0];
        assert_eq!(choice.label, "_Choice");
        assert!(!choice.enabled);
        assert_eq!(choice.toggle, TrayMenuToggle::Radio);
        assert_eq!(choice.toggle_state, 1);
    }
    #[test]
    fn rejects_malformed_duplicate_and_oversized_trees() {
        assert!(parse_layout((0, HashMap::new(), vec![OwnedValue::from(3i32)])).is_err());
        assert!(
            parse_layout((0, HashMap::new(), vec![child((0, HashMap::new(), vec![]))])).is_err()
        );
        let mut nested = (20, HashMap::new(), vec![]);
        for id in (0..20).rev() {
            nested = (id, HashMap::new(), vec![child(nested)]);
        }
        assert!(parse_layout(nested).is_err());
        let children = (1..=MAX_NODES as i32)
            .map(|id| child((id, HashMap::new(), vec![])))
            .collect();
        assert!(parse_layout((0, HashMap::new(), children)).is_err());
    }
    #[test]
    fn separator_and_visibility_properties_are_preserved() {
        let mut properties = HashMap::new();
        properties.insert(
            "type".into(),
            OwnedValue::try_from(zbus::zvariant::Value::from("separator")).unwrap(),
        );
        properties.insert("visible".into(), OwnedValue::from(false));
        let node = parse_layout((2, properties, vec![])).unwrap();
        assert!(node.separator);
        assert!(!node.visible);
    }
}
