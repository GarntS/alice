# Build and Packaging Specification

## Purpose
Define the implemented build integration across Flutter, Rust, CMake, flutter_rust_bridge, Nix, and distribution packaging.

## Requirements

### Requirement: Flutter Linux binary identity
Alice SHALL build a Linux Flutter application binary named `alicebar`.

#### Scenario: Flutter Linux build runs
- **WHEN** CMake configures the Linux runner
- **THEN** the executable target SHALL be named `alicebar`
- **AND** the GTK application id SHALL be set from the CMake `APPLICATION_ID`

### Requirement: flutter_rust_bridge integration
Alice SHALL keep generated Dart, Rust, and C bridge files in sync from the Rust API definitions when codegen is available and needed.

#### Scenario: Generated files are missing and codegen is available
- **WHEN** CMake sees `flutter_rust_bridge_codegen` and generated Dart files are absent
- **THEN** CMake SHALL run `flutter_rust_bridge_codegen generate` from the repository root
- **AND** generated files SHALL be placed under `lib/rust_gen`, `native/alice_platform/src/frb_generated.rs`, and `linux/runner/frb_generated.h`

#### Scenario: Generated files already exist
- **WHEN** generated FRB files are present
- **THEN** CMake SHALL use the pre-generated files

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

### Requirement: Nix package and dev shell
Alice SHALL provide a Nix flake with package and development shell outputs for supported Linux systems.

#### Scenario: Nix dev shell is entered
- **WHEN** `nix develop` is used
- **THEN** the shell SHALL provide Flutter, Dart, Rust, clang, CMake, Ninja, pkg-config, wayland-scanner, FRB codegen, and required GTK/Wayland libraries

#### Scenario: Nix package is built
- **WHEN** the Nix package is built
- **THEN** it SHALL use `buildFlutterApplication`, import the Rust cargo lock, link required runtime libraries, and wrap the installed executable with the needed library path

### Requirement: Distribution packaging artifacts
Alice SHALL include packaging definitions for Debian/Ubuntu, Fedora, and Arch release artifacts.

#### Scenario: Release workflow runs
- **WHEN** a GitHub release is published
- **THEN** the workflow SHALL build Debian/Ubuntu `.deb`, Fedora `.rpm`, and Arch `.pkg.tar.zst` artifacts using the repository packaging scripts/specs
- **AND** it SHALL upload built artifacts to the release
