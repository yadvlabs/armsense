# common.sh -- shared settings for the build VM helpers.  Sourced by the
# scripts in this directory.
#
# All VM state (disk, firmware variables, SSH key, cloud-init seed, downloads,
# synced images and packages) lives OUTSIDE the repository, in
# $ARMSENSE_VM_DIR (default ~/.armsense/buildvm), so that `git clean -fdx`
# cannot remove it.

B=$(cd "$(dirname "$0")" && pwd)
S=${ARMSENSE_VM_DIR:-$HOME/.armsense/buildvm}
mkdir -p "$S"

. "$B/../build/armsense.conf"

SSH_PORT=${SSH_PORT:-2222}
CPUS=${CPUS:-10}
MEM=${MEM:-32G}
DISK_SIZE=${DISK_SIZE:-200G}

CODE=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
VARS_TEMPLATE=/opt/homebrew/share/qemu/edk2-arm-vars.fd

DISK=$S/armsense-build.qcow2
VARS=$S/efivars.fd
KEY=$S/id_ed25519
KNOWN_HOSTS=$S/known_hosts
SEED=$S/seed.iso
SEED_DIR=$S/seed
PIDFILE=$S/qemu.pid
MONITOR=$S/monitor.sock
SERIAL=$S/serial.log
DOWNLOADS=$S/downloads
IMAGES=$S/images
PACKAGES=$S/packages
WWW=$S/www

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=$KNOWN_HOSTS -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=30"

vm_running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

# vm_ssh [cmd...]
vm_ssh() { ssh $SSH_OPTS -p "$SSH_PORT" root@127.0.0.1 "$@"; }
