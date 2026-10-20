#!/bin/sh
#
# phase1-base.sh -- build the FreeBSD world and the armsense kernel for arm64
# from the pfSense FreeBSD-src fork.  Runs inside the build VM as root.
#
# Usage: sh phase1-base.sh            (waits for the src clone, then builds)
#        NO_WORLD=1 sh phase1-base.sh (kernel only)
#
# Logs: /usr/armsense/logs/buildworld.log, buildkernel.log
#
set -eu

A=/usr/armsense
SRC=$A/src/FreeBSD-src
LOGS=$A/logs

# Same knobs the pfSense builder passes to build/scripts/build_freebsd.sh
# (see tools/builder_defaults.sh), with the file names that actually exist in
# the public fork's release/conf/.
export MAKEOBJDIRPREFIX=$A/obj
export SRCCONF=$SRC/release/conf/pfSense_build_src.conf
export __MAKE_CONF=$SRC/release/conf/pfSense_make.conf
export SRC_ENV_CONF=$SRC/release/conf/pfSense_src-env.conf
export TARGET=arm64
export TARGET_ARCH=aarch64
export KERNCONF=${KERNCONF:-armsense}

# Kernel modules.  pfSense's MODULES_OVERRIDE_base list from
# tools/builder_defaults.sh plus arm64-relevant extras; the amd64-only
# additions (aesni amdsmn amdtemp coretemp cpuctl cxgbe/tom drm2 ipmi ix ixv
# ndis nmdm qlnx sfxge vmm) are dropped.
export MODULES_OVERRIDE="${MODULES_OVERRIDE:-cc/cc_cdg cc/cc_chd cc/cc_cubic cc/cc_dctcp cc/cc_hd cc/cc_htcp cc/cc_vegas cryptodev dummynet fdescfs hwpmc i2c if_stf ipdivert ipfw ipfw_nat64 opensolaris usb/cdce usb/ipheth usb/ure usb/urndis zfs if_wg}"

ncpu=$(sysctl -n hw.ncpu)
J=$((ncpu * 2))

log() { echo ">>> $(date '+%F %T') $*"; }

# Wait for the shallow clone started at VM setup time.
while ! grep -q 'rc=0' "$LOGS/clone-FreeBSD-src.log" 2>/dev/null; do
	if grep -q 'rc=[1-9]' "$LOGS/clone-FreeBSD-src.log" 2>/dev/null; then
		log "FreeBSD-src clone failed:"; cat "$LOGS/clone-FreeBSD-src.log"; exit 1
	fi
	sleep 15
done
[ -f "$SRC/sys/sys/param.h" ] || { log "no source tree at $SRC"; exit 1; }

for f in "$SRCCONF" "$__MAKE_CONF" "$SRC_ENV_CONF"; do
	[ -f "$f" ] || { log "missing $f"; exit 1; }
done

# WITH_META_MODE (pfSense_src-env.conf) wants filemon(4).
kldload -n filemon 2>/dev/null || true

install -m 644 "$A/overlay/kernel/armsense" "$SRC/sys/arm64/conf/armsense"

log "source: $(git -C "$SRC" log -1 --format='%h %ad %s' --date=short)"
log "FreeBSD version: $(grep '#define __FreeBSD_version' "$SRC/sys/sys/param.h" | awk '{print $3}')"

cd "$SRC"
if [ -z "${NO_WORLD:-}" ]; then
	log "buildworld -j$J (log: $LOGS/buildworld.log)"
	if ! make -s -j"$J" buildworld > "$LOGS/buildworld.log" 2>&1; then
		log "buildworld FAILED"; tail -40 "$LOGS/buildworld.log"; exit 1
	fi
	log "buildworld done"
fi

log "buildkernel KERNCONF=$KERNCONF (log: $LOGS/buildkernel.log)"
if ! make -s -j"$J" buildkernel > "$LOGS/buildkernel.log" 2>&1; then
	log "buildkernel FAILED"; tail -40 "$LOGS/buildkernel.log"; exit 1
fi
log "buildkernel done"

K="$MAKEOBJDIRPREFIX$SRC/arm64.aarch64/sys/$KERNCONF/kernel"
ls -la "$K" 2>/dev/null || true
log "phase 1 complete"
