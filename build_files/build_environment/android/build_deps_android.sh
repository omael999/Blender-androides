#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Cross-compile Blender's dependencies for Android with the NDK.
#
# Output layout mirrors the Linux pre-compiled libraries so `platform_unix.cmake`
# can find them unchanged:
#
#   lib/android_arm64-v8a/<library>/{include,lib}
#
# Versions are read from `build_files/build_environment/cmake/versions.cmake`,
# so this stays in sync with the official desktop builds.
#
# Requirements on the host (Linux x86_64 or macOS):
#   - Android NDK r29+ ($ANDROID_NDK_HOME) and SDK ($ANDROID_HOME, for CPython's build)
#   - cmake >= 3.24, ninja, meson, python3 (3.13 recommended), curl, git, patch
#
# Usage:
#   ANDROID_NDK_HOME=~/Android/Sdk/ndk/27.2.12479018 \
#   ANDROID_HOME=~/Android/Sdk \
#     ./build_files/build_environment/android/build_deps_android.sh [deps...]
#
# Without arguments every dependency is built in order. Pass names to (re)build some only,
# e.g. `build_deps_android.sh sdl python`.

set -euo pipefail
shopt -s inherit_errexit  # Fail inside $(...) too (e.g. a failed download).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_SRC="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VERSIONS_CMAKE="${BLENDER_SRC}/build_files/build_environment/cmake/versions.cmake"

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to the Android NDK (r29 or newer)}"
ABI="${ANDROID_ABI:-arm64-v8a}"
API="${ANDROID_API:-29}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"

case "${ABI}" in
  arm64-v8a) TRIPLE=aarch64-linux-android ;;
  x86_64)    TRIPLE=x86_64-linux-android ;;
  *) echo "Unsupported ABI ${ABI}" >&2; exit 1 ;;
esac

PREFIX_ROOT="${LIBDIR:-${BLENDER_SRC}/lib/android_${ABI}}"
WORK="${WORK_DIR:-${BLENDER_SRC}/../build_android_deps}"
DL="${WORK}/downloads"
SRC_ROOT="${WORK}/src"
BUILD_ROOT="${WORK}/build/${ABI}"
mkdir -p "${PREFIX_ROOT}" "${DL}" "${SRC_ROOT}" "${BUILD_ROOT}"

TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
case "$(uname -s)" in
  Linux)  HOST_TAG=linux-x86_64 ;;
  Darwin) HOST_TAG=darwin-x86_64 ;;
esac
NDK_BIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
NDK_SYSROOT="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${HOST_TAG}/sysroot"

log() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }

# -----------------------------------------------------------------------------
# Versions from versions.cmake

declare -A VER URI
eval_versions() {
  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}" <<'EOF'
set(BUILD_MODE Release)
include(${VERSIONS})
foreach(v ZLIB ZSTD PNG JPEG BROTLI FREETYPE DEFLATE IMATH OPENEXR FMT ROBINMAP TBB
          EXPAT YAMLCPP PYSTRING MINIZIPNG OPENCOLORIO OPENIMAGEIO SSE2NEON TIFF
          VULKAN_HEADERS SHADERC SDL EPOXY PYTHON EIGEN SPIRV_HEADERS)
  message("${v}|${${v}_VERSION}|${${v}_URI}")
endforeach()
EOF
  while IFS='|' read -r name version uri; do
    [[ -n "${name}" && "${name}" != *" "* ]] || continue
    VER[${name}]="${version}"
    URI[${name}]="${uri}"
  done < <(cmake -DVERSIONS="${VERSIONS_CMAKE}" -P "${tmp}" 2>&1)
  rm -f "${tmp}"
}
eval_versions

# -----------------------------------------------------------------------------
# Helpers

# fetch <NAME> -> prints extracted source dir
fetch() {
  local name=$1 uri=${URI[$1]}
  # `tar` detects the compression itself, the extension does not matter.
  local file="${DL}/${name}-${VER[$1]}.archive"
  if [[ ! -f "${file}" ]]; then
    curl -L --fail --retry 3 -o "${file}.part" "${uri}" >&2
    mv "${file}.part" "${file}"
  fi
  local dest="${SRC_ROOT}/${name}-${VER[$1]}"
  if [[ ! -d "${dest}" ]]; then
    mkdir -p "${dest}"
    tar -xf "${file}" -C "${dest}" --strip-components=1
  fi
  echo "${dest}"
}

# cmake_dep <NAME> <install-subdir> [extra cmake args...]
#
# Note: NDK r26+ links with `--no-undefined-version`, which rejects version scripts
# naming symbols a library does not define (TBB's do), `--undefined-version` relaxes that.
cmake_dep() {
  local name=$1 sub=$2; shift 2
  local src build
  src="$(fetch "${name}")"
  build="${BUILD_ROOT}/${sub}"
  log "Building ${name} ${VER[${name}]} -> ${PREFIX_ROOT}/${sub}"
  cmake -S "${src}${SRC_SUBDIR:-}" -B "${build}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DANDROID_ABI="${ABI}" \
    -DANDROID_PLATFORM="android-${API}" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX_ROOT}/${sub}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_FIND_ROOT_PATH="${PREFIX_ROOT}" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_PREFIX_PATH="$(find "${PREFIX_ROOT}" -mindepth 1 -maxdepth 1 -type d | paste -sd';')" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,--undefined-version" \
    -DBUILD_TESTING=OFF \
    "$@"
  cmake --build "${build}" -j "${JOBS}"
  cmake --install "${build}"
}

P() { echo "${PREFIX_ROOT}/$1"; }

# -----------------------------------------------------------------------------
# Dependencies (in build order)

build_zlib() {
  cmake_dep ZLIB zlib -DZLIB_BUILD_EXAMPLES=OFF
  rm -f "$(P zlib)"/lib/libz.so*  # Static only, avoid clashing with the system libz.
}

build_zstd() {
  SRC_SUBDIR=/build/cmake cmake_dep ZSTD zstd \
    -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON
}

build_deflate() {
  cmake_dep DEFLATE deflate -DLIBDEFLATE_BUILD_SHARED_LIB=OFF -DLIBDEFLATE_BUILD_GZIP=OFF
}

build_png() {
  cmake_dep PNG png -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
    -DZLIB_ROOT="$(P zlib)" -DPNG_ARM_NEON=on
}

build_jpeg() {
  # libjpeg-turbo 2.x resolves a relative CMAKE_INSTALL_LIBDIR against the wrong root.
  cmake_dep JPEG jpeg -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF \
    -DCMAKE_INSTALL_LIBDIR="$(P jpeg)/lib" -DCMAKE_INSTALL_INCLUDEDIR="$(P jpeg)/include" \
    -DCMAKE_INSTALL_BINDIR="$(P jpeg)/bin" -DCMAKE_INSTALL_DOCDIR="$(P jpeg)/share/doc" \
    -DCMAKE_INSTALL_MANDIR="$(P jpeg)/share/man"
}

build_tiff() {
  cmake_dep TIFF tiff -DBUILD_SHARED_LIBS=OFF -Dtiff-tools=OFF -Dtiff-tests=OFF \
    -Dtiff-docs=OFF -Dlzma=OFF -Dwebp=OFF -Djbig=OFF -Dlerc=OFF -Dzstd=OFF \
    -Dlibdeflate=OFF -Dtiff-contrib=OFF -Dsphinx=OFF \
    -DZLIB_ROOT="$(P zlib)" -DZLIB_LIBRARY="$(P zlib)/lib/libz.a" \
    -DZLIB_INCLUDE_DIR="$(P zlib)/include" \
    -DJPEG_LIBRARY="$(P jpeg)/lib/libjpeg.a" -DJPEG_INCLUDE_DIR="$(P jpeg)/include"
  # Without libdeflate TiffTargets.cmake does not reference a Deflate::Deflate target,
  # which consumers such as OpenImageIO do not define. Deflate still works through zlib.
}

build_brotli() {
  cmake_dep BROTLI brotli -DBUILD_SHARED_LIBS=OFF -DBROTLI_DISABLE_TESTS=ON
}

build_freetype() {
  # Blender requires FreeType with Brotli (WOFF2 fonts). No PNG, like the official build.
  cmake_dep FREETYPE freetype -DBUILD_SHARED_LIBS=OFF \
    -DFT_REQUIRE_BROTLI=ON -DFT_REQUIRE_ZLIB=ON -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_HARFBUZZ=ON \
    -DBROTLIDEC_INCLUDE_DIRS="$(P brotli)/include" \
    -DBROTLIDEC_LIBRARIES="$(P brotli)/lib/libbrotlidec.a;$(P brotli)/lib/libbrotlicommon.a" \
    -DZLIB_ROOT="$(P zlib)"
}

build_imath() {
  cmake_dep IMATH imath -DBUILD_SHARED_LIBS=ON -DPYTHON=OFF
}

build_openexr() {
  cmake_dep OPENEXR openexr -DBUILD_SHARED_LIBS=ON \
    -DOPENEXR_BUILD_TOOLS=OFF -DOPENEXR_INSTALL_EXAMPLES=OFF -DOPENEXR_BUILD_EXAMPLES=OFF \
    -DOPENEXR_FORCE_INTERNAL_DEFLATE=OFF -Dlibdeflate_ROOT="$(P deflate)" \
    -DOPENEXR_FORCE_INTERNAL_OPENJPH=ON \
    -DImath_DIR="$(P imath)/lib/cmake/Imath"
}

build_fmt() {
  cmake_dep FMT fmt -DFMT_TEST=OFF -DFMT_DOC=OFF -DBUILD_SHARED_LIBS=OFF
}

build_robinmap() {
  cmake_dep ROBINMAP robinmap
}

build_tbb() {
  cmake_dep TBB tbb -DTBB_TEST=OFF -DTBB_EXAMPLES=OFF -DTBBMALLOC_PROXY_BUILD=OFF \
    -DTBB_STRICT=OFF -DBUILD_SHARED_LIBS=ON
}

build_expat() {
  SRC_SUBDIR=/expat cmake_dep EXPAT expat -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF \
    -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF -DEXPAT_SHARED_LIBS=OFF
}

build_yamlcpp() {
  cmake_dep YAMLCPP yamlcpp -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF \
    -DYAML_BUILD_SHARED_LIBS=OFF
}

build_pystring() {
  # pystring has no install rules upstream for all versions, install manually.
  local src build
  src="$(fetch PYSTRING)"
  build="${BUILD_ROOT}/pystring"
  log "Building pystring ${VER[PYSTRING]}"
  mkdir -p "${build}" "$(P pystring)/include/pystring" "$(P pystring)/lib"
  "${NDK_BIN}/${TRIPLE}${API}-clang++" -O2 -fPIC -std=c++17 -c "${src}/pystring.cpp" \
    -o "${build}/pystring.o"
  "${NDK_BIN}/llvm-ar" rcs "$(P pystring)/lib/libpystring.a" "${build}/pystring.o"
  # OpenColorIO includes it both as <pystring/pystring.h> and <pystring.h>.
  cp "${src}/pystring.h" "$(P pystring)/include/pystring/"
  cp "${src}/pystring.h" "$(P pystring)/include/"
}

build_minizipng() {
  # Same options as the official build (build_environment/cmake/minizipng.cmake).
  cmake_dep MINIZIPNG minizipng -DMZ_FETCH_LIBS=OFF -DMZ_LIBCOMP=OFF -DMZ_PKCRYPT=OFF \
    -DMZ_WZAES=OFF -DMZ_OPENSSL=OFF -DMZ_SIGNING=OFF -DMZ_PPMD=OFF -DMZ_LZMA=OFF \
    -DMZ_ZSTD=OFF -DMZ_BZIP2=OFF -DMZ_ICONV=OFF -DMZ_ZLIB=ON -DMZ_ZLIB_FLAVOR=zlib \
    -DMZ_COMPAT=OFF -DBUILD_SHARED_LIBS=OFF -DZLIB_ROOT="$(P zlib)" \
    -DZLIB_LIBRARY="$(P zlib)/lib/libz.a" -DZLIB_INCLUDE_DIR="$(P zlib)/include" \
    -DCMAKE_INSTALL_INCLUDEDIR=include/minizip-ng
}

build_opencolorio() {
  cmake_dep OPENCOLORIO opencolorio -DBUILD_SHARED_LIBS=ON \
    -DOCIO_BUILD_APPS=OFF -DOCIO_BUILD_PYTHON=OFF -DOCIO_BUILD_NUKE=OFF \
    -DOCIO_BUILD_OPENFX=OFF -DOCIO_BUILD_TESTS=OFF -DOCIO_BUILD_GPU_TESTS=OFF \
    -DOCIO_BUILD_DOCS=OFF -DOCIO_INSTALL_EXT_PACKAGES=NONE -DOCIO_USE_SIMD=OFF \
    -Dexpat_ROOT="$(P expat)" -Dyaml-cpp_ROOT="$(P yamlcpp)" \
    -Dpystring_ROOT="$(P pystring)" -Dpystring_INCLUDE_DIR="$(P pystring)/include" \
    -Dpystring_LIBRARY="$(P pystring)/lib/libpystring.a" \
    -Dminizip-ng_ROOT="$(P minizipng)" -DZLIB_ROOT="$(P zlib)" \
    -DImath_DIR="$(P imath)/lib/cmake/Imath"
}

build_openimageio() {
  cmake_dep OPENIMAGEIO openimageio -DBUILD_SHARED_LIBS=ON -DLINKSTATIC=OFF \
    -DUSE_SIMD=0 -DOIIO_BUILD_TOOLS=OFF -DOIIO_BUILD_TESTS=OFF -DUSE_PYTHON=OFF \
    -DUSE_QT=OFF -DUSE_OPENGL=OFF -DUSE_FREETYPE=OFF -DUSE_OPENVDB=OFF -DUSE_FFMPEG=OFF \
    -DUSE_GIF=OFF -DUSE_LIBHEIF=OFF -DUSE_LIBRAW=OFF -DUSE_OPENCV=OFF -DUSE_PTEX=OFF \
    -DUSE_JXL=OFF -DUSE_WEBP=OFF -DUSE_OPENJPEG=OFF -DUSE_DCMTK=OFF -DUSE_NUKE=OFF \
    -DUSE_TBB=ON -DUSE_OPENCOLORIO=ON -DUSE_EXTERNAL_PUGIXML=OFF \
    -DOpenImageIO_BUILD_MISSING_DEPS="" -DSTOP_ON_WARNING=OFF \
    -DZLIB_ROOT="$(P zlib)" -DPNG_ROOT="$(P png)" -DJPEG_ROOT="$(P jpeg)" \
    -Dlibjpeg-turbo_ROOT="$(P jpeg)" -DTIFF_ROOT="$(P tiff)" \
    -DJPEG_INCLUDE_DIR="$(P jpeg)/include" -DJPEG_LIBRARY="$(P jpeg)/lib/libjpeg.a" \
    -DPNG_PNG_INCLUDE_DIR="$(P png)/include" -DPNG_LIBRARY="$(P png)/lib/libpng.a" \
    -DTIFF_INCLUDE_DIR="$(P tiff)/include" -DTIFF_LIBRARY="$(P tiff)/lib/libtiff.a" \
    -DZLIB_LIBRARY="$(P zlib)/lib/libz.a" -DZLIB_INCLUDE_DIR="$(P zlib)/include" \
    -DImath_DIR="$(P imath)/lib/cmake/Imath" -DOpenEXR_DIR="$(P openexr)/lib/cmake/OpenEXR" \
    -Dfmt_ROOT="$(P fmt)" -DRobinmap_ROOT="$(P robinmap)" -DTBB_ROOT="$(P tbb)" \
    -DOpenColorIO_DIR="$(P opencolorio)/lib/cmake/OpenColorIO"
}

build_eigen() {
  # Header only, always required by Blender (also by Ceres/libmv when enabled).
  cmake_dep EIGEN eigen -DEIGEN_BUILD_TESTING=OFF -DEIGEN_BUILD_DOC=OFF \
    -DEIGEN_BUILD_PKGCONFIG=OFF -DEIGEN_BUILD_BLAS=OFF -DEIGEN_BUILD_LAPACK=OFF
}

build_sse2neon() {
  [[ "${ABI}" == arm64-v8a ]] || return 0
  local src
  src="$(fetch SSE2NEON)"
  log "Installing sse2neon"
  mkdir -p "$(P sse2neon)/include"
  cp "${src}/sse2neon.h" "$(P sse2neon)/include/"
}

build_vulkan() {
  # Headers from Khronos, the loader `libvulkan.so` is part of Android itself.
  cmake_dep VULKAN_HEADERS vulkan
  mkdir -p "$(P vulkan)/lib"
  ln -sf "${NDK_SYSROOT}/usr/lib/${TRIPLE}/${API}/libvulkan.so" "$(P vulkan)/lib/libvulkan.so"
}

build_spirv_headers() {
  # `spirv/unified1/spirv.h`, included by Blender's Vulkan shader compiler.
  cmake_dep SPIRV_HEADERS spirv_headers -DSPIRV_HEADERS_ENABLE_TESTS=OFF \
    -DSPIRV_HEADERS_ENABLE_INSTALL=ON
}

build_shaderc() {
  # Blender compiles GLSL to SPIR-V at run-time with shaderc.
  local src
  src="$(fetch SHADERC)"
  if [[ ! -d "${src}/third_party/glslang" ]]; then
    log "Fetching shaderc third party sources"
    (cd "${src}" && python3 utils/git-sync-deps)
  fi
  cmake_dep SHADERC shaderc -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF -DSHADERC_ENABLE_SHARED_CRT=ON \
    -DPython3_EXECUTABLE="$(command -v python3)"
}

build_sdl() {
  cmake_dep SDL sdl -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_VULKAN=ON -DSDL_OPENGLES=ON
  # Keep the source tree around: Gradle compiles SDL's Java glue from it.
  mkdir -p "${BLENDER_SRC}/lib/android_src"
  ln -sfn "$(fetch SDL)" "${BLENDER_SRC}/lib/android_src/SDL3"
}

build_epoxy() {
  # Required by Blender's CMake even without the OpenGL backend (headers only are used).
  local src build cross
  src="$(fetch EPOXY)"
  build="${BUILD_ROOT}/epoxy"
  cross="${BUILD_ROOT}/meson-cross.txt"
  cat > "${cross}" <<EOF
[binaries]
c = '${NDK_BIN}/${TRIPLE}${API}-clang'
cpp = '${NDK_BIN}/${TRIPLE}${API}-clang++'
ar = '${NDK_BIN}/llvm-ar'
strip = '${NDK_BIN}/llvm-strip'

[host_machine]
system = 'android'
cpu_family = '${TRIPLE%%-*}'
cpu = '${TRIPLE%%-*}'
endian = 'little'
EOF
  log "Building libepoxy ${VER[EPOXY]}"
  meson setup --wipe "${build}" "${src}" --cross-file "${cross}" \
    --prefix "$(P epoxy)" --libdir lib --default-library static --buildtype release \
    -Dglx=no -Dx11=false -Degl=yes -Dtests=false || \
  meson setup "${build}" "${src}" --cross-file "${cross}" \
    --prefix "$(P epoxy)" --libdir lib --default-library static --buildtype release \
    -Dglx=no -Dx11=false -Degl=yes -Dtests=false
  meson compile -C "${build}" -j "${JOBS}"
  meson install -C "${build}"
}

build_python() {
  # CPython supports Android officially (PEP 738) via `Android/android.py`.
  : "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK (needed by the CPython Android build)}"
  local src
  src="$(fetch PYTHON)"
  log "Building CPython ${VER[PYTHON]} for ${TRIPLE}"
  (
    cd "${src}"
    python3 Android/android.py configure-build
    python3 Android/android.py make-build
    python3 Android/android.py configure-host "${TRIPLE}"
    python3 Android/android.py make-host "${TRIPLE}"
  )
  local short="${VER[PYTHON]%.*}"
  local built="${src}/cross-build/${TRIPLE}/prefix"
  rm -rf "$(P python)"
  mkdir -p "$(P python)"
  cp -a "${built}/include" "${built}/lib" "$(P python)/"
  # Blender's FindPythonLibsUnix looks for `include/python3.X` and `lib/libpython3.X.so`.
  [[ -f "$(P python)/lib/libpython${short}.so" ]] || {
    echo "libpython${short}.so missing in ${built}/lib" >&2
    exit 1
  }
}

# `build_deps_android.sh versions` lists what would be built.
build_versions() {
  local k
  for k in $(printf '%s\n' "${!VER[@]}" | sort); do
    printf '%-16s %-44s %s\n' "${k}" "${VER[${k}]}" "${URI[${k}]}"
  done
}

ALL_DEPS=(zlib zstd deflate png jpeg tiff brotli freetype imath openexr fmt robinmap tbb
          expat yamlcpp pystring minizipng opencolorio openimageio sse2neon vulkan shaderc
          sdl epoxy python eigen spirv_headers)

if [[ $# -gt 0 ]]; then
  DEPS=("$@")
else
  DEPS=("${ALL_DEPS[@]}")
fi

# Dependencies already installed in LIBDIR are skipped (so a cached LIBDIR only
# builds what is new), unless named explicitly or FORCE_DEPS=1.
for dep in "${DEPS[@]}"; do
  if [[ $# -eq 0 && "${FORCE_DEPS:-0}" != 1 && "${dep}" != versions && \
        -n "$(ls -A "$(P "${dep}")" 2>/dev/null)" ]]; then
    log "Skipping ${dep} (already in $(P "${dep}"))"
    continue
  fi
  "build_${dep}"
done

[[ "${DEPS[*]}" == "versions" ]] && exit 0

# The C++ runtime is shared between all libraries and must be packaged in the APK.
mkdir -p "$(P cxx)/lib"
cp "${NDK_SYSROOT}/usr/lib/${TRIPLE}/libc++_shared.so" "$(P cxx)/lib/"

log "Done. Dependencies installed in ${PREFIX_ROOT}"
