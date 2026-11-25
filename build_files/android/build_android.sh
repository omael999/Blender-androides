#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build Blender for Android and package it as an APK.
#
#   1. Dependencies   -> lib/android_<abi>/              (build_deps_android.sh, once)
#   2. Blender (NDK)  -> ../build_android/install/       (libmain.so + <version>/ data files)
#   3. APK (Gradle)   -> build_files/android/app/build/outputs/apk/
#
# Usage:
#   export ANDROID_HOME=~/Android/Sdk
#   export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
#   ./build_files/android/build_android.sh            # everything
#   ./build_files/android/build_android.sh --skip-deps
#   ./build_files/android/build_android.sh --release  # assembleRelease instead of debug
#
# Install on a device:  adb install -r build_files/android/app/build/outputs/apk/debug/app-debug.apk
# Logs:                 adb logcat -s Blender BlenderSetup SDL

set -euo pipefail
shopt -s inherit_errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_SRC="$(cd "${SCRIPT_DIR}/../.." && pwd)"

: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the Android NDK (r29 or newer)}"

ABI="${ANDROID_ABI:-arm64-v8a}"
API="${ANDROID_API:-29}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
BUILD_DIR="${BUILD_DIR:-${BLENDER_SRC}/../build_android}"
INSTALL_DIR="${BUILD_DIR}/install"
LIBDIR="${LIBDIR:-${BLENDER_SRC}/lib/android_${ABI}}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

SKIP_DEPS=0
GRADLE_TASK=assembleDebug
for arg in "$@"; do
  case "${arg}" in
    --skip-deps) SKIP_DEPS=1 ;;
    --release)   GRADLE_TASK=assembleRelease ;;
    -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown argument: ${arg}" >&2; exit 1 ;;
  esac
done

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# Blender version as "<major>.<minor>" (e.g. 504 -> 5.4).
BLENDER_VERSION_NUM="$(sed -n 's/^#define BLENDER_VERSION \([0-9]*\)$/\1/p' \
  "${BLENDER_SRC}/source/blender/blenkernel/BKE_blender_version.h")"
BLENDER_VERSION="$((BLENDER_VERSION_NUM / 100)).$((BLENDER_VERSION_NUM % 100))"

# -----------------------------------------------------------------------------
# 1. Dependencies

if [[ ${SKIP_DEPS} -eq 0 ]]; then
  log "Building dependencies for ${ABI} (this takes a long time the first time)"
  ANDROID_ABI="${ABI}" ANDROID_API="${API}" LIBDIR="${LIBDIR}" \
    "${BLENDER_SRC}/build_files/build_environment/android/build_deps_android.sh"
fi

# -----------------------------------------------------------------------------
# 2. Blender

# Code generators (makesdna, makesrna...) must run on this machine, build them natively.
HOST_TOOLS_DIR="${HOST_TOOLS_DIR:-${BUILD_DIR}_host}"
log "Building native code generators in ${HOST_TOOLS_DIR}"
"${SCRIPT_DIR}/build_host_tools.sh" "${HOST_TOOLS_DIR}"

log "Configuring Blender ${BLENDER_VERSION} for Android ${ABI} (API ${API})"
cmake -S "${BLENDER_SRC}" -B "${BUILD_DIR}" -G Ninja \
  -C "${BLENDER_SRC}/build_files/cmake/config/blender_android.cmake" \
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="${ABI}" \
  -DANDROID_PLATFORM="android-${API}" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DWITH_INSTALL_PORTABLE=ON \
  -DLIBDIR="${LIBDIR}" \
  -DBLENDER_HOST_TOOLS_DIR="${HOST_TOOLS_DIR}/blender/bin"

log "Compiling Blender (${JOBS} jobs)"
cmake --build "${BUILD_DIR}" -j "${JOBS}"

log "Installing to ${INSTALL_DIR}"
cmake --install "${BUILD_DIR}"

# Shared C++ runtime used by Blender and every shared dependency.
mkdir -p "${INSTALL_DIR}/lib"
cp "${LIBDIR}/cxx/lib/libc++_shared.so" "${INSTALL_DIR}/lib/"
# Shared libraries from the dependencies (SDL3, TBB, OIIO, OCIO, OpenEXR, Imath, Python...).
find "${LIBDIR}" -path '*/lib/*.so' ! -name 'libvulkan.so' -exec cp -L {} "${INSTALL_DIR}/lib/" \;
# Android only loads `lib*.so` without version suffixes from the APK.
for f in "${INSTALL_DIR}"/lib/*.so.*; do
  [[ -e "${f}" ]] || continue
  echo "WARNING: versioned library ${f##*/}, set SONAME without version when building it" >&2
done

# CPython standard library next to Blender's scripts (PYTHONHOME, see creator_android.cc).
PY_SHORT="$(ls "${LIBDIR}/python/lib" | sed -n 's/^python\(3\.[0-9]*\)$/\1/p' | head -1)"
if [[ -n "${PY_SHORT}" ]]; then
  mkdir -p "${INSTALL_DIR}/${BLENDER_VERSION}/python/lib"
  rsync -a --delete --exclude '__pycache__' --exclude 'test' --exclude 'idlelib' \
    --exclude 'tkinter' --exclude 'turtledemo' \
    "${LIBDIR}/python/lib/python${PY_SHORT}" "${INSTALL_DIR}/${BLENDER_VERSION}/python/lib/"
fi

# -----------------------------------------------------------------------------
# 3. APK

log "Packaging APK (${GRADLE_TASK})"
cd "${SCRIPT_DIR}"
echo "sdk.dir=${ANDROID_HOME}" > local.properties
GRADLE="./gradlew"
[[ -x "${GRADLE}" ]] || GRADLE="gradle"
NDK_REVISION="$(sed -n 's/^Pkg.Revision *= *//p' "${ANDROID_NDK_HOME}/source.properties")"
"${GRADLE}" "${GRADLE_TASK}" \
  -Pblender.ndkVersion="${NDK_REVISION}" \
  -Pblender.installDir="${INSTALL_DIR}" \
  -Psdl.sourceDir="${BLENDER_SRC}/lib/android_src/SDL3" \
  -Pblender.version="${BLENDER_VERSION}"

log "APK ready:"
find "${SCRIPT_DIR}/app/build/outputs/apk" -name '*.apk' -print
