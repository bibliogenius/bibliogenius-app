# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "rust_lib_app")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")

# CMAKE_SOURCE_DIR points to the Flutter app root (project root)
# This is reliable regardless of where CMake runs from during the build
# Try local dev (sibling ../bibliogenius) first, then submodule (rust_builder/bibliogenius)
if(EXISTS "${CMAKE_SOURCE_DIR}/../../bibliogenius")
    set(RUST_MANIFEST_PATH "${CMAKE_SOURCE_DIR}/../../bibliogenius")
    message(STATUS "Using local dev Rust path: ${RUST_MANIFEST_PATH}")
elseif(EXISTS "${CMAKE_SOURCE_DIR}/../rust_builder/bibliogenius")
    set(RUST_MANIFEST_PATH "${CMAKE_SOURCE_DIR}/../rust_builder/bibliogenius")
    message(STATUS "Using submodule Rust path: ${RUST_MANIFEST_PATH}")
else()
    message(FATAL_ERROR "Could not find bibliogenius Rust source. Looked in:\n  - ${CMAKE_SOURCE_DIR}/../../bibliogenius\n  - ${CMAKE_SOURCE_DIR}/../rust_builder/bibliogenius\nRun: git submodule update --init")
endif()

apply_cargokit(${PROJECT_NAME} ${RUST_MANIFEST_PATH} rust_lib_app "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(rust_lib_app_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
