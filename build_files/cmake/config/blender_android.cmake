# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later

# Configuration preset for the Android port (arm64-v8a, SDL3 + Vulkan).
#
# Use with the Android NDK toolchain:
#   cmake -C build_files/cmake/config/blender_android.cmake \
#     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 ...
#
# Phase 1 ("base port"): only what is needed to start the UI, model and render with EEVEE.
# Dependencies that are heavy or not yet built for Android are disabled; they can be
# enabled one by one once `build_deps_android.sh` provides them.

# Core of the port.
set(WITH_GHOST_SDL           ON  CACHE BOOL "" FORCE)
set(WITH_VULKAN_BACKEND      ON  CACHE BOOL "" FORCE)
set(WITH_OPENGL_BACKEND      OFF CACHE BOOL "" FORCE)
set(WITH_PYTHON              ON  CACHE BOOL "" FORCE)  # The UI is defined in Python.
set(WITH_PYTHON_INSTALL      ON  CACHE BOOL "" FORCE)
set(WITH_PYTHON_INSTALL_NUMPY OFF CACHE BOOL "" FORCE)
set(WITH_PYTHON_INSTALL_ZSTANDARD OFF CACHE BOOL "" FORCE)
set(WITH_PYTHON_SAFETY       OFF CACHE BOOL "" FORCE)
set(WITH_TBB                 ON  CACHE BOOL "" FORCE)
set(WITH_FREETYPE            ON  CACHE BOOL "" FORCE)
set(WITH_LIBS_PRECOMPILED    ON  CACHE BOOL "" FORCE)
set(WITH_STATIC_LIBS         ON  CACHE BOOL "" FORCE)
set(WITH_SDL_AUDIO           OFF CACHE BOOL "" FORCE)  # Phase 2.
set(WITH_AUDASPACE           OFF CACHE BOOL "" FORCE)  # Phase 2.

# Not available / not ported yet.
set(WITH_ALEMBIC             OFF CACHE BOOL "" FORCE)
set(WITH_BLENDER_THUMBNAILER OFF CACHE BOOL "" FORCE)
set(WITH_BOOST               OFF CACHE BOOL "" FORCE)
set(WITH_BUILDINFO           OFF CACHE BOOL "" FORCE)
set(WITH_BULLET              OFF CACHE BOOL "" FORCE)
set(WITH_CODEC_FFMPEG        OFF CACHE BOOL "" FORCE)
set(WITH_CODEC_SNDFILE       OFF CACHE BOOL "" FORCE)
set(WITH_CYCLES              OFF CACHE BOOL "" FORCE)  # Phase 3 (CPU only).
set(WITH_DRACO               OFF CACHE BOOL "" FORCE)
set(WITH_EMBREE              OFF CACHE BOOL "" FORCE)
set(WITH_TRACY               OFF CACHE BOOL "" FORCE)
set(WITH_MESHOPTIMIZER       OFF CACHE BOOL "" FORCE)
set(WITH_KTX                 OFF CACHE BOOL "" FORCE)
set(WITH_FFTW3               OFF CACHE BOOL "" FORCE)
set(WITH_FREESTYLE           OFF CACHE BOOL "" FORCE)
set(WITH_GMP                 OFF CACHE BOOL "" FORCE)
set(WITH_HARU                OFF CACHE BOOL "" FORCE)
set(WITH_HYDRA               OFF CACHE BOOL "" FORCE)
set(WITH_IMAGE_CINEON        OFF CACHE BOOL "" FORCE)
set(WITH_IMAGE_OPENJPEG      OFF CACHE BOOL "" FORCE)
set(WITH_IMAGE_WEBP          OFF CACHE BOOL "" FORCE)
set(WITH_INPUT_IME           OFF CACHE BOOL "" FORCE)
set(WITH_INPUT_NDOF          OFF CACHE BOOL "" FORCE)
set(WITH_INTERNATIONAL       OFF CACHE BOOL "" FORCE)
set(WITH_IO_FBX              OFF CACHE BOOL "" FORCE)
set(WITH_JACK                OFF CACHE BOOL "" FORCE)
set(WITH_JOLT                OFF CACHE BOOL "" FORCE)
set(WITH_LIBMV               OFF CACHE BOOL "" FORCE)
set(WITH_LLVM                OFF CACHE BOOL "" FORCE)
set(WITH_MANIFOLD            OFF CACHE BOOL "" FORCE)
set(WITH_MATERIALX           OFF CACHE BOOL "" FORCE)
set(WITH_MOD_FLUID           OFF CACHE BOOL "" FORCE)
set(WITH_MOD_OCEANSIM        OFF CACHE BOOL "" FORCE)
set(WITH_MOD_REMESH          OFF CACHE BOOL "" FORCE)
set(WITH_NANOVDB             OFF CACHE BOOL "" FORCE)
set(WITH_OPENAL              OFF CACHE BOOL "" FORCE)
set(WITH_OPENCOLORIO         OFF CACHE BOOL "" FORCE)  # Phase 2.
set(WITH_OPENIMAGEDENOISE    OFF CACHE BOOL "" FORCE)
set(WITH_OPENSUBDIV          OFF CACHE BOOL "" FORCE)  # Phase 2.
set(WITH_OPENTIMELINEIO      OFF CACHE BOOL "" FORCE)
set(WITH_OPENVDB             OFF CACHE BOOL "" FORCE)
set(WITH_POTRACE             OFF CACHE BOOL "" FORCE)
set(WITH_PUGIXML             OFF CACHE BOOL "" FORCE)
set(WITH_QUADRIFLOW          OFF CACHE BOOL "" FORCE)
set(WITH_RUBBERBAND          OFF CACHE BOOL "" FORCE)
set(WITH_TBB_MALLOC_PROXY    OFF CACHE BOOL "" FORCE)
set(WITH_USD                 OFF CACHE BOOL "" FORCE)
set(WITH_UV_SLIM             OFF CACHE BOOL "" FORCE)
set(WITH_XR_OPENXR           OFF CACHE BOOL "" FORCE)
set(WITH_CPU_CHECK           OFF CACHE BOOL "" FORCE)
set(WITH_GTESTS              OFF CACHE BOOL "" FORCE)

# Keep the lightweight importers/exporters, they have no external dependencies.
set(WITH_IO_WAVEFRONT_OBJ    ON  CACHE BOOL "" FORCE)
set(WITH_IO_STL              ON  CACHE BOOL "" FORCE)
set(WITH_IO_PLY              ON  CACHE BOOL "" FORCE)
