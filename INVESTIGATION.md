# armSense — Building pfSense for arm64 (Raspberry Pi 4/5, KVM)

Investigation date: 2026-10-20. Repos examined are cloned under `extras/` (see §8).

## TL;DR

* **Feasible, but it is a real porting/packaging project, not a rebuild with a flag.**
  pfSense already runs on arm64 (Netgate sells it on the aarch64 Netgate 1100/2100),
  and the public source tree contains the arm64 kernel config, arm64-aware PHP code and
  arm64-aware upgrade/boot tooling. Nothing architectural blocks a Raspberry Pi 4 or a
  KVM arm64 build.
* **What blocks a "just run `build.sh`" approach:**
  1. Five ports fetch closed components from `gitlab.netgate.com` (an intranet host,
     172.27.25.39, unreachable): the new `if_pppoe` kernel driver, `pfSense-repoc`,
     `pfSense-gnid`, a Netgate patch for Kea, and the `pfSense-system` package source itself.
  2. The public build scripts (`build.sh`, `tools/builder_common.sh`) have not changed
     functionally since 2022; they reference a package template removed in 2023, never create
     the `boot` package that the `kernel` package depends on, and only know amd64 hosts.
     Netgate's real pipeline (AWS/S3 references in the code) sets variables that are defined
     nowhere in the public tree.
  3. The public GitHub mirrors stopped at 2026-03-26/31. The CE 2.8.x and 2.9.0 release
     branches were never published. The best buildable target is "2.9.0-DEVELOPMENT as of
     March 2026" on FreeBSD 16.0-CURRENT.
  4. The license forbids building anything named "pfSense" unless Netgate authorizes it,
     and the builder enforces this. The build must be rebranded (e.g. `armSense`); the
     tooling already supports renaming the product.
* **Hardware verdict:** KVM/QEMU arm64 VM (UEFI) is the easiest target. Raspberry Pi 4 /
  CM4 is realistic (in-tree Ethernet, U-Boot and firmware ports exist) but has one NIC, so a
  USB 3 gigabit adapter or VLAN trunk is required. Raspberry Pi 5 boots FreeBSD via UEFI but
  its onboard Ethernet (RP1 chip) still has **no in-tree FreeBSD driver**; only experimental
  out-of-tree modules exist. Treat Pi 5 as a stretch goal.
* **Build host:** a FreeBSD arm64 machine, not Linux. A FreeBSD 16.0-CURRENT aarch64 VM under
  QEMU/HVF on this Mac (M4 Pro, 64 GB) is sufficient. Official qcow2 snapshots exist.

## 1. Official status

| Item | Finding | Source |
|---|---|---|
| pfSense CE arm64 image | None. CE is amd64-only. | pfsense.org download page; Netgate forum |
| pfSense Plus arm64 | Yes, aarch64 memstick for Netgate 1100/2100 only (Armada 3720). | docs.netgate.com installer page |
| Netgate plans for ARM CE | "no plans for ARM CE images any time soon"; cites per-board U-Boot/DTB maintenance. | forum thread 198783 (stephenw10) |
| Latest CE | 2.9.0, released 2026-08-20, FreeBSD 16.0-CURRENT@4bdcff554368, branch RELENG_2_9_0 (not public). | docs.netgate.com/pfsense/en/latest/releases/versions.html |
| Latest Plus | 26.07, same FreeBSD base. | same |

## 2. Public source state (github.com/pfsense)

| Repo | Default branch | Last push | Notes |
|---|---|---|---|
| `pfsense/pfsense` | `master` | 2026-03-31 | `src/etc/version` = `2.9.0-DEVELOPMENT`. Release branches stop at `RELENG_2_7_2`. No `RELENG_2_8_*`/`RELENG_2_9_0`. |
| `pfsense/FreeBSD-src` | `devel-main` | 2026-03-26 | FreeBSD 16.0-CURRENT, `__FreeBSD_version 1600014`. Last merge from upstream `main` by Brad Davis. Release branches stop at `RELENG_2_7_2`. |
| `pfsense/FreeBSD-ports` | `devel` | 2026-03-26 | Full ports tree with 71 `pfSense-pkg-*` ports plus core ports. |

The three default branches were synced on the same dates and are mutually consistent, so
they form a coherent snapshot to build from. The 2.9.0 release used upstream FreeBSD commit
`4bdcff554368` (2026-06-10), which is newer than the public fork's last merge, so the exact
2.9.0 release cannot be reproduced from public source.

Community reports (Netgate forum 198645, "How does one build 2.8.0 kernel") confirm the
missing release branches and speculate the cause is the proprietary multi-threaded PPPoE
driver introduced in 2.8.

## 3. Evidence the codebase is arm64-ready

* `FreeBSD-src/sys/arm64/conf/pfSense` exists. It `include`s `GENERIC` (so all arm64 SoC
  fragments: `std.broadcom` with `genet` for Pi 4, `std.virt` with virtio for KVM,
  `std.marvell` for Netgate 1100/2100) and adds pf, ALTQ, netgraph, IPsec, carp, lagg,
  vxlan, wireless, USB NICs (`axge`, `ure` via modules), `virtio_console`, RSS.
* `FreeBSD-src/sys/dev/netgate/netgate.c` (BSD-licensed, in the public tree) identifies
  Netgate hardware and exposes `dev.netgate.model`; on other hardware it simply does not match.
* `pfsense/src/etc/inc/util.inc`: `is_arm()`, `is_arm64()`, `is_64bit()`;
  `globals.inc` sets `kern.shutdown.secure_halt=1` on arm/arm64; `pfsense-utils.inc`
  handles the armv7 (non-Lua) loader case and serial consoles (`ttyu0`).
* `pfsense/tools/conf/pfPorts/make.conf` has `aarch64` conditionals (snort3 without
  Hyperscan/TSC, Suricata Rust handling for non-native builds).
* `pfsense/tools/templates/core_pkg/u-boot` template and
  `tools/conf/pfPorts/poudriere_bulk.exclude.arm.armv7` show the multi-arch package flow.
* `FreeBSD-ports/sysutils/pfSense-upgrade/files/install-boot.sh` knows `bootaa64.efi`; the
  `install-boot` wrapper falls back to `machdep.bootmethod` on non-Netgate hardware, which is
  the generic UEFI path we would use.
* `FreeBSD-src/release/arm64/mkisoimages.sh` and `make-memstick.sh` are EFI-only and generic;
  `build.sh` already calls `release/${TARGET}/mkisoimages.sh`, so installer image creation
  is arch-neutral.
* `bsdinstall` in the fork keeps upstream's arm64 handling (`ZFSBOOT_BOOT_TYPE=UEFI` on
  arm64, `bootaa64`), plus pfSense's installer menu and config.xml recovery.

## 4. Blockers and gaps in detail

### 4.1 Closed-source components (fetched from gitlab.netgate.com)

| Port | What it is | Where it is used | Workaround |
|---|---|---|---|
| `net/if_pppoe-kmod` | New in-kernel PPPoE client (`if_pppoe.ko`, `pppcfg`). Token-gated. | `RUN_DEPENDS` of `pfSense-system`; GUI option `system/use_if_pppoe`. | Drop the dependency. pfSense still has the mpd5/netgraph PPPoE path when the option is off (`interfaces.inc`, `filter.inc` branch on `use_if_pppoe`). |
| `security/pfSense-gnid` | `gnid`, Netgate unique-ID generator. | `rc.bootup`, `system_get_uniqueid()`, `rc.update_bogons.sh`. | Replace with a small script producing a stable ID (e.g. hash of `kern.hostuuid`). Only the Netgate bogons feed might reject it; fall back to another bogons source if so. |
| `sysutils/pfSense-repoc` | Dynamic repository client (`pfSense-repoc`, `-static`). Token-gated. | `pfSense-upgrade`, `pfSense-repo-setup`, `pkg-utils.inc` (`proc_open(... -repoc -N)`). | Stub it (print a fixed feature list / exit 0) and ship static repo `.conf` files pointing at our own pkg repo. Update checks in the GUI need this path to work. |
| `net/kea` | Netgate's `netgate.diff` (8 KB) applied to Kea 3.0.2. Token-gated. | DHCP server (Kea backend). | Build stock Kea and test the pfSense Kea integration; or keep ISC DHCP (still a dependency) as the backend if something breaks. |
| `security/pfSense-system` | Installs `etc` and `usr` from the pfSense source via `GL_PROJECT=${PFSENSE_SRC_REPO}` / `GL_COMMIT=${PFSENSE_COMMITHASH}`. | Core package. | Point `USE_GITHUB` at `pfsense/pfsense` (or a local tarball) at the chosen commit. |

`gitlab.netgate.com` resolves to `172.27.25.39` (RFC 1918) and times out; it is not meant to
be reachable.

### 4.2 Public builder is stale and incomplete

* `tools/builder_common.sh`, `build.sh`, `tools/builder_defaults.sh`: last non-cosmetic
  commits are from 2022; later commits only bump copyright years.
* `clone_to_staging_area()` calls `core_pkg_create rc ...` but
  `tools/templates/core_pkg/rc` was deleted on 2023-09-05 ("Remove pfSense-rc before moving
  it to ports"). The script would abort there.
* The `kernel` package manifest depends on `pfSense-boot`, but nothing in the public builder
  creates a `boot` package (the template exists). `pkg add` of the kernel would fail.
* `get_altabi_arch()` knows `amd64`, `i386`, `armv7` only; needs `aarch64` →
  `aarch64:64`.
* `poudriere_possible_archs()` only allows `amd64.amd64` (+ `arm.armv7` via
  `qemu-user-static`); an arm64 host must be added (`arm64.aarch64`, native).
* `MODULES_OVERRIDE` is defined only for amd64; needs an arm64 list (drop `aesni`,
  `amdtemp`, `coretemp`, `vmm`, `ix*`, `cxgbe/tom`, `drm2`, `ndis`; keep `ure`, `cdce`, zfs,
  cc_*, dummynet, ipfw*, etc.).
* Variables the ports need are set nowhere publicly: `PFSENSE_COMMITHASH`,
  `PFSENSE_SRC_REPO`, `PFSENSE_DATESTRING`, `IFPPPOE_COMMITHASH`, `REPOC_COMMITHASH`,
  `REPOC_COMMITDATE`, `GITLAB_TOKEN`, `FLAVOR`.
* `builder_setup()` wants to `pkg install ${PRODUCT_NAME}-builder` from Netgate's repo;
  `BUILDER_PKG_DEPENDENCIES` includes `emulators/qemu-user-static` (irrelevant on a native
  arm64 host).
* `create_ova_image()` is amd64-only; not needed (we want qcow2/raw).

Conclusion: reuse the logic (core package creation, staging, image scripts, make.conf,
bulk lists) but drive it from a small, new orchestration script rather than trying to make
`build.sh` work unmodified.

### 4.3 Licensing and naming

`tools/builder_defaults.sh` exits unless `PRODUCT_NAME != pfSense` or
`BUILD_AUTHORIZED_BY_NETGATE=yes`, and `LICENSE` reserves the pfSense name/marks to Netgate.
The code is Apache 2.0, so a rebranded build (`PRODUCT_NAME=armSense`,
`PRODUCT_NAME_SUFFIX=-CE` or similar) is permitted. `poudriere_rename_ports()` rewrites every
`*pfSense*` port to the new product name automatically, including the PHP module.

### 4.4 Hardware support matrix

| Target | Boot path | Networking | Status |
|---|---|---|---|
| KVM/QEMU `virt` (UEFI, edk2) | UEFI → `loader.efi` → kernel | virtio-net, vmx | Fully supported by FreeBSD arm64 and by the pfSense kernel config (`std.virt`). Easiest target. |
| Raspberry Pi 4 B / CM4 | Pi firmware → U-Boot (`sysutils/u-boot-rpi-arm64`) → `loader.efi`; or pftf RPi4 UEFI firmware → `loader.efi` | `genet` onboard (in-tree), USB 3 NICs (`ure`, `axge`, `muge`) | Supported by FreeBSD since 13.x; `release/arm64/RPI.conf` documents the SD layout (MBR, 50 MB FAT16 with firmware/DTBs/`config.txt`, UFS root). Single NIC → need a USB NIC or VLAN trunk. No WiFi. |
| Raspberry Pi 5 | worproject `rpi5-uefi` (ACPI + DT) → `loader.efi` | **Onboard Ethernet not supported in-tree** (RP1 southbridge, Cadence GEM derivative; `if_cgem` has no RP1 compat string in FreeBSD `main` as of today). USB NICs work. NVMe/PCIe, USB, SD, HDMI work. No fan control, no WiFi. | Experimental only. Out-of-tree KLDs (`aphor/FreeBSD15-RPi5-modules`, fork `Medvidek77/FreeBSD15-RPi5-modules`) provide `rp1_eth` (polling mode, needs DSDT override), thermal and fan. Could be integrated later as kernel modules. |

## 5. Proposed approach

Phase 0 — Build host. FreeBSD 16.0-CURRENT aarch64 VM on the Mac via `qemu-system-aarch64
-accel hvf` (edk2 firmware, 8–10 vCPUs, 24–32 GB RAM, ~200 GB sparse qcow2, ZFS root for
poudriere). Official images:
`https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest/`.

Phase 1 — Base system. From `extras/FreeBSD-src` (devel-main): `make buildworld
buildkernel KERNCONF=pfSense` with `SRCCONF=release/conf/pfSense_build_src.conf`,
`__MAKE_CONF=release/conf/pfSense_make.conf`, `SRC_ENV_CONF=release/conf/pfSense_src-env.conf`
(as `build/scripts/build_freebsd.sh` does). Verify the kernel boots under QEMU `virt`.
Rough estimate: 1–2 h on the M4 Pro under HVF.

Phase 2 — Packages. poudriere jail created from the same src tree
(`poudriere jail -c -a arm64.aarch64 -m src=...`), ports tree = `extras/FreeBSD-ports`
`devel`, `make.conf` from `tools/conf/pfPorts/make.conf` plus the `PRODUCT_*`/`PKG_REPO_*`
lines `poudriere_bulk()` appends. Patch the five GitLab-dependent ports (§4.1), rename
ports to the product name, add an `exclude.arm64.aarch64` list (Open-VM-Tools, azure,
LCDproc, Netgate_Firmware_Upgrade, xe-guest-utilities, cpu-microcode, intel/realtek kmods
as needed). Start with `security/pfSense` + `pfSense-ce` + `pfSense-default-config*`; add
`pfSense-pkg-*` later. Rough estimate: 3–6 h for the core set; much longer if
Suricata/Zeek/Snort (Rust, large C++) are included.

Phase 3 — Core packages and images. Create `base`, `boot`, `kernel`, `default-config*`
packages with `build/scripts/create_core_pkg.sh` (adding the missing `boot` step and
dropping `rc`). Stage, then:
* UEFI installer ISO/memstick via `release/arm64/mkisoimages.sh -b` (hybrid ISO with ESP);
  boots in QEMU and on Pi 4 with pftf UEFI.
* KVM qcow2: install into a QEMU disk from the ISO, or build a GPT image (`mkimg`: `efi` +
  `freebsd-ufs`/`freebsd-zfs`) and `qemu-img convert` to qcow2.
* Pi 4 SD/USB image: follow `release/arm64/RPI.conf` + `release/tools/arm.subr`
  (FAT partition with `u-boot.bin`, Pi firmware, DTBs, `config.txt`, `EFI/BOOT/bootaa64.efi`;
  UFS root; `growfs` on first boot).

Phase 4 — Validate and operate. Boot tests (QEMU virt, Pi 4), GUI, pf, DHCP (Kea without the
Netgate patch), PPPoE via mpd5, package manager against our own pkg repo, upgrade flow with
the stubbed `repoc`. Decide on Pi 5 after checking FreeBSD `main` for RP1 support again.

## 6. Risks

* Source lag: no exact 2.9.0; the public mirror may stop updating entirely. Mitigation:
  pin the March 2026 snapshot; re-sync when Netgate pushes.
* Closed components: PPPoE kmod, repoc, gnid, Kea patch. All have workarounds (§4.1) but
  reduce fidelity to upstream pfSense.
* Builder rot: expect to write our own orchestration; the public scripts cannot run as-is.
* FreeBSD 16-CURRENT is a development branch; snapshots can regress.
* Pi 5 onboard NIC and fan: out-of-tree, experimental.
* Trademark: must ship under a different name.

## 7. Alternatives considered (for contrast only)

OPNsense's build system (`opnsense/tools`) is fully open and has arm64 support, and a
community aarch64 image/repo exists (`maurice-w/opnsense-vm-images`). That is a much smaller
effort if the goal is "a FreeBSD/pf firewall on a Pi"; it is not pfSense.

## 8. Repositories cloned under `extras/`

| Path | Source | Branch | Depth |
|---|---|---|---|
| `extras/pfsense` | https://github.com/pfsense/pfsense | all branches | full |
| `extras/FreeBSD-src` | https://github.com/pfsense/FreeBSD-src | `devel-main` | shallow (depth 1) |
| `extras/FreeBSD-ports` | https://github.com/pfsense/FreeBSD-ports | `devel` | shallow (depth 1) |

## 9. References

* Netgate versions table: https://docs.netgate.com/pfsense/en/latest/releases/versions.html
* Netgate forum, arm64 image plans: https://forum.netgate.com/topic/198783/any-updates-on-plans-to-make-an-arm64-image-available
* Netgate forum, 2.8.0 kernel source: https://forum.netgate.com/topic/198645/how-does-one-build-2-8-0-kernel-with-a-patch-applied-to-it
* Craig Leres, pfSense ports on arm64 with poudriere: https://xse.com/leres/pfsense/toolchain.html
* FreeBSD Pi 5 how-to (15.0, NVMe, USB NIC): https://lists.freebsd.org/archives/freebsd-arm/2026-February/005683.html
* FreeBSD forums Pi 5 status thread: https://forums.freebsd.org/threads/raspberry-pi-5-status.91406/
* Out-of-tree Pi 5 modules: https://github.com/aphor/FreeBSD15-RPi5-modules , https://github.com/Medvidek77/FreeBSD15-RPi5-modules
* Pi 5 UEFI firmware: https://github.com/worproject/rpi5-uefi ; Pi 4 UEFI: https://github.com/pftf/RPi4
* FreeBSD 16-CURRENT aarch64 VM images: https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest/
* Source-availability critique (advocacy, partly dated): https://github.com/rapi3/pfsense-is-closed-source

## 10. Decisions and version pins (2026-10-20)

* **Phase 1 target:** arm64 UEFI virtual machine only (KVM/QEMU `virt`, edk2 firmware).
  Raspberry Pi 4 is phase 2, Pi 5 later.
* **Product name:** `armsense` (lowercase).
* **Target base OS (what gets built):** `extras/FreeBSD-src` branch `devel-main` as of
  2026-03-26, which is FreeBSD 16.0-CURRENT with `__FreeBSD_version 1600014`. Paired with
  `extras/pfsense` master (2.9.0-DEVELOPMENT, 2026-03-31) and `extras/FreeBSD-ports`
  `devel` (2026-03-26).
* **Build host OS:** FreeBSD 16.0-CURRENT aarch64 snapshot, first candidate
  `20261019-041802b362aa-290219`, ZFS qcow2 VM image (≈624 MB compressed) from
  `https://download.freebsd.org/snapshots/VM-IMAGES/16.0-CURRENT/aarch64/Latest/`.
  Reason: `installworld` into a chroot, `pkg` inside that chroot, and poudriere jails all
  require the host kernel to be at least as new as the target userland. A 15.x release host
  cannot run 16-CURRENT userland. Snapshot kernels carry `INVARIANTS`/`WITNESS`, which slows
  compiles; once our own world is built we can install a `GENERIC-NODEBUG` kernel on the host.
* **Local hypervisor:** `qemu-system-aarch64` 11.1.2 with `hvf` acceleration and
  `edk2-aarch64-code.fd` are already installed via Homebrew on the Mac mini (M4 Pro, 64 GB).

### Rename plan for `armsense`

The builder's `poudriere_rename_ports()` renames ports and packages (`armsense-base`,
`armsense-kernel`, `security/armsense`, `php85-armsense-module`, ...). It does **not** touch
the pfSense source tree or the FreeBSD fork, which hardcode the name in a few places:

| Location | What | Action |
|---|---|---|
| `pfsense/src/etc/inc/globals.inc` | `'product_name' => 'pfSense'`, `product_label*`, `xml_rootobj => 'pfsense'` | Set `product_name`/labels to `armsense`. Keep `xml_rootobj` as `pfsense` and export `XML_ROOTOBJ=pfsense` in `build.conf` so existing pfSense `config.xml` backups still import. |
| `pfsense/src/etc/pfSense-rc`, `pfSense-rc.shutdown`, `pfSense-devd.conf`, `pfSense-ddb.conf`, `pfSense.obsoletedfiles`, `usr/local/sbin/pfSense-dhclient-script`, `usr/local/share/pfSense/`, `usr/local/pfSense/` | Literal file/dir names | Rename files; ~15 literal path references in ~8 files (`rc.php_ini_setup`, `pfsense-utils.inc`, `pfSense-rc`, obsoletedfiles, dhclient callers). Locale files (`pfSense.po/.mo`) can keep the `pfSense` gettext domain. |
| `FreeBSD-src/libexec/rc/rc`, `rc.shutdown` | Source `/etc/pfSense-rc` by literal name | Change to `/etc/armsense-rc`. |
| `FreeBSD-src/usr.sbin/bsdinstall/startbsdinstall`, `scripts/config`, `scripts/fix_fstab` | Installer branding, `OSNAME=pfSense`, `ZFSBOOT_POOL_NAME=pfSense`, `loader.conf.pfSense` | sed to `armsense`. |
| `FreeBSD-src/stand/lua/brand-pfSense.lua`, `logo-pfSensebw.lua`, `stand/defaults/loader.conf` | Loader menu branding | Cosmetic; rename or leave. |
| `FreeBSD-ports/sysutils/pfSense-upgrade/files/*`, other renamed ports' `files/` | Script contents still say `pfSense` (e.g. `pfSense-repoc-static`, `PRODUCT="pfSense"`) | Extend the rename step to sed file contents under `files/` for renamed ports (the PHP module already gets this treatment). |
| Builder defaults | `BUILD_KERNELS=${PRODUCT_NAME}` → `KERNCONF=armsense`; `SRCCONF=.../${PRODUCT_NAME}_src.conf` but fork ships `pfSense_build_src.conf` | Add `sys/arm64/conf/armsense` (`include pfSense`, `ident armsense`) or set `BUILD_KERNELS=pfSense`; set `SRCCONF`, `SRC_ENV_CONF`, `__MAKE_CONF` explicitly in `build.conf`. |
