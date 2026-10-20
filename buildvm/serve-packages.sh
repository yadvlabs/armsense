#!/bin/sh
# Serve the synced package repositories over HTTP on port 8000 so test VMs
# (10.0.2.2 under QEMU user networking) reach http://10.0.2.2:8000/packages/<repo>.
# Runs in the foreground.
set -eu
. "$(dirname "$0")/common.sh"
mkdir -p "$WWW"
ln -sfn "$PACKAGES" "$WWW/packages"
cd "$WWW" && exec python3 -m http.server 8000 --bind 0.0.0.0
