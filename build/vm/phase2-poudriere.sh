#!/bin/sh
#
# phase2-poudriere.sh -- package build.
#
#   sh phase2-poudriere.sh setup   install the phase-1 world into a jail root,
#                                  configure poudriere, register jail + ports
#                                  tree, write make.conf
#   sh phase2-poudriere.sh bulk    build the core package set
#   sh phase2-poudriere.sh rebuild <origin>...  force-rebuild ports after edits
#   sh phase2-poudriere.sh         both
#
# Requires: phase1-base.sh finished (buildworld), rename-src.sh pfsense and
# prepare-ports.sh run (armsense branches + source tarball present).
# Runs inside the build VM as root.
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
N=$PRODUCT_NAME

log() { echo ">>> $(date '+%F %T') $*"; }

export MAKEOBJDIRPREFIX=$OBJ
export SRCCONF=$SRC_FREEBSD/release/conf/pfSense_build_src.conf
export __MAKE_CONF=$SRC_FREEBSD/release/conf/pfSense_make.conf
export SRC_ENV_CONF=$SRC_FREEBSD/release/conf/pfSense_src-env.conf
export TARGET=arm64 TARGET_ARCH=aarch64

ncpu=$(sysctl -n hw.ncpu)
J=$((ncpu * 2))

setup() {
	grep -q -h 'buildworld done\|phase 1 complete' "$LOGS"/phase1*.log 2>/dev/null || { log "phase 1 buildworld has not finished"; exit 1; }
	[ -f "$A/pfsense-commit" ] || { log "run rename-src.sh pfsense first"; exit 1; }
	git -C "$SRC_PORTS" rev-parse -q --verify armsense >/dev/null || { log "run prepare-ports.sh first"; exit 1; }
	git -C "$SRC_PORTS" checkout -q armsense

	# 1. Jail root: the phase-1 world with toolchain (pfSense_build_src.conf),
	#    installed the same way build/scripts/install_freebsd.sh does.
	if [ ! -x "$JAILROOT/bin/sh" ]; then
		log "installworld + distribution into $JAILROOT (log: $LOGS/jail-installworld.log)"
		mkdir -p "$JAILROOT"
		kldload -n filemon 2>/dev/null || true
		make -C "$SRC_FREEBSD" -s -j"$J" DESTDIR="$JAILROOT" installworld > "$LOGS/jail-installworld.log" 2>&1
		make -C "$SRC_FREEBSD" -s DESTDIR="$JAILROOT" distribution >> "$LOGS/jail-installworld.log" 2>&1
	fi
	log "jail root FreeBSD version: $(awk '/#define __FreeBSD_version/ {print $3}' "$JAILROOT/usr/include/sys/param.h")"

	# 2. poudriere.conf (modelled on poudriere_init() in tools/builder_common.sh).
	mkdir -p "$DISTFILES" "$A/ccache" "$A/tmpfs-blacklist" /usr/local/etc/poudriere.d
	cat > /usr/local/etc/poudriere.conf <<EOC
ZPOOL=zroot
ZROOTFS=/poudriere
FREEBSD_HOST=https://download.FreeBSD.org
RESOLV_CONF=/etc/resolv.conf
BASEFS=/usr/local/poudriere
USE_PORTLINT=no
USE_TMPFS="wrkdir data"
TMPFS_BLACKLIST="rust llvm* gcc*"
TMPFS_BLACKLIST_TMPDIR=$A/tmpfs-blacklist
NOLINUX=yes
DISTFILES_CACHE=$DISTFILES
CHECK_CHANGED_OPTIONS=verbose
CHECK_CHANGED_DEPS=yes
ATOMIC_PACKAGE_REPOSITORY=yes
COMMIT_PACKAGES_ON_FAILURE=yes
KEEP_OLD_PACKAGES=no
ALLOW_MAKE_JOBS=yes
PARALLEL_JOBS=4
PREPARE_PARALLEL_JOBS=4
CCACHE_DIR=$A/ccache
BUILDER_HOSTNAME=armsense-build
MAX_EXECUTION_TIME=172800
NOHANG_TIME=14400
EOC

	# 3. Jail: null-mounted jail root, our source tree for kmod ports.
	if ! poudriere jail -i -j "$JAIL_NAME" >/dev/null 2>&1; then
		log "creating poudriere jail $JAIL_NAME"
		poudriere jail -c -j "$JAIL_NAME" -a arm64.aarch64 -m null -M "$JAILROOT" \
		    -S "$SRC_FREEBSD" -v 16.0-CURRENT
	fi
	poudriere jail -i -j "$JAIL_NAME" | grep -E 'Jail name|version|arch|method|path'

	# 4. Ports tree: the patched, renamed clone, null-mounted.
	if ! poudriere ports -l | grep -q "^$PORTS_NAME[[:space:]]"; then
		log "registering ports tree $PORTS_NAME"
		poudriere ports -c -p "$PORTS_NAME" -m null -M "$SRC_PORTS"
	fi

	# 5. make.conf: pfSense's options file plus the values poudriere_bulk()
	#    appends, plus the glue Netgate's private CI normally provides.
	PRODUCT_VERSION=$(head -1 "$SRC_PFSENSE/src/etc/version")
	PFSENSE_COMMITHASH=$(cat "$A/pfsense-commit")
	if [ ! -f "$A/datestring" ]; then date '+%Y%m%d-%H%M' > "$A/datestring"; fi
	DATESTRING=$(cat "$A/datestring")
	MC=/usr/local/etc/poudriere.d/${JAIL_NAME}-${PORTS_NAME}-make.conf
	sed -e "s,%%PRODUCT_NAME%%,$N,g" -e "s,%%PRODUCT_VERSION%%,$PRODUCT_VERSION,g" \
	    "$SRC_PFSENSE/tools/conf/pfPorts/make.conf" > "$MC"
	cat >> "$MC" <<EOC

# --- appended by poudriere_bulk() in the pfSense builder ---
PKG_REPO_BRANCH_DEVEL=$PORTS_BRANCH
PKG_REPO_BRANCH_RELEASE=$PORTS_BRANCH
PKG_REPO_SERVER_DEVEL=$PKG_REPO_SERVER
PKG_REPO_SERVER_RELEASE=$PKG_REPO_SERVER
POUDRIERE_PORTS_NAME=$PORTS_NAME
PFSENSE_DEFAULT_REPO=${N}-repo-devel
PRODUCT_NAME=$N
REPO_BRANCH_PREFIX=

# --- glue that Netgate's private CI provides ---
PRODUCT_VERSION=$PRODUCT_VERSION
PRODUCT_URL=$PRODUCT_URL
PFSENSE_COMMITHASH=$PFSENSE_COMMITHASH
PFSENSE_DATESTRING=$(date)
MIRROR_TYPE=none
SIGNATURE_TYPE=none
MAKE_JOBS_NUMBER=4
WARNING_WAIT=0
DEV_WARNING_WAIT=0
EOC
	log "make.conf: $MC"

	# Snapshot versioning of the meta ports, as poudriere_bulk() does.
	meta_version="$(echo "$PRODUCT_VERSION" | sed 's,DEVELOPMENT,ALPHA,')-$DATESTRING"
	sed -i '' -e "/^DISTVERSION/ s,^.*,DISTVERSION=	$meta_version," -e "/^PORTREVISION=/d" \
	    "$SRC_PORTS/security/$N/Makefile" "$SRC_PORTS/sysutils/$N-repo/Makefile"

	# If the GUI source commit changed, drop the stale -system package so poudriere rebuilds it.
	pkgdir=/usr/local/poudriere/data/packages/${JAIL_NAME}-${PORTS_NAME}
	if [ -f "$A/pfsense-commit.built" ] && [ "$(cat "$A/pfsense-commit.built")" != "$PFSENSE_COMMITHASH" ]; then
		log "GUI source changed, removing stale $N-system package"
		rm -f "$pkgdir"/.latest/All/$N-system-*.pkg "$pkgdir"/All/$N-system-*.pkg 2>/dev/null || true
	fi

	sed "s,%%PRODUCT_NAME%%,$N,g" "$HERE/../ports/bulk-core.txt" > "$A/bulk-core.txt"
	log "setup complete"
}

bulk() {
	PFSENSE_COMMITHASH=$(cat "$A/pfsense-commit")
	log "poudriere bulk $JAIL_NAME / $PORTS_NAME"
	log "logs: /usr/local/poudriere/data/logs/bulk/${JAIL_NAME}-${PORTS_NAME}/latest/"
	rc=0
	poudriere bulk -j "$JAIL_NAME" -p "$PORTS_NAME" -f "$A/bulk-core.txt" || rc=$?
	echo "$PFSENSE_COMMITHASH" > "$A/pfsense-commit.built"
	log "poudriere bulk finished rc=$rc"
	return $rc
}

# rebuild origin... -- force a rebuild of the given ports (and their dependents);
# poudriere does not notice Makefile/files edits that leave the package version alone.
rebuild() {
	[ $# -gt 0 ] || { echo "usage: $0 rebuild origin..."; exit 1; }
	log "forced rebuild: $*"
	poudriere bulk -C -j "$JAIL_NAME" -p "$PORTS_NAME" "$@"
}

case "${1:-all}" in
setup) setup ;;
bulk) bulk ;;
rebuild) shift; rebuild "$@" ;;
all) setup; bulk ;;
*) echo "usage: $0 [setup|bulk|rebuild origin...|all]"; exit 1 ;;
esac
