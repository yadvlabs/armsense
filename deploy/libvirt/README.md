# armsense on libvirt/KVM (Raspberry Pi 5 and other arm64 Linux hosts)

* `create-vm.sh` copies the qcow2 into the libvirt images directory, renders
  the domain XML, defines the VM and starts it.
* `armsense.xml.in` is the domain template; it can also be filled in by hand.

Tested on a Raspberry Pi 5 running Ubuntu 26.04 with libvirt 12 and QEMU 10.

## Requirements

* An arm64 host with KVM (Raspberry Pi 5, or any other aarch64 Linux
  machine). KVM cannot run arm64 guests on an x86 host.
* libvirt 7.2 or newer (it selects the firmware from the `<firmware>`
  features), `qemu-system-arm`, the arm64 UEFI firmware (`qemu-efi-aarch64`
  on Debian/Ubuntu, `edk2-aarch64` on Fedora) and `qemu-utils` for `qemu-img`.
* Networks for the two NICs: host bridges (for example `br0` on the uplink
  for WAN and a second bridge for LAN) or libvirt networks
  (`network=default` is libvirt's NAT network).

## Create and start

    curl -LO https://github.com/yadvlabs/armsense/releases/download/<tag>/armsense-<version>-arm64-<date>.qcow2
    curl -LO https://github.com/yadvlabs/armsense/releases/download/<tag>/SHA256SUMS-images-<tag>.txt
    sha256sum -c --ignore-missing SHA256SUMS-images-<tag>.txt
    sudo sh create-vm.sh -i armsense-<version>-arm64-<date>.qcow2 -w br0 -l br1 -s 16G

Options: `-n NAME` (default `armsense`), `-m MB` (4096), `-c N` vCPUs (2),
`-s SIZE` grows the disk before the first boot (the root file system expands
to fill it), `-d DIR` images directory, `-N` define without starting, `-x`
print the XML and stop. `-w` and `-l` take a bridge name or `network=NAME`.

Then:

    sudo virsh console armsense       # serial console with the menu; Ctrl-] detaches
    sudo virsh autostart armsense     # optional: start together with the host

The first NIC is WAN (DHCP client). The second is LAN at `https://192.168.1.1/`
with a DHCP server; log in as `admin` / `armsense` and change the password.
If the LAN bridge already carries a network, give the LAN a free address there
and leave its DHCP server off: console menu option 2, see
[docs/getting-started.md](../../docs/getting-started.md).

## Why Secure Boot has to be off

The template asks libvirt for the UEFI firmware without Secure Boot:

    <os firmware='efi'>
      <type arch='aarch64' machine='virt'>hvm</type>
      <firmware>
        <feature enabled='no' name='secure-boot'/>
        <feature enabled='no' name='enrolled-keys'/>
      </firmware>
    </os>

Distributions default to the Secure Boot build (`AAVMF_CODE.ms.fd`) with
Microsoft's keys enrolled. That firmware runs only EFI binaries signed by a
key it trusts. The FreeBSD loader in the armsense image carries no such
signature, and unlike Linux distributions FreeBSD has no Microsoft-signed
shim, so the firmware stops with `UEFI Misc Device ... Access Denied` and
`No bootable option or device was found`. Nothing in the armsense build can
change that: signing the loader with a project key would still require that
key to be enrolled by hand in every VM's firmware variables, which is more
work than selecting the other firmware and adds nothing to a VM whose disk
the host controls anyway. Upstream pfSense requires Secure Boot to be
disabled for the same reason.

A VM created earlier with the Secure Boot firmware (virt-manager and cockpit
pick it by default): add the `<firmware>` block above with `virsh edit`,
then `virsh undefine --nvram <name>` and `virsh define <name>.xml` so the
NVRAM file is recreated from the matching template.

## Without the script

`virt-install` (version 4 or newer) with the same settings:

    virt-install --name armsense --arch aarch64 --machine virt --cpu host-passthrough \
      --vcpus 2 --memory 4096 --osinfo freebsd14.0 \
      --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
      --disk /var/lib/libvirt/images/armsense.qcow2,bus=virtio \
      --network bridge=br0,model=virtio --network bridge=br1,model=virtio \
      --graphics none --import

Or fill in the template by hand and define it:

    sh create-vm.sh -x -i armsense.qcow2 -w br0 -l br1 > armsense.xml   # or edit armsense.xml.in
    sudo virsh define armsense.xml && sudo virsh start armsense

## Remove

    sudo virsh destroy armsense
    sudo virsh undefine --nvram armsense
    sudo rm /var/lib/libvirt/images/armsense.qcow2
