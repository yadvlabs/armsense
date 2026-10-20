#!/bin/sh
# ssh into the build VM as root: ./ssh.sh [command...]
set -eu
. "$(dirname "$0")/common.sh"
exec ssh $SSH_OPTS -p "$SSH_PORT" root@127.0.0.1 "$@"
