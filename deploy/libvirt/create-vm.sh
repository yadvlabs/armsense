#!/bin/sh
#
# create-vm.sh -- create and start an armsense virtual machine on a
# libvirt/KVM host: an arm64 Linux machine such as a Raspberry Pi 5.
#
# Copies the qcow2 image into the libvirt images directory (optionally
# growing it), renders armsense.xml.in next to this script (UEFI firmware
# without Secure Boot, virtio disk, two virtio NICs, serial console), defines
# the domain and starts it.
#
# usage: create-vm.sh -i IMAGE.qcow2 -w WAN -l LAN [-n NAME] [-m MB] [-c N]
#                     [-s SIZE] [-d DIR] [-N] [-x]
#   -i IMAGE  armsense-*.qcow2 from the releases page
#   -w WAN    first NIC (WAN): a host bridge name, or network=NAME for a
#             libvirt network (for example network=default)
#   -l LAN    second NIC (LAN): same forms
#   -n NAME   domain name (default: armsense)
#   -m MB     memory in MiB (default: 4096)
#   -c N      vCPUs (default: 2)
#   -s SIZE   grow the disk to SIZE before the first boot, e.g. 16G; the
#             first boot expands the root file system to fill the disk
#   -d DIR    libvirt images directory (default: /var/lib/libvirt/images)
#   -N        define the domain but do not start it
#   -x        print the rendered XML and exit; nothing is created
#
# Run as root (or as a user allowed to manage qemu:///system).
set -eu

name=armsense memory=4096 vcpus=2 size= dir=/var/lib/libvirt/images image= wan= lan= start=1 dryrun=
usage() { sed -n '/^# usage:/,/^# Run as/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
die() { echo "create-vm.sh: $*" >&2; exit 1; }

while getopts i:w:l:n:m:c:s:d:Nxh opt; do
	case $opt in
	i) image=$OPTARG ;;  w) wan=$OPTARG ;;  l) lan=$OPTARG ;;  n) name=$OPTARG ;;
	m) memory=$OPTARG ;; c) vcpus=$OPTARG ;; s) size=$OPTARG ;; d) dir=$OPTARG ;;
	N) start= ;;         x) dryrun=1 ;;     h) usage 0 ;;      *) usage ;;
	esac
done
[ -n "$image" ] && [ -n "$wan" ] && [ -n "$lan" ] || usage
case $name in *[!A-Za-z0-9._-]*|'') die "domain name may contain letters, digits, . _ - only" ;; esac

here=$(cd "$(dirname "$0")" && pwd)
template=$here/armsense.xml.in
[ -f "$template" ] || die "$template not found; keep create-vm.sh and armsense.xml.in together"

# "br0" or "bridge=br0" -> bridge; "network=default" -> libvirt network
nic_type() { case $1 in network=*) echo network ;; *) echo bridge ;; esac; }
nic_name() { echo "${1#*=}"; }

disk=$dir/$name.qcow2
render() {
	sed -e "s|@NAME@|$name|g" -e "s|@MEMORY_MB@|$memory|g" -e "s|@VCPUS@|$vcpus|g" \
	    -e "s|@DISK@|$disk|g" \
	    -e "s|@WAN_TYPE@|$(nic_type "$wan")|g" -e "s|@WAN_SOURCE@|$(nic_type "$wan")='$(nic_name "$wan")'|g" \
	    -e "s|@LAN_TYPE@|$(nic_type "$lan")|g" -e "s|@LAN_SOURCE@|$(nic_type "$lan")='$(nic_name "$lan")'|g" \
	    "$template"
}

if [ -n "$dryrun" ]; then render; exit 0; fi

command -v virsh >/dev/null || die "virsh not found (install libvirt)"
command -v qemu-img >/dev/null || die "qemu-img not found (install qemu-utils)"
[ "$(uname -m)" = aarch64 ] || die "this creates a KVM guest for arm64; the host is $(uname -m)"
[ -f "$image" ] || die "image $image not found"
[ -d "$dir" ] || die "images directory $dir not found"
[ ! -e "$disk" ] || die "$disk exists; choose another name (-n) or remove it"
if virsh dominfo "$name" >/dev/null 2>&1; then die "domain $name already exists"; fi
[ "$(nic_type "$wan")" = network ] && ! virsh net-info "$(nic_name "$wan")" >/dev/null 2>&1 && die "libvirt network $(nic_name "$wan") not found"
[ "$(nic_type "$lan")" = network ] && ! virsh net-info "$(nic_name "$lan")" >/dev/null 2>&1 && die "libvirt network $(nic_name "$lan") not found"

echo "copying $image -> $disk"
qemu-img convert -O qcow2 "$image" "$disk"
if [ -n "$size" ]; then echo "growing disk to $size"; qemu-img resize -q "$disk" "$size"; fi

xml=$(mktemp "${TMPDIR:-/tmp}/$name.XXXXXX")
trap 'rm -f "$xml"' EXIT
render > "$xml"
virsh define "$xml"
[ -n "$start" ] && virsh start "$name"

cat <<MSG

Domain $name $( [ -n "$start" ] && echo started || echo defined ).
  serial console:  virsh console $name        (Ctrl-] detaches)
  WAN:             first NIC, DHCP client
  LAN:             second NIC, https://192.168.1.1/ -- login admin / armsense
To give the LAN another address use console menu option 2, or Interfaces > LAN
in the GUI (answer "n" to "revert to HTTP" to keep HTTPS).
Remove with: virsh destroy $name; virsh undefine --nvram $name; rm $disk
MSG
