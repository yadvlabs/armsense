#!/bin/sh
#
# clean-build.sh -- rebuild everything from the pinned sources.
#
# Re-cuts the armsense branches from the pinned upstream branches, removes all
# build output (objects, poudriere jail and packages, staging areas, core
# repository, images, build date) and runs phases 1 to 3.  The distfiles cache
# is kept (upstream source tarballs, verified by checksum); the compiler cache
# is cleared unless --keep-ccache is given.
#
# Usage: sh clean-build.sh [--keep-ccache]
# Log:   /usr/armsense/logs/clean-build.log (phase logs alongside)
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
: "${A:?}" "${OBJ:?}" "${JAILROOT:?}" "${LOGS:?}" "${JAIL_NAME:?}" "${PORTS_NAME:?}"

keep_ccache=
for a in "$@"; do
	case "$a" in
	--keep-ccache) keep_ccache=1 ;;
	*) echo "usage: $0 [--keep-ccache]"; exit 1 ;;
	esac
done

log() { echo ">>> $(date '+%F %T') $*"; }

wipe() {
	case "${1:?}" in
	"$A"/*|/usr/local/poudriere/data/*) ;;
	*) log "refusing to remove $1"; exit 1 ;;
	esac
	[ -e "$1" ] || return 0
	chflags -R noschg "$1" 2>/dev/null || true
	rm -rf "${1:?}"
}

start=$(date +%s)
log "clean build started"

log "sources: re-cutting the armsense branches"
sh "$HERE/../src/rename-src.sh" all > "$LOGS/rename-src.log" 2>&1
sh "$HERE/../ports/prepare-ports.sh" > "$LOGS/prepare-ports.log" 2>&1
for r in pfsense FreeBSD-src FreeBSD-ports; do
	printf '  %-14s %s\n' "$r" "$(git -C "$A/src/$r" log -1 --format='%h %s' armsense)"
done

log "removing previous build output"
if [ -f /usr/local/etc/poudriere.conf ]; then
	if poudriere jail -i -j "$JAIL_NAME" >/dev/null 2>&1; then poudriere jail -d -j "$JAIL_NAME" >/dev/null; fi
	if poudriere ports -l 2>/dev/null | grep -q "^$PORTS_NAME[[:space:]]"; then poudriere ports -d -p "$PORTS_NAME" >/dev/null; fi
fi
for d in "$OBJ" "$JAILROOT" \
    "/usr/local/poudriere/data/packages/${JAIL_NAME}-${PORTS_NAME}" \
    "/usr/local/poudriere/data/logs/bulk/${JAIL_NAME}-${PORTS_NAME}" \
    "/usr/local/poudriere/data/cache" \
    "$A/stage-dir" "$A/final-dir" "$A/installer-dir" "$A/disk-root" "$A/smoke-root" \
    "$A/kernels" "$A/repo" "$A/images" "$A/tmpfs-blacklist"; do
	wipe "$d"
done
rm -f "$A/datestring" "$A/pfsense-commit.built" "$A/base_exclude_files" "$A/bulk-core.txt" \
    "$A/root.ufs" "$A/esp.img" "$A/smoke.ufs" "$A/smoke-esp.img" "$A/src-install.conf" "$A/src-installer.conf"
[ -n "$keep_ccache" ] || { wipe "$A/ccache"; mkdir -p "$A/ccache"; }
mkdir -p "$A/images"

log "phase 1: world and kernel"
sh "$HERE/phase1-base.sh" > "$LOGS/phase1.log" 2>&1
grep -q 'phase 1 complete' "$LOGS/phase1.log"

log "phase 2: packages"
sh "$HERE/phase2-poudriere.sh" setup > "$LOGS/phase2-setup.log" 2>&1
sh "$HERE/phase2-poudriere.sh" bulk > "$LOGS/phase2-bulk.log" 2>&1 || true
grep -E 'Built:.*Failed:' "$LOGS/phase2-bulk.log" | tail -1 | grep -o 'Built: [0-9]* *Failed: [0-9]* *Skipped: [0-9]*'
grep -q 'Failed: 0 ' "$LOGS/phase2-bulk.log" || { log "package build had failures"; grep -E 'Failed ports' "$LOGS/phase2-bulk.log"; exit 1; }

log "phase 3: core packages and images"
for st in core final iso disk; do
	sh "$HERE/phase3-image.sh" "$st" > "$LOGS/phase3-$st.log" 2>&1
done

end=$(date +%s)
log "clean build finished in $(( (end - start) / 60 )) minutes"
ls -la "$A/images"
