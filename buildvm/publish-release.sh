#!/bin/sh
# Attach the images built in the VM to a GitHub release (created by the
# Release workflow when a v* tag is pushed).  Needs the gh CLI logged in.
#
# Usage: ./publish-release.sh v0.1.0
set -eu
. "$(dirname "$0")/common.sh"
tag=${1:?tag}
"$B/sync-packages.sh" >/dev/null
cd "$IMAGES"
files=$(ls armsense-*.qcow2 armsense-*.iso 2>/dev/null)
[ -n "$files" ] || { echo "no images in $IMAGES"; exit 1; }
shasum -a 256 $files > "SHA256SUMS-images-$tag.txt"
gh release upload "$tag" $files "SHA256SUMS-images-$tag.txt" --clobber
gh release view "$tag"
