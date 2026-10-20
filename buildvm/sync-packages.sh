#!/bin/sh
# Pull the package repositories and images out of the build VM into
# $ARMSENSE_VM_DIR/{packages,images} (raw images stay in the VM).
set -eu
. "$(dirname "$0")/common.sh"
mkdir -p "$PACKAGES" "$IMAGES"
RS="rsync -az --delete -e \"ssh $SSH_OPTS -p $SSH_PORT\""
eval $RS -L "root@127.0.0.1:$A/repo/${JAIL_NAME}-core/.latest/" "$PACKAGES/${JAIL_NAME}-core/"
eval $RS -L "root@127.0.0.1:/usr/local/poudriere/data/packages/${JAIL_NAME}-${PORTS_NAME}/.latest/" "$PACKAGES/${JAIL_NAME}-${PORTS_NAME}/"
eval $RS --exclude "'*.raw'" --exclude "'smoke-*'" "root@127.0.0.1:$A/images/" "$IMAGES/"
du -sh "$PACKAGES"/* "$IMAGES"
