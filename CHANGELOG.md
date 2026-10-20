# Changelog

## Unreleased

* `buildvm/setup-vm.sh` creates and bootstraps the build VM in one step;
  VM and test-VM state moved to `~/.armsense` (outside the checkout).
* `build/vm/clean-build.sh` for from-scratch builds; upstream commits pinned
  in `build/armsense.conf`.
* SETUP.md (building from source) and a README "Get started" section.
* Second disk-image flavour `-lan-dhcp` (LAN as a DHCP client, no LAN DHCP
  server, WAN pinned as default gateway) for Apple Virtualization apps
  (MacVisor, UTM) and other hypervisors whose second network has its own
  DHCP server; `DISK_FLAVOURS` selects the flavours `phase3-image.sh disk`
  builds. `testvm/run.sh` takes `LAN_IP` for the port forwards.
* `deploy/libvirt/`: `create-vm.sh` and a domain template that create and
  start the VM on a libvirt/KVM host (Raspberry Pi 5 tested), attached to
  releases as `armsense-libvirt-<tag>.tar.gz`; the docs explain why Secure
  Boot has to be off and that the image cannot work around it.
* Docs: running under libvirt/KVM on a Raspberry Pi 5 or other arm64 Linux
  host (firmware without Secure Boot, `virt-install` example) and changing
  the LAN address from the console.
* `testvm/console.py` answers the shell's terminal-size query and recognises
  the product's root shell prompt, so driving the console shell (menu
  option 8) works.

## v0.1.0 (2026-10-20)

First development snapshot.

* Build pipeline for arm64 from the public pfSense CE sources (pinned to the
  March 2026 snapshots, FreeBSD 16.0-CURRENT): world, kernel, poudriere
  packages, core packages, UEFI installer ISO and qcow2/raw disk image.
* Replacements for the five components the upstream build fetches from a
  private server (PPPoE kernel driver dropped, repository client and
  unique-ID stand-ins, stock Kea, GUI source tarball).
* Product rename and de-branding: name and packages, monochrome logo and
  icons, console and loader art, installer notice, wizard and GUI text,
  theme names; vendor services (copyright download, support widget,
  registration page) removed.
* Defaults: admin / armsense, hostname armsense, serial console on.
* Helpers to run the build VM and test VMs under QEMU on a Mac, CI and
  release workflows.
