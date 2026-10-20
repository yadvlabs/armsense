#!/bin/sh
# Boot an armsense arm64 image under QEMU/HVF for testing.
#
# Usage: ./run.sh disk  <image.qcow2>      boot an installed disk image
#        ./run.sh iso   <installer.iso> [disk.qcow2]   boot the installer (creates disk if missing)
#
# Network: vtnet0 (WAN) = QEMU user network 10.0.2.0/24 with DHCP,
#          vtnet1 (LAN) = QEMU user network 192.168.1.0/24, guest LAN IP 192.168.1.1
#          host forwards: https://127.0.0.1:8443 -> LAN GUI, ssh -p 2223 127.0.0.1 -> LAN ssh
# Console: serial on stdio (Ctrl-A X to quit QEMU).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
# VM state (disks, firmware variables, pid/socket files, logs) lives outside
# the repository so that `git clean -fdx` cannot remove it.
S=${ARMSENSE_TESTVM_DIR:-$HOME/.armsense/testvm}
mkdir -p "$S"
# INSTANCE=<name> runs a second VM side by side: own EFI vars, pid, socket and
# forwarded ports (GUI_PORT/HTTP_PORT/SSH_FWD_PORT, defaults 8443/8080/2223).
INSTANCE=${INSTANCE:-test}
GUI_PORT=${GUI_PORT:-8443}
HTTP_PORT=${HTTP_PORT:-8080}
SSH_FWD_PORT=${SSH_FWD_PORT:-2223}
CODE=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
VARS=$S/efivars-$INSTANCE.fd
[ -f "$VARS" ] || cp /opt/homebrew/share/qemu/edk2-arm-vars.fd "$VARS"
MEM=${MEM:-2G}
CPUS=${CPUS:-2}
# SERIAL_LOG=<file>: run detached with the serial console written to the file
# (pid in $T/qemu.pid); otherwise interactive on stdio (Ctrl-A X quits).
if [ -n "${SERIAL_LOG:-}" ]; then
	SERIAL_OPTS="-serial file:$SERIAL_LOG -pidfile $S/qemu-$INSTANCE.pid -daemonize"
elif [ -n "${SERIAL_SOCK:-}" ]; then
	# detached, serial console on a unix socket; drive it with ./console.py
	rm -f "$S/serial-$INSTANCE.sock"
	SERIAL_OPTS="-serial unix:$S/serial-$INSTANCE.sock,server,nowait -pidfile $S/qemu-$INSTANCE.pid -daemonize"
else
	SERIAL_OPTS="-serial mon:stdio"
fi

mode=${1:-}; shift || true
case "$mode" in
disk)
	DISK=${1:?disk image}
	BOOT=""
	;;
iso)
	ISO=${1:?installer iso}
	DISK=${2:-$S/armsense-$INSTANCE.qcow2}
	[ -f "$DISK" ] || qemu-img create -q -f qcow2 "$DISK" 16G
	BOOT="-drive file=$ISO,if=none,id=cd0,format=raw,readonly=on -device virtio-blk-pci,drive=cd0,bootindex=0"
	;;
*)
	echo "usage: $0 disk <image.qcow2> | iso <installer.iso> [disk.qcow2]"; exit 1 ;;
esac

exec qemu-system-aarch64 \
	-name "armsense-$INSTANCE" \
	-machine virt,accel=hvf,gic-version=3 \
	-cpu host -smp "$CPUS" -m "$MEM" \
	-drive if=pflash,format=raw,readonly=on,file="$CODE" \
	-drive if=pflash,format=raw,file="$VARS" \
	-drive file="$DISK",if=none,id=hd0,format=qcow2,discard=unmap \
	-device virtio-blk-pci,drive=hd0,bootindex=1 \
	$BOOT \
	-netdev user,id=wan -device virtio-net-pci,netdev=wan,mac=52:54:00:aa:00:01 \
	-netdev user,id=lan,net=192.168.1.0/24,host=192.168.1.2,dhcpstart=192.168.1.200,hostfwd=tcp:127.0.0.1:${GUI_PORT}-192.168.1.1:443,hostfwd=tcp:127.0.0.1:${HTTP_PORT}-192.168.1.1:80,hostfwd=tcp:127.0.0.1:${SSH_FWD_PORT}-192.168.1.1:22 \
	-device virtio-net-pci,netdev=lan,mac=52:54:00:aa:00:02 \
	-device virtio-rng-pci \
	-display none -vga none \
	$SERIAL_OPTS
