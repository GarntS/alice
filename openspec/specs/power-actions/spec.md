# Power Actions Specification

## Purpose
Define the implemented power panel and configurable shell-command delegation for power actions.

## Requirements

### Requirement: Power panel actions
Alice SHALL provide a power panel with lock, lock and suspend, restart, and power off actions.

#### Scenario: Power panel is rendered
- **WHEN** the user opens the power panel
- **THEN** Alice SHALL render buttons for Lock, Lock + Suspend, Restart, and Power Off
- **AND** Power Off SHALL use destructive visual styling

### Requirement: Configured command execution
Alice SHALL execute configured power commands through `/bin/sh -c`.

#### Scenario: Valid power action is requested
- **WHEN** Flutter requests `lock`, `lockAndSuspend`, `restart`, or `poweroff`
- **THEN** Rust SHALL load the native config
- **AND** Rust SHALL select the corresponding configured shell command
- **AND** Rust SHALL spawn `/bin/sh -c <command>` when the command is non-empty

### Requirement: Unknown or empty action handling
Alice SHALL refuse unknown power actions and empty commands.

#### Scenario: Unknown action is requested
- **WHEN** Flutter requests an unrecognized power action
- **THEN** Rust SHALL return `false` for the action request

#### Scenario: Command is empty after config resolution
- **WHEN** the selected command is empty or whitespace
- **THEN** Rust SHALL not spawn a shell command
- **AND** Rust SHALL return `false`

### Requirement: Panel closure after power action
Alice SHALL close the power panel after a power action request completes on the Flutter side.

#### Scenario: Power action callback completes
- **WHEN** Flutter finishes requesting a power action
- **THEN** Alice SHALL close the current panel controller state
