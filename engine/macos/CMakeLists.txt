# FF7Recomp for macOS: the lifted game, its runtime, FFNx and bgfx (Metal) in one app bundle.
#
# x86_64, run by Rosetta 2 on Apple silicon: the lifted code addresses guest memory at the
# game's own 32-bit addresses (RECOMP_FLAT_MEMORY), and only an x86_64 process may map the
# low 4 GB on macOS (arm64 processes must keep a 4 GB __PAGEZERO). See src/mac/.
#
#   cmake -S macos -B build/macos -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
#   cmake --build build/macos
cmake_minimum_required(VERSION 3.20)
# FF7_ARCH=arm64: native on Apple silicon, the guest's memory at an offset (FF7_OFFSET_MEMORY,
# src/host/ff7_guest_space.h) instead of at its own addresses.
set(FF7_ARCH "x86_64" CACHE STRING "x86_64 (Rosetta 2 on Apple silicon) or arm64 (native)")
set(CMAKE_OSX_ARCHITECTURES ${FF7_ARCH} CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0 CACHE STRING "" FORCE)   
if(FF7_ARCH STREQUAL "arm64")
  set(FF7_OFFSET_MEMORY ON CACHE BOOL "" FORCE)
else()
  set(FF7_OFFSET_MEMORY OFF CACHE BOOL "" FORCE)   # a build folder switched back from arm64
endif()
project(FF7RecompMac C CXX OBJC OBJCXX ASM)
get_filename_component(FF7_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-ffile-prefix-map=${FF7_ROOT}=ff7recomp>")

# Every source sees the Linux names the runtime uses (src/mac/include/mac_compat.h).
add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:SHELL:-include ${FF7_ROOT}/src/mac/include/mac_compat.h>")
include_directories(AFTER "${FF7_ROOT}/src/mac/include")

set(FF7_WITH_BGFX ON CACHE BOOL "" FORCE)
set(FF7_WITH_FFNX ON CACHE BOOL "" FORCE)
include("${FF7_ROOT}/cmake/ff7core.cmake")

# <ucontext.h> needs _XOPEN_SOURCE on macOS (_DARWIN_C_SOURCE keeps the rest visible).
set_source_files_properties("${FF7_ROOT}/src/host/ff7_crash.c" PROPERTIES COMPILE_DEFINITIONS "_XOPEN_SOURCE=700;_DARWIN_C_SOURCE")

# (NorthernCrater: the SwiftUI launcher that used to be built in here was removed.)
if(FF7_OFFSET_MEMORY)
  set(FF7_GUEST_RESERVE "")
else()
  set(FF7_GUEST_RESERVE "${FF7_ROOT}/src/mac/guest_reserve.s")
endif()
add_executable(FF7Recomp MACOSX_BUNDLE
  "${FF7_ROOT}/src/mac/ff7_mac_main.mm"
  ${FF7_GUEST_RESERVE})
target_include_directories(FF7Recomp PRIVATE "${FF7_ROOT}/src/mods")
set_source_files_properties("${FF7_ROOT}/src/mac/ff7_mac_main.mm" PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_include_directories(FF7Recomp PRIVATE "${FF7_ROOT}/src/host")
target_link_libraries(FF7Recomp PRIVATE ff7_core ffnx
  "-framework Cocoa" "-framework Metal" "-framework QuartzCore" "-framework GameController" "-framework CoreHaptics"
  "-framework AudioToolbox" "-framework CoreAudio" "-framework IOKit" "-framework AppKit")
# x86_64: non-PIE at 4 GB, with the guest's [0x10000, 0x80000000) reserved by FF7GUEST.
if(NOT FF7_OFFSET_MEMORY)
  target_link_options(FF7Recomp PRIVATE
    "LINKER:-no_pie"
    "LINKER:-pagezero_size,0x10000"
    "LINKER:-image_base,0x100000000"
    "LINKER:-segaddr,FF7GUEST,0x10000"
    "LINKER:-segprot,FF7GUEST,rw,rw")
endif()
set_target_properties(FF7Recomp PROPERTIES
  OUTPUT_NAME "NorthernCrater Engine"
  MACOSX_BUNDLE_BUNDLE_NAME "NorthernCrater Engine"
  MACOSX_BUNDLE_COPYRIGHT "Based on GJ Materia by Good JOE and FF7Recomp. GPL v3."
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.northerncrater.engine"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1"
  MACOSX_BUNDLE_BUNDLE_VERSION "1")

# The game folder's run-time files, inside the app (the launcher installs them into the game
# folder: src/mac/launcher/GameFiles.swift): FFNx's settings and data tables, the Metal shaders
# (tools/compile_shaders_mac.sh), the NTSC-J LUTs. Plus which exe this app was lifted from (its
# SHA-1: the launcher only imports that exe) and where this source tree is (re-lifts for mods).
file(SHA1 "${FF7_ROOT}/game/ff7_en.exe" FF7_EXE_SHA1)
file(WRITE "${CMAKE_BINARY_DIR}/ff7_en.sha1" "${FF7_EXE_SHA1}\n")
file(WRITE "${CMAKE_BINARY_DIR}/source-tree.txt" "${FF7_ROOT}\n")
set(FF7_RES "$<TARGET_BUNDLE_CONTENT_DIR:FF7Recomp>/Resources")
file(GLOB FF7_FFNX_TOMLS "${FF7_ROOT}/external/FFNx/misc/FFNx*.toml")
file(GLOB FF7_LUTS "${FF7_ROOT}/external/FFNx/misc/glut_*.png")
add_custom_command(TARGET FF7Recomp POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${FF7_RES}/ffnx/shaders"
  COMMAND ${CMAKE_COMMAND} -E copy ${FF7_FFNX_TOMLS} "${FF7_RES}/ffnx/"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${FF7_ROOT}/build/shaders-mtl" "${FF7_RES}/ffnx/shaders"
  COMMAND ${CMAKE_COMMAND} -E copy ${FF7_LUTS} "${FF7_RES}/ffnx/shaders/"
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/ff7_en.sha1" "${CMAKE_BINARY_DIR}/source-tree.txt" "${FF7_RES}/"
  VERBATIM)
# The build (for bug reports: Report.swift)
execute_process(COMMAND git -C "${FF7_ROOT}" describe --always --dirty OUTPUT_VARIABLE FF7_GIT OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
file(WRITE "${CMAKE_BINARY_DIR}/build-info.txt" "${FF7_GIT} (macos branch)\n")
add_custom_command(TARGET FF7Recomp POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/build-info.txt" "${FF7_RES}/" VERBATIM)
