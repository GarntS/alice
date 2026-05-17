# Sway Workspaces Specification

## Purpose
Define current Sway IPC workspace integration and workspace focus actions.

## Requirements

### Requirement: Workspace discovery
Alice SHALL read workspaces from Sway IPC and convert them into workspace snapshots.

#### Scenario: Sway returns workspace data
- **WHEN** Alice reads workspaces from Sway
- **THEN** Alice SHALL include workspaces that have a non-empty output
- **AND** each snapshot SHALL include a numeric label, focused state, and visible state

### Requirement: Workspace event refresh
Alice SHALL subscribe to Sway workspace events to refresh the snapshot stream.

#### Scenario: Sway workspace event occurs
- **WHEN** Sway emits a workspace event on the IPC subscription
- **THEN** Alice SHALL trigger a snapshot rebuild

### Requirement: Workspace chip rendering
Alice SHALL render workspace chips with different styling for focused, visible-unfocused, and hidden workspaces.

#### Scenario: Workspace chips are displayed
- **WHEN** the bar renders workspace snapshots
- **THEN** focused workspaces SHALL use the primary color
- **AND** visible-unfocused workspaces SHALL use the secondary color
- **AND** hidden workspaces SHALL use transparent background with an outline

### Requirement: Workspace focus action
Alice SHALL focus a workspace through Sway IPC when its chip is clicked.

#### Scenario: Numeric workspace label is clicked
- **WHEN** a numeric workspace label is requested
- **THEN** Alice SHALL run `workspace <label>` through Sway IPC

#### Scenario: Non-numeric workspace label is clicked
- **WHEN** a non-numeric workspace label is requested
- **THEN** Alice SHALL quote and escape the label before running the Sway workspace command
