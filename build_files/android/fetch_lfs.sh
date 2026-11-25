#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Blender Authors
#
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fetch the Git LFS files needed to build Blender (startup.blend, icons, studio lights...)
# when the checkout only contains LFS pointer files, e.g. in a GitHub fork.
#
# Strategies, in order:
#   1. `git lfs pull` from projects.blender.org (retried, the server may throttle).
#   2. `git lfs pull` from the GitHub mirror.
#   3. Per file over plain HTTP from projects.blender.org's `media` endpoint, accepted only
#      when its SHA-256 matches the object id in the pointer file.
#
# Usage: build_files/android/fetch_lfs.sh   (from the repository root)

set -uo pipefail

INCLUDE="release/datafiles/**,assets/**,scripts/startup/**"
MEDIA_BASE="https://projects.blender.org/blender/blender/media/branch/main"

pointer_files() {
  # Files under the include paths that are still LFS pointers.
  git lfs ls-files -n -I "${INCLUDE}" 2>/dev/null | while read -r f; do
    if [[ -f "${f}" ]] && head -c 100 "${f}" | grep -q "^version https://git-lfs"; then
      echo "${f}"
    fi
  done
}

remaining() { pointer_files | wc -l; }

echo "LFS files to fetch: $(remaining)"
[[ "$(remaining)" -eq 0 ]] && exit 0

for attempt in 1 2 3; do
  echo "== git lfs pull from projects.blender.org (attempt ${attempt})"
  git -c lfs.url=https://projects.blender.org/blender/blender.git/info/lfs \
    lfs pull --include="${INCLUDE}" && break
  sleep $((attempt * 30))
done
echo "Remaining: $(remaining)"

if [[ "$(remaining)" -gt 0 ]]; then
  echo "== git lfs pull from the GitHub mirror"
  git -c lfs.url=https://github.com/blender/blender.git/info/lfs \
    lfs pull --include="${INCLUDE}" || true
  echo "Remaining: $(remaining)"
fi

if [[ "$(remaining)" -gt 0 ]]; then
  echo "== Per-file HTTP download with SHA-256 verification"
  tmp="$(mktemp)"
  pointer_files | while read -r f; do
    oid="$(sed -n 's/^oid sha256:\([0-9a-f]*\)$/\1/p' "${f}")"
    if curl -fsSL --retry 3 --retry-delay 5 -o "${tmp}" "${MEDIA_BASE}/${f}"; then
      got="$(sha256sum "${tmp}" | cut -d' ' -f1)"
      if [[ "${got}" == "${oid}" ]]; then
        cp "${tmp}" "${f}"
        # Store it like `git lfs` would, so the CI cache of .git/lfs/objects keeps it.
        obj=".git/lfs/objects/${oid:0:2}/${oid:2:2}/${oid}"
        mkdir -p "$(dirname "${obj}")" && cp "${tmp}" "${obj}"
      else
        echo "  hash mismatch (file changed upstream since this commit): ${f}"
      fi
    else
      echo "  download failed: ${f}"
    fi
  done
  rm -f "${tmp}"
  echo "Remaining: $(remaining)"
fi

left="$(remaining)"
if [[ "${left}" -gt 0 ]]; then
  echo "WARNING: ${left} LFS files could not be fetched:"
  pointer_files | head -20
fi

size=$(stat -c%s release/datafiles/startup.blend)
echo "startup.blend: ${size} bytes"
# startup.blend is mandatory (CMake refuses to configure without it), the rest only
# affects icons/previews at run-time.
[[ "${size}" -gt 1024 ]]
