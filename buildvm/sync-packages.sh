#!/bin/sh
# Pull the package repositories and images out of the build VM into buildvm/packages and buildvm/images.
set -eu
B=$(cd "$(dirname "$0")" && pwd)
. "$B/../build/armsense.conf"
RS="rsync -az --delete -e 'ssh -i $B/id_ed25519 -p ${SSH_PORT:-2222} -o StrictHostKeyChecking=no -o UserKnownHostsFile=$B/known_hosts -o LogLevel=ERROR'"
mkdir -p "$B/packages" "$B/images"
# core repository (follow .latest), ports repository (poudriere .latest)
eval $RS -L "root@127.0.0.1:$A/repo/${JAIL_NAME}-core/.latest/" "$B/packages/${JAIL_NAME}-core/"
eval $RS -L "root@127.0.0.1:/usr/local/poudriere/data/packages/${JAIL_NAME}-${PORTS_NAME}/.latest/" "$B/packages/${JAIL_NAME}-${PORTS_NAME}/"
# raw images (7.5 GB each) stay in the VM; fetch one explicitly when needed
eval $RS --exclude "'*.raw'" --exclude "'smoke-*'" "root@127.0.0.1:$A/images/" "$B/images/"
du -sh "$B/packages"/* "$B/images"
