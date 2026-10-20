# armsense build pipeline

Builds `armsense`, a rebranded pfSense CE for arm64, from the public
pfSense repositories.  Everything runs inside a FreeBSD 16.0-CURRENT aarch64
build VM (see `../buildvm/`).  These scripts are copied into the VM as
`/usr/armsense/overlay` and run there as root; edit them here and re-push:

    ../buildvm/scp.sh -r armsense.conf src ports vm kernel root@vm:/usr/armsense/overlay/

## Layout in the VM

    /usr/armsense/
      src/pfsense         GUI/backend source     branch armsense (from master)
      src/FreeBSD-src     base system fork        branch armsense (from devel-main)
      src/FreeBSD-ports   ports fork              branch armsense (from devel)
      obj/                buildworld/buildkernel objects
      jail/               installed world used as the poudriere jail (null mount)
      kernels/, stage-dir/, final-dir/, installer-dir/, disk-root/
      repo/<jail>-core/   core package repository (base, boot, kernel)
      distfiles/          poudriere distfiles cache + the renamed GUI source tarball
      images/             ISO, raw and qcow2 images
      logs/

## Phases

| Step | Script | What it does |
|---|---|---|
| rename | `src/rename-src.sh pfsense` (runs `src/debrand-src.sh`) | `armsense` branch of the pfSense source: product name, renamed `/etc/<product>-rc` and friends, PHP extension name; writes the source tarball the `-system` port installs. |
| rename | `src/rename-src.sh freebsd` | `armsense` branch of FreeBSD-src: `/etc/rc` hook, installer strings, loader brand, kernel config. Run after phase 1 so the world build is not disturbed. |
| ports | `ports/prepare-ports.sh` | `armsense` branch of the ports tree: replaces the five components fetched from Netgate's GitLab (if_pppoe kmod dropped, repoc and gnid stand-ins in `ports/stubs/`, stock Kea, GUI source from the tarball), then renames the 83 pfSense ports. |
| 1 | `vm/phase1-base.sh` | `buildworld` + `buildkernel KERNCONF=armsense` with pfSense's `release/conf/pfSense_*` knobs. `NO_WORLD=1` for kernel only. |
| 2 | `vm/phase2-poudriere.sh setup` | installworld into the jail root, poudriere.conf, jail `armsense_master_aarch64`, ports tree `armsense_devel`, make.conf (pfSense `tools/conf/pfPorts/make.conf` + the glue Netgate's CI provides). |
| 2 | `vm/phase2-poudriere.sh bulk` | `poudriere bulk` of `ports/bulk-core.txt`. `rebuild <origin>...` forces ports whose files changed without a version bump. |
| 3 | `vm/phase3-image.sh core` | stage world, `armsense-boot`, `-kernel-armsense`, `-kernel-debug-armsense`, `-base` packages. |
| 3 | `vm/phase3-image.sh final` | final chroot = stage + core packages + port packages. |
| 3 | `vm/phase3-image.sh iso` | UEFI installer ISO (hybrid ISO with ESP). |
| 3 | `vm/phase3-image.sh disk` | GPT disk image (ESP + swap + UFS root) as raw and qcow2, WAN=vtnet0, LAN=vtnet1, serial console. |

Package naming follows the pfSense builder: jail `<product>_<pfsense branch>_<arch>`,
ports tree `<product>_<ports branch>`, so the repository URLs baked into the
`-repo` package resolve to `<server>/packages/armsense_master_aarch64-core` and
`<server>/packages/armsense_master_aarch64-armsense_devel`.  Serve them from the
Mac with `../buildvm/sync-packages.sh` then `../buildvm/serve-packages.sh`.

## Testing images

    ../buildvm/sync-packages.sh                      # pulls images to ../buildvm/images
    ../testvm/run.sh disk ../buildvm/images/armsense-*.qcow2
    ../testvm/run.sh iso  ../buildvm/images/armsense-*.iso

GUI: https://127.0.0.1:8443 (LAN side), serial console on the terminal.

## Known differences from pfSense

* PPPoE uses the mpd5/netgraph path; the closed `if_pppoe` kernel driver is not available.
* `armsense-repoc` is a static stand-in: repository definitions come from the `-repo` package.
* `gnid` is a stand-in that derives an ID from the kernel host UUID.
* Kea is stock 3.0.2 without Netgate's 8 KB patch.
* Package repositories are unsigned (`SIGNATURE_TYPE=none`) for now.
* Kernel modules: pfSense's base list plus `if_wg`; the x86-only set is dropped.
