# armsense

<img src="build/branding/armsense-mark.svg" alt="armsense" width="96" align="right">

armsense is a firewall and router distribution for **arm64** systems, built
from the open source pfSense® Community Edition code base and FreeBSD. It
runs as a UEFI virtual machine today (KVM, QEMU, bhyve) and targets Raspberry
Pi 4 class boards next.

> **Highly experimental.** armsense is an early development snapshot. It may
> or may not work, it has not been audited, and it is **not fit for
> production use**. Use it only in a lab or a virtual machine you can afford
> to lose.
>
> **No warranty.** armsense is provided "as is", without warranty of any
> kind, express or implied, including the implied warranties of
> merchantability, fitness for a particular purpose and non-infringement.
> You use it entirely at your own risk; the authors and contributors are not
> liable for any damage or loss arising from its use. See [LICENSE](LICENSE).

* Project: https://labs.yadv.in/
* Source: https://github.com/yadvlabs/armsense
* License: [Apache License 2.0](LICENSE), see [NOTICE](NOTICE) for attribution
* Docs: [getting started](docs/getting-started.md) (images, defaults, running under QEMU/KVM), [building from source](SETUP.md), [branding and attribution](docs/branding.md), [releases](docs/release.md)

> armsense is an independent project. It is not affiliated with, sponsored
> by, or endorsed by Netgate or Electric Sheep Fencing. "pfSense" is a
> registered trademark of Electric Sheep Fencing, LLC.

## Status

armsense is a **development snapshot** (`v0.x`) and highly experimental. It
is meant for trying out in a virtual machine. Do not put it in front of
anything you care about: the package repositories are unsigned and served
from a development host, the project has had no security review, and any
release may fail to boot, fail to upgrade, or misbehave.


| Target | State |
|---|---|
| arm64 UEFI VM (QEMU/KVM) | Boots, console menu, web GUI, package updates from the armsense repository; tested under QEMU/HVF on a Mac and libvirt/KVM on a Raspberry Pi 5 |
| Raspberry Pi 4 / CM4 | Planned (FreeBSD supports the board; needs the U-Boot/firmware boot partition) |
| Raspberry Pi 5 | Later (no in-tree FreeBSD driver for the onboard Ethernet yet) |

Images are produced as a UEFI installer ISO and a ready-to-boot qcow2/raw
disk (two virtio NICs: WAN on the first via DHCP, LAN on the second at
192.168.1.1, serial console enabled, login admin / armsense).

## Get started

1. Download the latest `armsense-*.qcow2` (ready-to-boot disk) or
   `armsense-*.iso` (installer) from the
   [releases page](https://github.com/yadvlabs/armsense/releases) and check
   it against the `SHA256SUMS-images-*.txt` file.
2. Create an arm64 UEFI virtual machine (QEMU/KVM, libvirt, Proxmox, UTM:
   machine `virt`, edk2/AAVMF firmware with Secure Boot off, virtio disk, two
   virtio NICs; 2 vCPUs and 2 GB RAM are plenty) and attach the disk image, or
   boot the ISO with an empty disk and run the installer. On a libvirt/KVM
   host such as a Raspberry Pi 5, `deploy/libvirt/create-vm.sh` does this in
   one step with the right firmware ([deploy/libvirt/README.md](deploy/libvirt/README.md)).
3. The first NIC becomes WAN (DHCP), the second LAN at `192.168.1.1/24` with
   a DHCP server. Open `https://192.168.1.1/` from the LAN side and log in
   with `admin` / `armsense`; change the password first. If the LAN NIC sits
   on a network that already has a DHCP server (Apple Virtualization apps
   such as MacVisor or UTM, shared networks), use the `-lan-dhcp` image: its
   LAN is a DHCP client and the console menu shows the address to open.
4. A serial console (115200 8N1) and the EFI console both show the console
   menu.

On a Mac with QEMU installed, `testvm/run.sh disk <qcow2>` does step 2 with
the GUI forwarded to https://127.0.0.1:8443. Details, defaults, a plain QEMU
command line and libvirt/KVM notes (including a Raspberry Pi 5 as the host)
are in [docs/getting-started.md](docs/getting-started.md).

## Building from source

The build runs on a FreeBSD 16.0-CURRENT arm64 host; on a Mac with Apple
silicon `buildvm/setup-vm.sh` creates one as a QEMU/HVF VM and
`build/vm/clean-build.sh` produces the images from the pinned upstream
sources in about 1.5 hours. [SETUP.md](SETUP.md) describes the host, the
overlay and the three build phases in detail.

## How it is built

armsense is produced entirely from public source:

* [pfsense/pfsense](https://github.com/pfsense/pfsense) (GUI and backend),
  [pfsense/FreeBSD-src](https://github.com/pfsense/FreeBSD-src) and
  [pfsense/FreeBSD-ports](https://github.com/pfsense/FreeBSD-ports), pinned
  to the March 2026 snapshots of their development branches (FreeBSD
  16.0-CURRENT).
* A rename and de-branding pass (`build/src/`), replacements for the five
  components the upstream build fetches from a private server
  (`build/ports/`), an arm64 kernel configuration (`build/kernel/`) and a
  three-phase pipeline (`build/vm/`) that runs inside a FreeBSD arm64 build
  VM. See [build/README.md](build/README.md) and
  [INVESTIGATION.md](INVESTIGATION.md) for the details and the reasoning.

Differences from pfSense CE worth knowing: PPPoE uses the mpd5 path (the
closed in-kernel driver is not available), the dynamic repository client and
the unique-ID tool are small stand-ins, Kea is stock, and the package
repositories are currently unsigned.

## Releases and CI

Tags matching `v*` trigger the Release workflow, which validates the tree,
packages the build overlay and opens a GitHub release; images are built on
the FreeBSD build VM and attached afterwards. See [docs/release.md](docs/release.md)
and [CHANGELOG.md](CHANGELOG.md).

## Trademarks and attribution

armsense is derived from pfSense® CE software under the Apache License 2.0
and carries the required attribution in [NOTICE](NOTICE), the GUI license
dialog and the installer. "pfSense" is a registered trademark of Electric
Sheep Fencing, LLC; "Netgate" is a trademark of Rubicon Communications, LLC.
Neither is affiliated with armsense. [docs/branding.md](docs/branding.md)
lists what the build renames, what it keeps and why.

## Repository layout

    build/      overlay copied into the build VM: scripts, kernel config, ports stubs, branding
    buildvm/    helpers to create and drive the FreeBSD arm64 build VM on a Mac (QEMU/HVF); state in ~/.armsense
    testvm/     helpers to boot and drive the produced images under QEMU
    deploy/     recipes to run the images on hypervisors (libvirt/KVM: script and domain template)
    branding/   logo generator and audit notes
    docs/       user and release documentation
    extras/     (ignored) clones of the upstream repositories used for investigation
