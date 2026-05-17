## ADDED Requirements

### Requirement: Hermetic configuration testability
Alice SHALL support configuration tests that exercise default creation, existing-file parsing, and fallback behavior through explicit test-controlled paths or in-memory YAML.

#### Scenario: Tests load from an explicit path
- **WHEN** tests need to verify config file creation or parsing
- **THEN** they SHALL use a temporary explicit config path
- **AND** they SHALL NOT read or assert against the developer's real Alice config file

#### Scenario: Tests parse YAML in memory
- **WHEN** tests need to verify defaults, invalid-value fallback, optional sections, or typed configuration mapping
- **THEN** they SHALL parse controlled YAML input in memory where possible
- **AND** they SHALL NOT require environment variables to point at a particular real config directory
