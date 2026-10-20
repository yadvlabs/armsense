# armsense

<img src="build/branding/armsense-mark.svg" alt="armsense" width="96" align="right">

armsense is a firewall and router distribution for **arm64** systems, built
from the open source pfSense® Community Edition code base and FreeBSD. It
runs as a UEFI virtual machine today (KVM, QEMU, bhyve) and targets Raspberry
Pi 4 class boards next.

* Project: https://labs.yadv.in/
* Source: https://github.com/yadvlabs/armsense
* License: [Apache License 2.0](LICENSE), see [NOTICE](NOTICE) for attribution

> armsense is an independent project. It is not affiliated with, sponsored
> by, or endorsed by Netgate or Electric Sheep Fencing. "pfSense" is a
> registered trademark of Electric Sheep Fencing, LLC.

## Status

| Target | State |
|---|---|
| arm64 UEFI VM (QEMU/KVM) | Boots, console menu, web GUI, package updates from the armsense repository |
| Raspberry Pi 4 / CM4 | Planned (FreeBSD supports the board; needs the U-Boot/firmware boot partition) |
| Raspberry Pi 5 | Later (no in-tree FreeBSD driver for the onboard Ethernet yet) |

Images are produced as a UEFI installer ISO and a ready-to-boot qcow2/raw
disk (two virtio NICs: WAN on the first via DHCP, LAN on the second at
192.168.1.1, serial console enabled, admin / pfsense).

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

## Repository layout

    build/      overlay copied into the build VM: scripts, kernel config, ports stubs, branding
    buildvm/    helpers to create and drive the FreeBSD arm64 build VM on a Mac (QEMU/HVF)
    testvm/     helpers to boot and drive the produced images under QEMU
    branding/   logo generator and audit notes
    extras/     (ignored) clones of the upstream repositories used for investigation
