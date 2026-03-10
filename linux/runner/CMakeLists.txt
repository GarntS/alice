cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

find_program(CARGO_EXECUTABLE cargo REQUIRED)
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

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
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
