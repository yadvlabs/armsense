# Getting started

> **Highly experimental.** armsense is an early development snapshot. It may
> or may not work, it has not been audited, and it is **not fit for
> production use**. Use it only in a lab or a virtual machine you can afford
> to lose.
>
> **No warranty.** armsense is provided "as is", without warranty of any
> kind, express or implied, including the implied warranties of
> merchantability, fitness for a particular purpose and non-infringement.
> You use it entirely at your own risk; the authors and contributors are not
> liable for any damage or loss arising from its use. See [LICENSE](../LICENSE).


## Images

Each build produces three files, named
`armsense-<version>-arm64-<date>.*`:

| File | Use |
|---|---|
| `.qcow2` | Ready-to-boot disk for QEMU/KVM, libvirt, Proxmox, UTM. UEFI (edk2/AAVMF) required. |
| `.raw` | The same disk as a raw image, for other hypervisors or for writing to a drive. |
| `.iso` | UEFI installer (hybrid ISO, boots from a CD/DVD device or a USB stick). |

The disk image is 8 GB (6 GB root file system, 1 GB swap, EFI system
partition). On first boot the root file system grows to fill the partition,
so you can enlarge the disk before the first boot (`qemu-img resize`).

## Default settings

| Setting | Value |
|---|---|
| Web GUI login | `admin` / `armsense` |
| Console / SSH root password | `armsense` (same account as admin) |
| Hostname | `armsense.home.arpa` |
| WAN | first virtio NIC (`vtnet0`), DHCP client |
| LAN | second virtio NIC (`vtnet1`), `192.168.1.1/24`, DHCP server `192.168.1.100-199` |
| Web GUI | `https://192.168.1.1/` on the LAN side (self-signed certificate) |
| Consoles | serial (115200 8N1) and EFI framebuffer, both active |

Change the admin password at the first login; the dashboard reminds you
while it is still the default.

## Running under QEMU on a Mac or Linux host

The repository ships a helper for QEMU: `testvm/run.sh` (its VM state goes to `~/.armsense/testvm`). It wires the first
NIC to a user-mode network with DHCP (the "internet") and the second NIC to
a user-mode network `192.168.1.0/24` with the GUI forwarded to the host:

    testvm/run.sh disk ~/.armsense/buildvm/images/armsense-2.9.0-DEVELOPMENT-arm64-20261020-0845.qcow2
    # GUI: https://127.0.0.1:8443   SSH (once enabled): ssh -p 2223 admin@127.0.0.1
    # serial console on the terminal, Ctrl-A X quits

To boot the installer instead:

    testvm/run.sh iso ~/.armsense/buildvm/images/armsense-2.9.0-DEVELOPMENT-arm64-20261020-0845.iso mydisk.qcow2

Plain QEMU, for reference:

    qemu-system-aarch64 -M virt -cpu host -accel kvm -smp 2 -m 2G \
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
      -drive file=armsense.qcow2,if=none,id=hd0 -device virtio-blk-pci,drive=hd0 \
      -netdev user,id=wan -device virtio-net-pci,netdev=wan \
      -netdev user,id=lan,net=192.168.1.0/24,hostfwd=tcp::8443-192.168.1.1:443 \
      -device virtio-net-pci,netdev=lan \
      -nographic

## Running under libvirt/KVM (Raspberry Pi 5 or any arm64 Linux host)

`deploy/libvirt/create-vm.sh` creates and starts the VM from the qcow2 in one
step (tested on a Raspberry Pi 5 with Ubuntu 26.04, libvirt 12 and QEMU 10):

    sudo sh deploy/libvirt/create-vm.sh -i armsense-<version>-arm64-<date>.qcow2 -w br0 -l br1 -s 16G
    sudo virsh console armsense

`-w` and `-l` take a host bridge name or `network=NAME` for a libvirt
network. Requirements, the domain template it renders, a `virt-install`
equivalent and removal are in
[deploy/libvirt/README.md](../deploy/libvirt/README.md).

The settings that matter on any libvirt or Proxmox host:

* **UEFI firmware without Secure Boot.** With the default Secure Boot
  firmware the console shows `UEFI Misc Device ... Access Denied` and then
  `No bootable option or device was found`. This is a property of the
  firmware, not something the image can work around: Secure Boot runs only
  EFI binaries signed by a key the firmware trusts, the FreeBSD loader has no
  Microsoft signature and FreeBSD has no Microsoft-signed shim. Upstream
  pfSense needs Secure Boot off for the same reason. In libvirt XML:

      <os firmware='efi'>
        <type arch='aarch64' machine='virt'>hvm</type>
        <firmware>
          <feature enabled='no' name='secure-boot'/>
          <feature enabled='no' name='enrolled-keys'/>
        </firmware>
      </os>

  For a VM already created with the Secure Boot firmware, add the block with
  `virsh edit`, then `virsh undefine --nvram <name>` and `virsh define` so
  the NVRAM file is recreated.
* virtio disk; two virtio NICs, the first in PCI order is WAN and the second
  LAN; `host-passthrough` CPU, 2 vCPUs, 2 to 4 GB of RAM; a pty serial
  console (`virsh console <name>`). A display is optional, the EFI
  framebuffer shows the same menu.

### Changing the LAN address from the console

The default LAN is `192.168.1.1/24` with a DHCP server. When the LAN NIC is
bridged into an existing network, give it a free address there and leave the
DHCP server off. In the console menu choose `2`, then the LAN interface, and
answer the prompts in this order: `n` to IPv4 via DHCP, the new address, the
prefix length (`24`), Enter for no gateway, `n` to IPv6 via DHCP6, Enter for
no IPv6 address, `n` to the DHCP server, and `n` to "revert to HTTP as the
webConfigurator protocol" (a `y` here turns HTTPS off for the GUI). The GUI
is then at `https://<new address>/`; the same change can be made under
Interfaces → LAN in the GUI.

## Package updates

The system is configured for the armsense package repositories defined in
`/usr/local/share/armsense/pkg/repos/`. In the current development snapshot
they point at the build host and are not signed, so updates only work on the
developer's network; a public, signed repository is planned. System → Update and System → Package
Manager work against them once the repository server is reachable. The
repositories are built by `build/vm/phase2-poudriere.sh` and served with
`buildvm/serve-packages.sh` during development.

## Documentation

armsense keeps the upstream pfSense® software behaviour almost everywhere, so
the [pfSense documentation](https://docs.netgate.com/pfsense/en/latest/)
applies to day-to-day use; the Help menu in the GUI links to it. Differences
are listed in [branding.md](branding.md) and in `build/README.md`.
