#!/bin/sh
# Start (or report) the armsense FreeBSD arm64 build VM under QEMU/HVF.
# Usage: ./run.sh [start|stop|status|console]
set -e
B=$(cd "$(dirname "$0")" && pwd)
DISK=${DISK:-$B/armsense-build.qcow2}
SEED=$B/seed.iso
CODE=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
VARS=$B/efivars.fd
PID=$B/qemu.pid
MON=$B/monitor.sock
SERIAL=$B/serial.log
SSH_PORT=${SSH_PORT:-2222}
CPUS=${CPUS:-10}
MEM=${MEM:-32G}

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; }

case "${1:-start}" in
start)
	if running; then echo "already running (pid $(cat "$PID"))"; exit 0; fi
	[ -f "$DISK" ] || { echo "missing $DISK"; exit 1; }
	: > "$SERIAL"
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
		-monitor unix:"$MON",server,nowait \
		-pidfile "$PID" -daemonize
	;;
stop)
	if running; then
		echo system_powerdown | nc -U "$MON" >/dev/null 2>&1 || true
		for i in $(seq 1 60); do running || { echo "stopped"; exit 0; }; sleep 1; done
		echo "forcing"; kill "$(cat "$PID")"
	else
		echo "not running"
	fi
	;;
status)
	if running; then echo "running (pid $(cat "$PID")), ssh port $SSH_PORT"; else echo "not running"; fi
	;;
console)
	tail -f "$SERIAL"
	;;
*)
	echo "usage: $0 [start|stop|status|console]"; exit 1
	;;
esac
