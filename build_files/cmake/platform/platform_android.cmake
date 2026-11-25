# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later

# Platform configuration for Android (cross-compiled with the Android NDK).
#
# Usage (see `build_files/android/README.md`):
#
#   cmake -S . -B ../build_android \
#     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
#     -C build_files/cmake/config/blender_android.cmake
#
# Android is a UNIX (bionic libc) platform, so this file sets the Android specific
# parts and then re-uses `platform_unix.cmake` for dependency discovery.

if(NOT ANDROID)
  message(FATAL_ERROR "platform_android.cmake included without an Android toolchain")
endif()

if(DEFINED CMAKE_ANDROID_ARCH_ABI)
  set(BLENDER_ANDROID_ABI ${CMAKE_ANDROID_ARCH_ABI})
elseif(DEFINED ANDROID_ABI)
  set(BLENDER_ANDROID_ABI ${ANDROID_ABI})
else()
  set(BLENDER_ANDROID_ABI arm64-v8a)
endif()

if(NOT BLENDER_ANDROID_ABI STREQUAL "arm64-v8a" AND NOT BLENDER_ANDROID_ABI STREQUAL "x86_64")
  message(FATAL_ERROR
    "Android ABI \"${BLENDER_ANDROID_ABI}\" is not supported, "
    "Blender requires a 64-bit ABI (arm64-v8a or x86_64)."
  )
endif()

# Vulkan 1.1 loader with `VK_KHR_dynamic_rendering` etc. is needed, API 29 (Android 10)
# is the practical minimum.
if(DEFINED ANDROID_NATIVE_API_LEVEL AND ANDROID_NATIVE_API_LEVEL LESS 29)
  message(FATAL_ERROR "Blender requires ANDROID_PLATFORM android-29 or newer")
endif()

# ----------------------------------------------------------------------------
# Pre-compiled dependencies
#
# Built by `build_files/build_environment/android/build_deps_android.sh`
# into `lib/android_<abi>/<library>/{include,lib}` mirroring the Linux layout.

if(NOT DEFINED LIBDIR)
  set(LIBDIR ${CMAKE_SOURCE_DIR}/lib/android_${BLENDER_ANDROID_ABI})
endif()
if(NOT EXISTS "${LIBDIR}")
  message(FATAL_ERROR
    "Android dependency directory not found: \"${LIBDIR}\".\n"
    "Run build_files/build_environment/android/build_deps_android.sh first "
    "or pass -DLIBDIR=/path/to/android/deps."
  )
endif()

# The NDK toolchain restricts `find_*` to the sysroot, allow our prefix too.
list(APPEND CMAKE_FIND_ROOT_PATH ${LIBDIR})
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)

# ----------------------------------------------------------------------------
# Features not available on Android

foreach(_opt
    WITH_GHOST_X11
    WITH_GHOST_WAYLAND
    WITH_GHOST_DBUS
    WITH_GHOST_XDND
    WITH_X11_XINPUT
    WITH_X11_XFIXES
    WITH_OPENGL_BACKEND
    WITH_XR_OPENXR
    WITH_INPUT_NDOF
    WITH_INPUT_IME
    WITH_JACK
    WITH_PULSEAUDIO
    WITH_PIPEWIRE
    WITH_CYCLES_DEVICE_CUDA
    WITH_CYCLES_DEVICE_OPTIX
    WITH_CYCLES_DEVICE_HIP
    WITH_CYCLES_DEVICE_ONEAPI
    WITH_CYCLES_EMBREE
    WITH_EMBREE
    WITH_LINKER_MOLD
    WITH_LINKER_GOLD
    WITH_MEM_VALGRIND
    WITH_CPU_CHECK
    WITH_INSTALL_PORTABLE_WINDOWS_LAUNCHER
)
  if(${_opt})
    message(STATUS "Android: disabling ${_opt}")
  endif()
  set(${_opt} OFF CACHE BOOL "" FORCE)
endforeach()
unset(_opt)

# Windowing + input + audio go through SDL3, drawing through Vulkan.
set(WITH_GHOST_SDL ON CACHE BOOL "" FORCE)
set(WITH_VULKAN_BACKEND ON CACHE BOOL "" FORCE)

# Bionic provides `dlopen`, `pthread` and `libm`, but has no `libutil`.
set(BLENDER_ANDROID_LINKLIBS log android)

# ----------------------------------------------------------------------------
# Generic UNIX dependency discovery

include(${CMAKE_CURRENT_LIST_DIR}/platform_unix.cmake)

list(APPEND PLATFORM_LINKLIBS ${BLENDER_ANDROID_LINKLIBS})

# SPIR-V headers (`spirv/unified1/spirv.h`) used by the Vulkan backend.
if(EXISTS "${LIBDIR}/spirv_headers/include")
  list(APPEND VULKAN_INCLUDE_DIRS "${LIBDIR}/spirv_headers/include")
else()
  message(FATAL_ERROR "SPIR-V headers missing in ${LIBDIR}/spirv_headers, rebuild the deps")
endif()

# The NDK clang is always used, Android requires PIC and 16 KB page alignment
# for devices running Android 15+.
string(APPEND PLATFORM_CFLAGS " -fPIC")
string(APPEND CMAKE_SHARED_LINKER_FLAGS " -Wl,-z,max-page-size=16384 -Wl,--no-undefined")
string(APPEND CMAKE_MODULE_LINKER_FLAGS " -Wl,-z,max-page-size=16384")

# Binary relocation is a Linux `/proc/self/exe` trick, on Android the data files
# are extracted from the APK into the application's internal storage instead.
set(WITH_BINRELOC OFF)

add_definitions(-DBLENDER_ANDROID)
