#!/usr/bin/env bash
#
# Attach the locally-built, signed assets (macOS / Android / Linux) to an
# existing GitHub Release. Windows is built and attached by CI
# (.github/workflows/release-windows.yml); this script adds the rest.
#
# Run it yourself after your local/self-hosted builds are done:
#   scripts/release-assets.sh v1.2.3 [dir-containing-the-files]
#
# Requires the `gh` CLI authenticated against github.com.
set -euo pipefail

TAG="${1:?usage: release-assets.sh <tag> [dir]}"
DIR="${2:-.}"

assets=(
  "$DIR/BiblioGenius-macOS.dmg"
  "$DIR/BiblioGenius-Android.apk"
  "$DIR/BiblioGenius-Linux.tar.gz"
)

missing=0
for f in "${assets[@]}"; do
  if [ ! -f "$f" ]; then
    echo "missing: $f" >&2
    missing=1
  fi
done
if [ "$missing" != 0 ]; then
  echo "Aborting: build the signed assets first." >&2
  exit 1
fi

gh release upload "$TAG" "${assets[@]}" --clobber
echo "Uploaded macOS / Android / Linux assets to release $TAG"
