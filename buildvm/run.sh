#!/bin/sh
# Start, stop or inspect the armsense FreeBSD arm64 build VM (QEMU/HVF on macOS).
# Usage: ./run.sh [start|stop|status|console|monitor]
# State lives in $ARMSENSE_VM_DIR (default ~/.armsense/buildvm); see setup-vm.sh.
set -eu
. "$(dirname "$0")/common.sh"

case "${1:-start}" in
start)
	if vm_running; then echo "already running (pid $(cat "$PIDFILE")), ssh port $SSH_PORT"; exit 0; fi
	[ -f "$DISK" ] || { echo "missing $DISK; run setup-vm.sh first"; exit 1; }
	[ -f "$SEED" ] || { echo "missing $SEED; run setup-vm.sh first"; exit 1; }
	[ -f "$VARS" ] || cp "$VARS_TEMPLATE" "$VARS"
	: > "$SERIAL"
	rm -f "$MONITOR"
	exec qemu-system-aarch64 \
		-name armsense-build \
		-machine virt,accel=hvf,gic-version=3 \
		-cpu host -smp "$CPUS" -m "$MEM" \
		-drive if=pflash,format=raw,readonly=on,file="$CODE" \
		-drive if=pflash,format=raw,file="$VARS" \
		-drive file="$DISK",if=none,id=hd0,format=qcow2,cache=writeback,discard=unmap \
		-device virtio-blk-pci,drive=hd0,bootindex=0 \
		-drive file="$SEED",if=none,id=cd0,format=raw,readonly=on \
		-device virtio-blk-pci,drive=cd0 \
		-netdev user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22 \
		-device virtio-net-pci,netdev=net0 \
		-device virtio-rng-pci \
		-display none -vga none \
		-serial file:"$SERIAL" \
		-monitor unix:"$MONITOR",server,nowait \
		-pidfile "$PIDFILE" -daemonize
	;;
stop)
	if vm_running; then
		echo system_powerdown | nc -U "$MONITOR" >/dev/null 2>&1 || true
		for i in $(seq 1 90); do vm_running || { echo "stopped"; exit 0; }; sleep 1; done
		echo "forcing"; kill "$(cat "$PIDFILE")"
	else
		echo "not running"
	fi
	;;
status)
	if vm_running; then echo "running (pid $(cat "$PIDFILE")), ssh port $SSH_PORT, state $S"; else echo "not running (state $S)"; fi
	;;
console)
	tail -f "$SERIAL"
	;;
monitor)
	# QEMU human monitor; e.g. 'info block', 'drive_backup -f hd0 /path/copy.qcow2 qcow2'
	nc -U "$MONITOR"
	;;
*)
	echo "usage: $0 [start|stop|status|console|monitor]"; exit 1
	;;
esac
