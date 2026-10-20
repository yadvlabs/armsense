#!/bin/sh
# Serve buildvm/packages over HTTP on port 8000 so test VMs (10.0.2.2 from QEMU user networking)
# can reach http://10.0.2.2:8000/packages/<repo>.  Runs in the foreground.
B=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$B/www"
ln -sfn "$B/packages" "$B/www/packages"
cd "$B/www" && exec python3 -m http.server 8000 --bind 0.0.0.0
