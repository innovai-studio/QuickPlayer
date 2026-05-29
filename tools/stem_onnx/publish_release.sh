#!/usr/bin/env bash
# Publish the six stem-model artifacts in stem_spike/models/dist/ to a
# GitHub Release on innovai-studio/QuickPlayer. The Dart manifest in
# lib/features/stem/data/stem_model_config.dart points at this exact
# tag + filenames, so changing either side without the other will brick
# first-use download.
#
# Usage:
#   tools/stem_onnx/publish_release.sh                 # uses tag models-v2.1
#   tools/stem_onnx/publish_release.sh models-v2.1-rc2 # custom tag
#
# Requirements: gh CLI authenticated against innovai-studio/QuickPlayer
# (gh auth login). Aborts if any file size disagrees with the manifest.
set -euo pipefail

TAG="${1:-models-v2.1}"
REPO="innovai-studio/QuickPlayer"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/stem_spike/models/dist"

# fileName : expectedBytes  — keep in sync with StemModelConfig.
declare -a FILES=(
  "htdemucs_2s.onnx:2072388"
  "htdemucs_2s.weights:167880704"
  "htdemucs_3s9.onnx:3447815"
  "htdemucs_3s9.weights:167880704"
  "htdemucs_7s8.onnx:6408327"
  "htdemucs_7s8.weights:167880704"
)

cd "${PROJECT_ROOT}"

echo "→ verifying ${#FILES[@]} files in ${DIST_DIR}"
for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  expected="${entry##*:}"
  path="${DIST_DIR}/${name}"
  if [[ ! -f "${path}" ]]; then
    echo "missing: ${path}" >&2; exit 1
  fi
  actual="$(stat -c %s "${path}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "size mismatch ${name}: have ${actual}, manifest says ${expected}" >&2
    exit 1
  fi
done
echo "  ok — sizes match manifest"

# Create the release if it doesn't exist; ignore the failure if it does
# (a re-run with new files needs `gh release upload --clobber`).
if ! gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  echo "→ creating release ${TAG}"
  gh release create "${TAG}" \
    --repo "${REPO}" \
    --title "Stem models ${TAG}" \
    --notes "htdemucs stem-separation models (v2.1, native FFT). Downloaded on first use by QuickPlayer — see lib/features/stem/data/model_installer.dart." \
    --prerelease
else
  echo "→ release ${TAG} already exists; will --clobber assets"
fi

for entry in "${FILES[@]}"; do
  name="${entry%%:*}"
  path="${DIST_DIR}/${name}"
  echo "→ uploading ${name}"
  gh release upload "${TAG}" "${path}" --repo "${REPO}" --clobber
done

echo "→ done. Assets live at:"
echo "   https://github.com/${REPO}/releases/download/${TAG}/<filename>"
