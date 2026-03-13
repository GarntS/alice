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

pub fn focus_workspace(label: &str) -> Result<(), PlatformError> {
    let command = workspace_command(label)?;
    let mut connection = Connection::new()
        .map_err(|error| PlatformError::new(format!("failed to connect to sway IPC: {error}")))?;
    connection
        .run_command(command)
        .map_err(|error| PlatformError::new(format!("failed to focus workspace: {error}")))?;
    Ok(())
}

fn workspace_command(label: &str) -> Result<String, PlatformError> {
    let trimmed = label.trim();
    if trimmed.is_empty() {
        return Err(PlatformError::new("workspace label is empty"));
    }

    if trimmed.chars().all(|character| character.is_ascii_digit()) {
        Ok(format!("workspace {trimmed}"))
    } else {
        let escaped = trimmed.replace('\\', "\\\\").replace('"', "\\\"");
        Ok(format!("workspace \"{escaped}\""))
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

    #[test]
    fn workspace_command_quotes_non_numeric_labels() {
        let command = workspace_command("dev space").expect("command should build");
        assert_eq!(command, "workspace \"dev space\"");
    }

    #[test]
    fn workspace_command_accepts_numeric_labels() {
        let command = workspace_command("3").expect("command should build");
        assert_eq!(command, "workspace 3");
    }
}
