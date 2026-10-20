#!/bin/sh
# Copy files to/from the build VM: ./scp.sh src ... dest   (use root@vm:/path for the VM side)
set -eu
. "$(dirname "$0")/common.sh"
args=""
for a in "$@"; do args="$args $(printf %s "$a" | sed 's,^root@vm:,root@127.0.0.1:,')"; done
exec scp $SSH_OPTS -P "$SSH_PORT" -O $args
