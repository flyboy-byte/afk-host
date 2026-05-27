cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "pipewire_video_capture")
project(${PROJECT_NAME} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(PIPEWIRE REQUIRED IMPORTED_TARGET libpipewire-0.3)

set(PLUGIN_NAME "pipewire_video_capture_plugin")

add_library(${PLUGIN_NAME} SHARED
  "pipewire_video_capture_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::PIPEWIRE
  ${GTK_LIBRARIES}
)

target_include_directories(${PLUGIN_NAME} PRIVATE
  ${GTK_INCLUDE_DIRS}
)

set(pipewire_video_capture_bundled_libraries
  ""
  PARENT_SCOPE)
