cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_program(FRB_CODEGEN_EXECUTABLE flutter_rust_bridge_codegen REQUIRED)

set(FRB_CODEGEN_INPUTS
  "${CMAKE_SOURCE_DIR}/../native/alice_platform/src/api.rs"
  "${CMAKE_SOURCE_DIR}/../native/alice_platform/src/state.rs"
  "${CMAKE_SOURCE_DIR}/../native/alice_platform/src/config.rs"
  "${CMAKE_SOURCE_DIR}/../flutter_rust_bridge.yaml"
)
set(FRB_GENERATED_DART
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/api.dart"
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/config.dart"
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/frb_generated.dart"
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/frb_generated.io.dart"
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/frb_generated.web.dart"
  "${CMAKE_SOURCE_DIR}/../lib/rust_gen/state.dart"
)
set(FRB_GENERATED_RUST
  "${CMAKE_SOURCE_DIR}/../native/alice_platform/src/frb_generated.rs"
  "${CMAKE_SOURCE_DIR}/../linux/runner/frb_generated.h"
)

add_custom_command(
  OUTPUT ${FRB_GENERATED_DART} ${FRB_GENERATED_RUST}
  COMMAND ${FRB_CODEGEN_EXECUTABLE} generate
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/.."
  DEPENDS ${FRB_CODEGEN_INPUTS}
  COMMENT "Running flutter_rust_bridge codegen"
  VERBATIM
)
add_custom_target(frb_codegen ALL
  DEPENDS ${FRB_GENERATED_DART} ${FRB_GENERATED_RUST}
)

set(ALICE_NATIVE_DIR "${CMAKE_SOURCE_DIR}/../native")
set(ALICE_TARGET_DIR "${ALICE_NATIVE_DIR}/target/$<IF:$<CONFIG:Debug>,debug,release>")
set(ALICE_PLATFORM_LIB "${ALICE_TARGET_DIR}/libalice_platform.a")
set(ALICE_LAYER_SHELL_LIB "${ALICE_TARGET_DIR}/libalice_layer_shell.a")

set(ALICE_CARGO_BUILD_ARGS build --manifest-path "${ALICE_NATIVE_DIR}/Cargo.toml")
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  list(APPEND ALICE_CARGO_BUILD_ARGS --release)
endif()

add_custom_command(
  OUTPUT "${ALICE_PLATFORM_LIB}" "${ALICE_LAYER_SHELL_LIB}"
  COMMAND ${CARGO_EXECUTABLE} ${ALICE_CARGO_BUILD_ARGS} --package alice_platform --package alice_layer_shell
  WORKING_DIRECTORY "${ALICE_NATIVE_DIR}"
  COMMENT "Building Alice Rust native libraries"
  VERBATIM
)

add_custom_target(alice_rust_native ALL DEPENDS "${ALICE_PLATFORM_LIB}" "${ALICE_LAYER_SHELL_LIB}")
add_dependencies(alice_rust_native frb_codegen)

add_executable(${BINARY_NAME}
  "main.cc"
  "alice_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

add_dependencies(${BINARY_NAME} alice_rust_native)

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK_LAYER_SHELL)
target_link_libraries(${BINARY_NAME} PRIVATE "${ALICE_PLATFORM_LIB}")
target_link_libraries(${BINARY_NAME} PRIVATE "${ALICE_LAYER_SHELL_LIB}")

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Export statically-linked Rust symbols to the dynamic symbol table so that
# DynamicLibrary.process() / dlsym() can find flutter_rust_bridge entry points.
target_link_options(${BINARY_NAME} PRIVATE -Wl,--export-dynamic)
