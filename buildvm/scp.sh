#!/bin/sh
# copy files to/from the build VM: ./scp.sh src ... dest   (use root@vm:/path for the VM side)
B=$(cd "$(dirname "$0")" && pwd)
args=""
for a in "$@"; do args="$args $(printf %s "$a" | sed 's,^root@vm:,root@127.0.0.1:,')"; done
exec scp -i "$B/id_ed25519" -P "${SSH_PORT:-2222}" -O \
	-o StrictHostKeyChecking=no -o UserKnownHostsFile="$B/known_hosts" -o LogLevel=ERROR \
	$args
