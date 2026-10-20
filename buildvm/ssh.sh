#!/bin/sh
# ssh into the build VM: ./ssh.sh [command...]
B=$(cd "$(dirname "$0")" && pwd)
exec ssh -i "$B/id_ed25519" -p "${SSH_PORT:-2222}" \
	-o StrictHostKeyChecking=no -o UserKnownHostsFile="$B/known_hosts" \
	-o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=30 \
	root@127.0.0.1 "$@"
