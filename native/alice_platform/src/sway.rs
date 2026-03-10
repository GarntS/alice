use swayipc::{Connection, Fallible};

use crate::{PlatformError, providers::WorkspaceProvider, state::WorkspaceSnapshot};

pub struct SwayWorkspaceProvider;

impl SwayWorkspaceProvider {
    pub fn new() -> Self {
        Self
    }

    fn read_from_connection(connection: &mut Connection) -> Fallible<Vec<WorkspaceSnapshot>> {
        let workspaces = connection.get_workspaces()?;
        Ok(workspaces
            .into_iter()
            .filter(|workspace| !workspace.output.is_empty())
            .map(|workspace| WorkspaceSnapshot {
                label: workspace.num.to_string(),
                is_focused: workspace.focused,
                is_visible: workspace.visible,
            })
            .collect())
    }
}

impl WorkspaceProvider for SwayWorkspaceProvider {
    fn read_workspaces(&self) -> Result<Vec<WorkspaceSnapshot>, PlatformError> {
        let mut connection = Connection::new().map_err(|error| {
            PlatformError::new(format!("failed to connect to sway IPC: {error}"))
        })?;
        Self::read_from_connection(&mut connection)
            .map_err(|error| PlatformError::new(format!("failed to read sway workspaces: {error}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn provider_can_be_constructed() {
        let _provider = SwayWorkspaceProvider::new();
    }
}
