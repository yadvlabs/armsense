#!/bin/sh
#
# phase3-image.sh -- core packages and images for arm64 UEFI.
#
#   sh phase3-image.sh core    stage world + core packages (boot, kernel,
#                              kernel-debug, base) into the core repository
#   sh phase3-image.sh final   final chroot: stage world + core packages +
#                              port packages from poudriere
#   sh phase3-image.sh iso     installer ISO (hybrid ISO with EFI system partition)
#   sh phase3-image.sh disk    bootable disk image (GPT: ESP + swap + UFS root),
#                              raw and qcow2, for QEMU/KVM
#   sh phase3-image.sh all     everything above in order
#
# Mirrors build.sh / tools/builder_common.sh (make_world, build_all_kernels,
# clone_to_staging_area, customize_stagearea_for_image, create_memstick_image)
# plus what the public builder lacks: the boot package, the initial tarball,
# arm64 image creation, VM disk images.
#
# Requires: phase1-base.sh complete, rename-src.sh (both parts) run,
# phase2-poudriere.sh packages built.  Runs inside the build VM as root.
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
N=${PRODUCT_NAME:?}
: "${A:?}" "${SRC_FREEBSD:?}" "${SRC_PFSENSE:?}" "${LOGS:?}" "${OBJ:?}" "${JAIL_NAME:?}" "${PORTS_NAME:?}"

log() { echo ">>> $(date '+%F %T') $*"; }

export MAKEOBJDIRPREFIX=$OBJ
export TARGET=arm64 TARGET_ARCH=aarch64
export __MAKE_CONF=$SRC_FREEBSD/release/conf/pfSense_make.conf
export SRC_ENV_CONF=$SRC_FREEBSD/release/conf/pfSense_src-env.conf
SRCCONF_BUILD=$SRC_FREEBSD/release/conf/pfSense_build_src.conf
# The install-time confs only add knobs (WITHOUT_TOOLCHAIN, ...) on top of the
# build-time conf; applied alone they would try to install things that were
# never built (e.g. the test suite), so combine them.
SRCCONF_INSTALL=$A/src-install.conf
SRCCONF_INSTALLER=$A/src-installer.conf
cat "$SRCCONF_BUILD" "$SRC_FREEBSD/release/conf/pfSense_install_src.conf" > "$SRCCONF_INSTALL"
cat "$SRCCONF_BUILD" "$SRC_FREEBSD/release/conf/pfSense_installer_src.conf" > "$SRCCONF_INSTALLER"
export KERNCONF=${KERNCONF:-armsense}
# Must match phase1-base.sh, otherwise installkernel wants modules that were never built.
export MODULES_OVERRIDE="${MODULES_OVERRIDE:-cc/cc_cdg cc/cc_chd cc/cc_cubic cc/cc_dctcp cc/cc_hd cc/cc_htcp cc/cc_vegas cryptodev dummynet fdescfs hwpmc i2c if_stf ipdivert ipfw ipfw_nat64 opensolaris usb/cdce usb/ipheth usb/ure usb/urndis zfs if_wg}"

PRODUCT_VERSION=$(head -1 "$SRC_PFSENSE/src/etc/version")
[ -f "$A/datestring" ] || date '+%Y%m%d-%H%M' > "$A/datestring"
DATESTRING=$(cat "$A/datestring")
# builder_defaults.sh: DEVELOPMENT -> ".a.<date>" snapshot core package version
CORE_PKG_VERSION="${PRODUCT_VERSION%%-*}.a.$(echo "$DATESTRING" | tr - .)"
OSMAJOR=$(awk '/#define __FreeBSD_version/ {print int($3/100000)}' "$SRC_FREEBSD/sys/sys/param.h")
ABI="FreeBSD:${OSMAJOR}:aarch64"
ALTABI="freebsd:${OSMAJOR}:aarch64:64"

STAGE=$A/stage-dir
FINAL=$A/final-dir
INSTALLER=$A/installer-dir
KERNELS=$A/kernels
DISKROOT=$A/disk-root
REPO=$A/repo
CORE=$REPO/${JAIL_NAME}-core
CORE_REAL=$CORE/.real_$DATESTRING
PORTSREPO=/usr/local/poudriere/data/packages/${JAIL_NAME}-${PORTS_NAME}/.latest
IMAGES=$A/images
TEMPLATES=$SRC_PFSENSE/tools/templates/core_pkg
CREATE_CORE_PKG=$SRC_PFSENSE/build/scripts/create_core_pkg.sh
IMGBASE=${N}-${PRODUCT_VERSION}-arm64-${DATESTRING}

ncpu=$(sysctl -n hw.ncpu)
J=$((ncpu * 2))

# core_pkg template flavor root findroot [filter]
core_pkg() {
	env PRODUCT_NAME="$N" PRODUCT_URL="$PRODUCT_URL" sh "$CREATE_CORE_PKG" \
	    -t "$TEMPLATES/$1" -f "$2" -v "$CORE_PKG_VERSION" -r "$3" -s "$4" \
	    ${5:+-F "$5"} -d "$CORE_REAL/All" -a "$ABI" -A "$ALTABI"
}

# install_world srcconf destdir
install_world() {
	env SRCCONF="$1" DESTDIR="$2" make -C "$SRC_FREEBSD" -s -j"$J" installworld
	env SRCCONF="$1" DESTDIR="$2" make -C "$SRC_FREEBSD" -s distribution
}

# wipe dir -- remove a build directory under $A (refuses anything else)
wipe() {
	case "${1:?}" in
	"$A"/*) ;;
	*) log "refusing to remove $1"; exit 1 ;;
	esac
	[ -d "$1" ] || return 0
	chflags -R noschg "$1" 2>/dev/null || true
	rm -rf "${1:?}"
}

cleanup_mounts() {
	for m in dev tmp/repo-core tmp/repo-ports; do
		umount -f "${1:?}/$m" 2>/dev/null || true
	done
}

check_prereqs() {
	grep -q -h 'phase 1 complete' "$LOGS"/phase1*.log 2>/dev/null || { log "phase 1 not complete"; exit 1; }
	git -C "$SRC_FREEBSD" rev-parse -q --verify armsense >/dev/null || { log "run rename-src.sh freebsd first"; exit 1; }
	git -C "$SRC_FREEBSD" checkout -q armsense
	kldload -n filemon 2>/dev/null || true
	log "product $N $PRODUCT_VERSION, core packages $CORE_PKG_VERSION, ABI $ABI, kernel $KERNCONF"
}

core() {
	check_prereqs

	log "stage world: installworld (build+install src.conf) -> $STAGE (log: $LOGS/stage-installworld.log)"
	wipe "$STAGE"; mkdir -p "$STAGE"
	install_world "$SRCCONF_INSTALL" "$STAGE" > "$LOGS/stage-installworld.log" 2>&1

	log "kernel: installkernel $KERNCONF -> $KERNELS/$KERNCONF"
	wipe "$KERNELS/$KERNCONF"; mkdir -p "$KERNELS/$KERNCONF"
	env SRCCONF="$SRCCONF_BUILD" DESTDIR="$KERNELS/$KERNCONF" make -C "$SRC_FREEBSD" -s installkernel \
	    > "$LOGS/installkernel.log" 2>&1
	gzip -f9 "$KERNELS/$KERNCONF/boot/kernel/kernel"

	log "core packages -> $CORE_REAL/All"
	wipe "$CORE"; mkdir -p "$CORE_REAL/All"
	core_pkg kernel-debug "$KERNCONF" "$KERNELS/$KERNCONF" "./usr/lib/debug/boot" '*.debug'
	wipe "$KERNELS/$KERNCONF/usr"
	kfind="./boot/kernel"
	for d in modules dtb; do
		[ -d "$KERNELS/$KERNCONF/boot/$d" ] && kfind="$kfind ./boot/$d"
	done
	core_pkg kernel "$KERNCONF" "$KERNELS/$KERNCONF" "$kfind"
	# boot: loader and friends (the stage has no kernel, so ./boot is exactly that)
	core_pkg boot "" "$STAGE" "./boot"
	# base: the world as a tarball applied by the package's +INSTALL, with an
	# mtree for upgrades and the one-time 'initial' tarball
	mkdir -p "$STAGE/usr/local/share/$N"
	sed -e "s,%%PRODUCT_NAME%%,$N,g" "$TEMPLATES/base/exclude_files" > "$A/base_exclude_files"
	mtree -c -k uid,gid,mode,size,flags,sha256digest -p "$STAGE" -X "$A/base_exclude_files" \
	    > "$STAGE/usr/local/share/$N/base.mtree"
	tar -C "$STAGE" -cf - -X "$A/base_exclude_files" . | xz -T0 -6 > "$STAGE/usr/local/share/$N/base.txz"
	(cd "$SRC_PFSENSE/src" && tar -cf - $(sed -e "s,%%PRODUCT_NAME%%,$N,g" "$TEMPLATES/base/initial_files")) \
	    | xz -T0 > "$STAGE/usr/local/share/$N/initial.txz"
	core_pkg base "" "$STAGE" "."

	pkg repo -q "$CORE_REAL/"
	ln -sfn ".real_$DATESTRING" "$CORE/.latest"
	for f in "$CORE_REAL"/*; do ln -sfn ".latest/$(basename "$f")" "$CORE/$(basename "$f")"; done
	ls -la "$CORE_REAL/All"
	log "core packages done"
}

final() {
	check_prereqs
	[ -d "$PORTSREPO/All" ] || { log "no poudriere packages at $PORTSREPO"; exit 1; }
	[ -d "$CORE/.latest/All" ] || { log "no core packages; run 'core' first"; exit 1; }

	log "final chroot: clone stage -> $FINAL"
	cleanup_mounts "$FINAL"; wipe "$FINAL"; mkdir -p "$FINAL"
	tar -C "$STAGE" -cf - . | tar -C "$FINAL" -xpf -

	mkdir -p "$FINAL/tmp/repo-core" "$FINAL/tmp/repo-ports" "$FINAL/usr/local/etc/pkg/repos" "$FINAL/dev"
	mount -t nullfs -o ro "$(realpath "$CORE/.latest")" "$FINAL/tmp/repo-core"
	mount -t nullfs -o ro "$(realpath "$PORTSREPO")" "$FINAL/tmp/repo-ports"
	mount -t devfs devfs "$FINAL/dev"
	trap 'cleanup_mounts "$FINAL"' EXIT INT TERM
	# The product never uses the FreeBSD.org repositories.
	rm -f "$FINAL/etc/pkg/FreeBSD.conf"
	cat > "$FINAL/usr/local/etc/pkg/repos/build.conf" <<EOC
${N}-core: { url: "file:///tmp/repo-core", signature_type: "none", enabled: yes, priority: 10 }
${N}-ports: { url: "file:///tmp/repo-ports", signature_type: "none", enabled: yes }
EOC
	pkgc() { env ASSUME_ALWAYS_YES=yes IGNORE_OSVERSION=yes chroot "$FINAL" /usr/local/sbin/pkg "$@"; }
	log "pkg bootstrap"
	env ASSUME_ALWAYS_YES=yes chroot "$FINAL" /usr/sbin/pkg bootstrap -f > "$LOGS/final-pkg.log" 2>&1
	# pkg's bootstrap drops a FreeBSD.org repository definition; the product never uses it.
	rm -f "$FINAL/usr/local/etc/pkg/repos/FreeBSD.conf"
	log "installing core packages (log: $LOGS/final-pkg.log)"
	pkgc install "${N}-boot" "${N}-kernel-${KERNCONF}" "${N}-base" >> "$LOGS/final-pkg.log" 2>&1
	pkgc set -v 1 "${N}-boot" "${N}-kernel-${KERNCONF}" "${N}-base" >> "$LOGS/final-pkg.log" 2>&1
	log "installing product packages"
	pkgc install "$N" "${N}-ce" "${N}-repo" "${N}-default-config-serial" qemu-guest-agent >> "$LOGS/final-pkg.log" 2>&1
	pkgc set -A 0 pkg "$N" "${N}-ce" "${N}-repo" "${N}-default-config-serial" qemu-guest-agent >> "$LOGS/final-pkg.log" 2>&1
	pkgc set -v 1 pkg "$N" >> "$LOGS/final-pkg.log" 2>&1
	pkgc autoremove >> "$LOGS/final-pkg.log" 2>&1 || true
	log "$(pkgc info | wc -l | tr -d ' ') packages installed"

	# Loader settings for a UEFI machine with serial + EFI console; the product
	# rewrites /boot/loader.conf from its configuration on later boots.
	cat > "$FINAL/boot/loader.conf" <<EOC
autoboot_delay="3"
# arm64 loader consoles are efi/eficom only; under UEFI the kernel console
# follows the firmware (SPCR / EFI ConOut), e.g. the PL011 serial port on QEMU.
console="efi"
EOC

	rm -f "$FINAL/usr/local/etc/pkg/repos/build.conf" "$FINAL/usr/local/etc/pkg/repos/FreeBSD.conf"
	echo "  pkg.conf: $(tr '\n' ' ' < "$FINAL/usr/local/etc/pkg.conf")"
	cleanup_mounts "$FINAL"; trap - EXIT INT TERM
	rmdir "$FINAL/tmp/repo-core" "$FINAL/tmp/repo-ports" 2>/dev/null || true
	rm -rf "${FINAL:?}/var/cache/pkg" "${FINAL:?}/var/db/pkg/repos"
	mkdir -p "$FINAL/var/cache/pkg"

	log "sanity"
	for f in boot/kernel/kernel.gz boot/loader.efi etc/$N-rc etc/platform etc/version usr/local/www/index.php \
	    usr/local/etc/pkg/repos/$N.conf conf.default/config.xml cf/conf/config.xml usr/sbin/gnid usr/local/sbin/$N-repoc; do
		if [ -e "$FINAL/$f" ] || [ -L "$FINAL/$f" ]; then echo "  ok  /$f"; else echo "  MISSING /$f"; fi
	done
	echo "  product_name: $(grep "'product_name'" "$FINAL/etc/inc/globals.inc")"
	echo "  platform: $(cat "$FINAL/etc/platform") version: $(cat "$FINAL/etc/version")"
	log "final chroot done"
}

iso() {
	check_prereqs
	[ -x "$FINAL/bin/sh" ] || { log "no final chroot; run 'final' first"; exit 1; }

	log "installer chroot: installworld (build+installer src.conf) -> $INSTALLER (log: $LOGS/installer-installworld.log)"
	wipe "$INSTALLER"; mkdir -p "$INSTALLER"
	env SRCCONF="$SRCCONF_INSTALLER" DESTDIR="$INSTALLER" WITHOUT_RESCUE=yes \
	    make -C "$SRC_FREEBSD" -s -j"$J" installworld > "$LOGS/installer-installworld.log" 2>&1
	env SRCCONF="$SRCCONF_INSTALLER" DESTDIR="$INSTALLER" \
	    make -C "$SRC_FREEBSD" -s installkernel >> "$LOGS/installer-installworld.log" 2>&1
	gzip -f9 "$INSTALLER/boot/kernel/kernel"
	env SRCCONF="$SRCCONF_INSTALLER" DESTDIR="$INSTALLER" WITHOUT_RESCUE=yes \
	    make -C "$SRC_FREEBSD" -s distribution >> "$LOGS/installer-installworld.log" 2>&1
	cp "$SRC_FREEBSD/release/rc.local" "$INSTALLER/etc/"
	install -m 0755 "$SRC_PFSENSE"/tools/installer/*.sh "$INSTALLER/root/"
	pw -R "$INSTALLER" usermod root -w yes
	cat > "$INSTALLER/boot/loader.conf" <<EOC
autoboot_delay="3"
kern.cam.boot_delay=10000
# arm64 loader consoles are efi/eficom only; under UEFI the kernel console
# follows the firmware (SPCR / EFI ConOut), e.g. the PL011 serial port on QEMU.
console="efi"
EOC

	log "distribution set from the final chroot"
	mkdir -p "$INSTALLER/usr/freebsd-dist"
	tar -C "$FINAL" --exclude ./pkgs -cf - . | xz -T0 -6 > "$INSTALLER/usr/freebsd-dist/base.txz"
	(cd "$INSTALLER/usr/freebsd-dist" && sh "$SRC_FREEBSD/release/scripts/make-manifest.sh" base.txz > MANIFEST)
	cat "$INSTALLER/usr/freebsd-dist/MANIFEST"

	mkdir -p "$IMAGES"
	rm -f "$IMAGES/$IMGBASE.iso"
	log "ISO: $IMAGES/$IMGBASE.iso"
	sh "$SRC_FREEBSD/release/arm64/mkisoimages.sh" -b "$(echo "$N" | tr '[:lower:]' '[:upper:]')" \
	    "$IMAGES/$IMGBASE.iso" "$INSTALLER"
	ls -la "$IMAGES/$IMGBASE.iso"
	log "ISO done"
}

# make_esp file sizekb loader  (from tools/boot/install-boot.sh, arm64 only)
make_esp() {
	local stage
	stage=$(mktemp -d /tmp/esp.XXXXXX)
	mkdir -p "$stage/EFI/BOOT"
	cp "$3" "$stage/EFI/BOOT/bootaa64.efi"
	makefs -t msdos -o fat_type=32 -o sectors_per_cluster=1 -o volume_label=EFISYS -s "$2k" "$1" "$stage"
	rm -rf "${stage:?}"
}

disk() {
	check_prereqs
	[ -x "$FINAL/bin/sh" ] || { log "no final chroot; run 'final' first"; exit 1; }
	pkg info -e qemu-tools || env ASSUME_ALWAYS_YES=yes pkg install qemu-tools > /dev/null

	log "disk root: clone final -> $DISKROOT"
	wipe "$DISKROOT"; mkdir -p "$DISKROOT"
	tar -C "$FINAL" -cf - . | tar -C "$DISKROOT" -xpf -
	mkdir -p "$DISKROOT/boot/efi"
	cat > "$DISKROOT/etc/fstab" <<EOC
/dev/gpt/${N}		/		ufs	rw	1	1
/dev/gpt/efiboot0	/boot/efi	msdosfs	rw	2	2
/dev/gpt/swap0		none		swap	sw	0	0
EOC
	# QEMU/KVM virtio NICs: WAN = first, LAN = second.
	for c in "$DISKROOT/conf.default/config.xml" "$DISKROOT/cf/conf/config.xml"; do
		[ -f "$c" ] || continue
		xml ed -L -P -u '/pfsense/interfaces/wan/if' -v vtnet0 -u '/pfsense/interfaces/lan/if' -v vtnet1 "$c"
	done
	# Grow the root file system to the partition on first boot.
	touch "$DISKROOT/root/force_growfs"

	log "file systems"
	rm -f "$A/root.ufs" "$A/esp.img"
	makefs -t ffs -B little -o label="$N",version=2,softupdates=1 -s "${DISK_ROOT_SIZE:-6g}" "$A/root.ufs" "$DISKROOT"
	make_esp "$A/esp.img" 33292 "$DISKROOT/boot/loader.efi"

	mkdir -p "$IMAGES"
	rm -f "$IMAGES/$IMGBASE.raw" "$IMAGES/$IMGBASE.qcow2"
	log "disk image: $IMAGES/$IMGBASE.raw"
	mkimg -s gpt -f raw \
	    -p efi/efiboot0:="$A/esp.img" \
	    -p freebsd-swap/swap0::1g \
	    -p freebsd-ufs/"$N":="$A/root.ufs" \
	    -o "$IMAGES/$IMGBASE.raw"
	qemu-img convert -f raw -O qcow2 -c "$IMAGES/$IMGBASE.raw" "$IMAGES/$IMGBASE.qcow2"
	rm -f "$A/root.ufs" "$A/esp.img"
	ls -la "$IMAGES"
	log "disk image done"
}

case "${1:-all}" in
core) core ;;
final) final ;;
iso) iso ;;
disk) disk ;;
all) core; final; iso; disk ;;
*) echo "usage: $0 [core|final|iso|disk|all]"; exit 1 ;;
esac
