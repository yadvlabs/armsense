#!/bin/sh
#
# setup-vm.sh -- create and bootstrap the armsense build VM on a Mac
# (Apple silicon, QEMU with HVF from Homebrew).
#
# Steps: download the FreeBSD 16.0-CURRENT aarch64 cloud-init image, verify
# it, create the VM disk, generate an SSH key and a cloud-init seed, start the
# VM, install the build tools, create the ZFS work area, clone the pinned
# upstream sources and push the build overlay.  Afterwards:
#
#     ./ssh.sh 'sh /usr/armsense/overlay/vm/clean-build.sh'
#
# State goes to $ARMSENSE_VM_DIR (default ~/.armsense/buildvm).
# Re-running is safe: finished steps are skipped.
#
# Environment overrides: SNAPSHOT_URL, CPUS, MEM, DISK_SIZE, SSH_PORT.
#
set -eu
. "$(dirname "$0")/common.sh"

SNAPSHOT_URL=${SNAPSHOT_URL:-https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest}
IMAGE=FreeBSD-16.0-CURRENT-arm64-aarch64-BASIC-CLOUDINIT-zfs.qcow2.xz

log() { echo ">>> $(date '+%H:%M:%S') $*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1 (brew install $2)"; exit 1; }; }
need qemu-system-aarch64 qemu
need qemu-img qemu
need xz xz
[ -f "$CODE" ] || { echo "missing $CODE (brew install qemu)"; exit 1; }

mkdir -p "$DOWNLOADS" "$SEED_DIR" "$IMAGES" "$PACKAGES"

# 1. FreeBSD image
if [ ! -f "$DOWNLOADS/$IMAGE" ]; then
	log "downloading $IMAGE"
	curl -sS -L -o "$DOWNLOADS/CHECKSUM.SHA256" "$SNAPSHOT_URL/CHECKSUM.SHA256"
	curl -sS -L -o "$DOWNLOADS/$IMAGE" "$SNAPSHOT_URL/$IMAGE"
	want=$(grep -F 'CLOUDINIT' "$DOWNLOADS/CHECKSUM.SHA256" | grep -F 'zfs.qcow2' | awk '{print $4}')
	have=$(shasum -a 256 "$DOWNLOADS/$IMAGE" | awk '{print $1}')
	[ "$want" = "$have" ] || { echo "checksum mismatch for $IMAGE"; rm -f "$DOWNLOADS/$IMAGE"; exit 1; }
	log "checksum ok"
fi

# 2. Disk
if [ ! -f "$DISK" ]; then
	log "creating $DISK ($DISK_SIZE)"
	xz -dc "$DOWNLOADS/$IMAGE" > "$DISK"
	qemu-img resize -q "$DISK" "$DISK_SIZE"
fi

# 3. SSH key, cloud-init seed, firmware variables
[ -f "$KEY" ] || { log "generating SSH key"; ssh-keygen -q -t ed25519 -N '' -C 'armsense-buildvm' -f "$KEY"; }
if [ ! -f "$SEED" ]; then
	log "creating cloud-init seed"
	cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
hostname: armsense-build
fqdn: armsense-build.local
manage_etc_hosts: true
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys:
      - $(cat "$KEY.pub")
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
runcmd:
  - sysrc sshd_enable=YES
  - sed -i '' -e 's/^#\{0,1\}PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - service sshd restart
  - sysrc ntpd_enable=YES ntpd_sync_on_start=YES
  - service ntpd start
final_message: "armsense-build cloud-init done after \$UPTIME seconds"
EOF
	printf 'instance-id: armsense-build-%s\nlocal-hostname: armsense-build\n' "$(date +%Y%m%d%H%M%S)" > "$SEED_DIR/meta-data"
	hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "$SEED" "$SEED_DIR"
fi
[ -f "$VARS" ] || cp "$VARS_TEMPLATE" "$VARS"
rm -f "$KNOWN_HOSTS"

# 4. Start and wait for SSH
vm_running || { log "starting VM"; "$B/run.sh" start; }
log "waiting for SSH"
for i in $(seq 1 120); do vm_ssh -o ConnectTimeout=3 true 2>/dev/null && break; sleep 5; done
vm_ssh true || { echo "VM did not come up; see $SERIAL"; exit 1; }
log "VM up: $(vm_ssh 'uname -r; date -u' | tr '\n' ' ')"

# 5. Bootstrap inside the VM
log "installing tools, work area and sources"
vm_ssh 'sh -s' <<EOF
set -e
export ASSUME_ALWAYS_YES=yes
pkg install -q git-lite poudriere ccache rsync tmux xmlstarlet sqlite3 qemu-tools >/tmp/pkg-install.log 2>&1 || { tail -5 /tmp/pkg-install.log; exit 1; }
pool=\$(zpool list -H -o name | head -1)
zfs list -H -o name \${pool}/armsense >/dev/null 2>&1 || zfs create -o mountpoint=$A -o compression=lz4 -o atime=off \${pool}/armsense
mkdir -p $A/src $A/obj $A/logs $A/overlay $A/distfiles $A/images
cd $A/src
clone() { # name branch pin
	if [ ! -d "\$1/.git" ]; then
		git clone -q --depth 1 --single-branch -b "\$2" "https://github.com/pfsense/\$1.git" "\$1"
	fi
	if [ "\$(git -C "\$1" rev-parse HEAD)" != "\$3" ]; then
		git -C "\$1" fetch -q --depth 1 origin "\$3"
		git -C "\$1" checkout -q -B "\$2" "\$3"
	fi
	echo "\$1 clone rc=0" > $A/logs/clone-\$1.log
	printf '  %-14s %s\n' "\$1" "\$(git -C "\$1" log -1 --format='%h %ad %s' --date=short)"
}
clone pfsense $PFSENSE_BRANCH $PFSENSE_PIN
clone FreeBSD-src $FREEBSD_BRANCH $FREEBSD_PIN
clone FreeBSD-ports $PORTS_BRANCH $PORTS_PIN
EOF

# 6. Overlay
log "pushing the build overlay"
vm_ssh "rm -rf $A/overlay && mkdir -p $A/overlay"
scp $SSH_OPTS -P "$SSH_PORT" -O -q -r "$B/../build/armsense.conf" "$B/../build/src" "$B/../build/ports" "$B/../build/vm" "$B/../build/kernel" "$B/../build/branding" "root@127.0.0.1:$A/overlay/"
log "done. Next: $B/ssh.sh 'nohup sh $A/overlay/vm/clean-build.sh > $A/logs/clean-build.log 2>&1 &'"
