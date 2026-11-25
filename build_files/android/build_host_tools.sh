#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build Blender's code generators (makesdna, makesrna, datatoc, msgfmt, shader_tool)
# natively for the build machine, so a cross-compiled (Android) build can run them.
#
# They are configured with the same feature options as the Android build
# (`blender_android.cmake`), since `makesrna` generates different code per option.
#
# Linux host requirements (Ubuntu 24.04 package names):
#   build-essential gcc-14 g++-14 cmake ninja-build python3.13 (with libpython) libjpeg-dev libpng-dev
#   zlib1g-dev libzstd-dev libepoxy-dev libfmt-dev libfreetype-dev libbrotli-dev
#   libimath-dev libopenexr-dev libopenimageio-dev openimageio-tools libeigen3-dev libtbb-dev
#   libvulkan-dev libshaderc-dev libyaml-cpp-dev libexpat1-dev
# OpenColorIO >= 2.3 and SDL3 are built here (too old / missing in Ubuntu 24.04).
# Ubuntu's OpenImageIO CMake config also needs: sudo mkdir -p /usr/include/opencv4
#
# Usage: build_host_tools.sh <host-build-dir>
# Prints nothing special; the tools end up in <host-build-dir>/bin.

set -euo pipefail
shopt -s inherit_errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_SRC="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOST_DIR="${1:?Usage: build_host_tools.sh <host-build-dir>}"
mkdir -p "${HOST_DIR}"
HOST_DIR="$(cd "${HOST_DIR}" && pwd)"
PREFIX="${HOST_DIR}/prefix"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# Versions/URLs from versions.cmake (via the Android deps script).
uri_of() {
  ANDROID_NDK_HOME=/nonexistent \
    "${BLENDER_SRC}/build_files/build_environment/android/build_deps_android.sh" versions |
    awk -v n="$1" '$1 == n { print $3 }'
}

fetch_src() {  # fetch_src <NAME> <dir>
  local uri dir=$2
  if [[ ! -d "${dir}" ]]; then
    uri="$(uri_of "$1")"
    mkdir -p "${dir}"
    curl -fsSL --retry 3 "${uri}" | tar -xz -C "${dir}" --strip-components=1
  fi
}

host_cmake() {  # host_cmake <src> <build> [args...]
  local src=$1 build=$2; shift 2
  cmake -S "${src}" -B "${build}" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DBUILD_TESTING=OFF "$@"
  cmake --build "${build}" -j "${JOBS}"
  cmake --install "${build}"
}

# -----------------------------------------------------------------------------
# Host dependencies missing from the distribution

if [[ ! -f "${PREFIX}/lib/cmake/OpenColorIO/OpenColorIOConfig.cmake" ]]; then
  log "Building OpenColorIO for the host"
  fetch_src OPENCOLORIO "${HOST_DIR}/src/ocio"
  host_cmake "${HOST_DIR}/src/ocio" "${HOST_DIR}/build/ocio" \
    -DOCIO_BUILD_APPS=OFF -DOCIO_BUILD_PYTHON=OFF -DOCIO_BUILD_TESTS=OFF \
    -DOCIO_BUILD_GPU_TESTS=OFF -DOCIO_BUILD_DOCS=OFF -DOCIO_BUILD_OPENFX=OFF \
    -DOCIO_INSTALL_EXT_PACKAGES=MISSING -DCMAKE_INSTALL_LIBDIR=lib
fi

if [[ ! -f "${PREFIX}/lib/cmake/SDL3/SDL3Config.cmake" ]]; then
  log "Building SDL3 for the host"
  sdl_src="${BLENDER_SRC}/lib/android_src/SDL3"
  [[ -d "${sdl_src}" ]] || { fetch_src SDL "${HOST_DIR}/src/sdl"; sdl_src="${HOST_DIR}/src/sdl"; }
  host_cmake "${sdl_src}" "${HOST_DIR}/build/sdl" \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_TEST_LIBRARY=OFF -DCMAKE_INSTALL_LIBDIR=lib \
    -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_VULKAN=OFF \
    -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_AUDIO=OFF
  # Only needed so Blender's configure finds SDL3, the tools don't use it.
fi

# -----------------------------------------------------------------------------
# Blender, code generators only

PY_ROOT="${PYTHON_ROOT_DIR:-${pythonLocation:-}}"
PY_ARGS=()
[[ -n "${PY_ROOT}" ]] && PY_ARGS=(-DPYTHON_ROOT_DIR="${PY_ROOT}")

# Blender requires GCC 14+ (Ubuntu 24.04 defaults to 13, `gcc-14` is packaged).
COMPILER_ARGS=()
if command -v g++-14 > /dev/null; then
  COMPILER_ARGS=(-DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14)
fi

log "Configuring Blender host tools"
cmake -S "${BLENDER_SRC}" -B "${HOST_DIR}/blender" -G Ninja \
  "${COMPILER_ARGS[@]}" \
  -C "${BLENDER_SRC}/build_files/cmake/config/blender_android.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="${PREFIX}" \
  -DOpenColorIO_ROOT="${PREFIX}" \
  -DSDL3_ROOT="${PREFIX}" \
  -DWITH_LIBS_PRECOMPILED=OFF \
  -DWITH_STATIC_LIBS=OFF \
  -DWITH_STRICT_BUILD_OPTIONS=OFF \
  -DWITH_GHOST_X11=OFF \
  -DWITH_GHOST_WAYLAND=OFF \
  -DWITH_OPENGL_BACKEND=OFF \
  -DWITH_INSTALL_PORTABLE=ON \
  "${PY_ARGS[@]}"

# Only the tools this configuration has (e.g. `msgfmt` requires WITH_INTERNATIONAL).
TOOLS=()
ALL_TARGETS="$(ninja -C "${HOST_DIR}/blender" -t targets all)"
for t in makesdna makesrna datatoc msgfmt shader_tool; do
  if grep -q "^${t}:" <<< "${ALL_TARGETS}"; then
    TOOLS+=("${t}")
  fi
done
log "Building ${TOOLS[*]}"
cmake --build "${HOST_DIR}/blender" -j "${JOBS}" --target "${TOOLS[@]}"

for t in "${TOOLS[@]}"; do
  test -x "${HOST_DIR}/blender/bin/${t}"
done
log "Host tools ready in ${HOST_DIR}/blender/bin"
