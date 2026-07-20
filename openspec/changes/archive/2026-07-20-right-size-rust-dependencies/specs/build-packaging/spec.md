## MODIFIED Requirements

### Requirement: Rust native library build
Alice SHALL build the Rust workspace native libraries as part of the Linux runner build. Direct dependency feature declarations for `alice_platform` SHALL identify features required by its own inspected code rather than selecting umbrella feature sets, while preserving the current Ring rustls provider and required HTTP protocol support.

#### Scenario: Runner target is built
- **WHEN** CMake builds the runner
- **THEN** it SHALL run Cargo for `alice_platform` and `alice_layer_shell`
- **AND** it SHALL link the resulting static libraries into the C++ runner
- **AND** it SHALL export dynamic symbols for FRB lookup through `DynamicLibrary.process`

#### Scenario: Alice platform targets are checked
- **WHEN** Cargo checks all `alice_platform` targets
- **THEN** Tokio SHALL provide multi-thread runtime, macro/select, synchronization, task, and timer support required by direct source use
- **AND** Hyper, hyper-util, and hyper-rustls SHALL provide the client and HTTP protocol support required by weather and Google Calendar/OAuth code
- **AND** rustls SHALL retain and initialize the Ring crypto provider

#### Scenario: Direct dependency graph is inspected
- **WHEN** the `alice_platform` dependency declarations are reviewed
- **THEN** Tokio and Hyper SHALL NOT use their `full` feature umbrellas without a verified direct requirement
- **AND** `ring` SHALL NOT be a direct dependency when source reaches it only through rustls
- **AND** dependency versions SHALL remain unchanged by this feature-right-sizing change
