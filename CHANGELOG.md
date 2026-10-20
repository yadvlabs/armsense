# Changelog

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
