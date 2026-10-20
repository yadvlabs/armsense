#!/bin/sh
#
# smoke-disk.sh -- minimal bootable disk (stage world + armsense kernel, plain
# FreeBSD rc, no product packages) to validate the UEFI loader, kernel, virtio
# and serial console path before the package build has finished.
#
# Output: /usr/armsense/images/smoke-<date>.qcow2  (root login without password)
#
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../armsense.conf"
: "${A:?}" "${LOGS:?}"
KERNCONF=${KERNCONF:-armsense}
STAGE=$A/stage-dir
KERNEL=$A/kernels/$KERNCONF
R=$A/smoke-root
IMAGES=$A/images

log() { echo ">>> $(date '+%F %T') $*"; }

[ -x "$STAGE/bin/sh" ] || { log "no stage world; run phase3-image.sh core first"; exit 1; }
[ -f "$KERNEL/boot/kernel/kernel.gz" ] || { log "no installed kernel at $KERNEL"; exit 1; }
pkg info -e qemu-tools || env ASSUME_ALWAYS_YES=yes pkg install qemu-tools > /dev/null

log "root: stage world + kernel -> $R"
chflags -R noschg "$R" 2>/dev/null || true
rm -rf "${R:?}"; mkdir -p "$R"
tar -C "$STAGE" -cf - . | tar -C "$R" -xpf -
tar -C "$KERNEL" -cf - ./boot | tar -C "$R" -xpf -
mkdir -p "$R/boot/efi"
cat > "$R/etc/fstab" <<EOF
/dev/gpt/smoke		/		ufs	rw	1	1
/dev/gpt/efiboot0	/boot/efi	msdosfs	rw	2	2
EOF
cat > "$R/boot/loader.conf" <<EOF
autoboot_delay="3"
# arm64 loader consoles are efi/eficom only; under UEFI the kernel console
# follows the firmware (SPCR / EFI ConOut), e.g. the PL011 serial port on QEMU.
console="efi"
EOF
cat > "$R/etc/rc.conf" <<EOF
hostname="armsense-smoke"
ifconfig_vtnet0="DHCP"
ifconfig_vtnet1="inet 192.168.1.1/24"
sendmail_enable="NONE"
EOF
# root without password for the serial console
pw -R "$R" usermod root -w none

log "file systems and image"
rm -f "$A/smoke.ufs" "$A/smoke-esp.img"
makefs -t ffs -B little -o label=smoke,version=2,softupdates=1 -s 3g "$A/smoke.ufs" "$R"
esp=$(mktemp -d /tmp/esp.XXXXXX)
mkdir -p "$esp/EFI/BOOT"
cp "$R/boot/loader.efi" "$esp/EFI/BOOT/bootaa64.efi"
makefs -t msdos -o fat_type=32 -o sectors_per_cluster=1 -o volume_label=EFISYS -s 33292k "$A/smoke-esp.img" "$esp"
rm -rf "${esp:?}"
mkdir -p "$IMAGES"
out=$IMAGES/smoke-$(date +%Y%m%d-%H%M)
mkimg -s gpt -f raw -p efi/efiboot0:="$A/smoke-esp.img" -p freebsd-ufs/smoke:="$A/smoke.ufs" -o "$out.raw"
qemu-img convert -f raw -O qcow2 -c "$out.raw" "$out.qcow2"
rm -f "$out.raw" "$A/smoke.ufs" "$A/smoke-esp.img"
ls -la "$out.qcow2"
log "smoke image: $out.qcow2"
