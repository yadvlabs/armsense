# Building armsense from source

This describes the complete setup: a FreeBSD arm64 build host, the three
upstream source trees, the overlay in `build/`, and the three build phases
that turn them into an installer ISO and a disk image. Expect about 1.5 hours
for a clean build on an Apple M4 Pro class machine.

Everything user-facing (defaults, running the images) is in
[docs/getting-started.md](docs/getting-started.md); the reasoning behind the
design is in [INVESTIGATION.md](INVESTIGATION.md).

## 1. Build host

armsense is built natively on **FreeBSD 16.0-CURRENT for aarch64** (the
upstream sources are a FreeBSD 16-CURRENT snapshot, and the host kernel must
be at least as new as the userland it installs into chroots). Needed on the
host:

* `poudriere`, `git-lite`, `rsync`, `xmlstarlet`, `sqlite3`, `ccache`,
  `qemu-tools` (for `qemu-img`), all from packages;
* a ZFS pool (poudriere uses it) with roughly 60 GB free;
* 8 or more cores and 16 GB or more RAM (the scripts use `ncpu * 2` make
  jobs and four poudriere builders).

### 1a. On a Mac with Apple silicon (what the project uses)

The helpers in `buildvm/` create and drive such a host as a QEMU/HVF virtual
machine. Install QEMU (`brew install qemu`), then:

    buildvm/setup-vm.sh

This downloads the FreeBSD 16.0-CURRENT aarch64 cloud-init image (about
600 MB), verifies its checksum, creates a 200 GB sparse disk, generates an
SSH key and a cloud-init seed, boots the VM (10 vCPUs, 32 GB RAM by default;
override with `CPUS`, `MEM`, `DISK_SIZE`), installs the packages above,
creates the `/usr/armsense` ZFS dataset, clones the pinned upstream sources
and copies the overlay in. It is idempotent.

All VM state lives in `~/.armsense/buildvm` (override with
`ARMSENSE_VM_DIR`), deliberately outside the repository: `git clean -fdx`
in the checkout does not touch it.

Day-to-day commands:

    buildvm/run.sh start|stop|status|console|monitor
    buildvm/ssh.sh 'command'                      # root in the VM
    buildvm/scp.sh -r build/vm root@vm:/usr/armsense/overlay/   # push changed scripts
    buildvm/sync-packages.sh                      # pull images and repos to ~/.armsense/buildvm
    buildvm/serve-packages.sh                     # serve them on :8000 for test VMs

### 1b. On any FreeBSD arm64 host

Install the packages listed above, create a dataset mounted at
`/usr/armsense` with `src`, `obj`, `logs`, `overlay`, `distfiles` and
`images` directories, clone the sources into `/usr/armsense/src` and copy
the contents of `build/` to `/usr/armsense/overlay`. The commit pins are in
`build/armsense.conf`:

    cd /usr/armsense/src
    git clone --depth 1 -b master     https://github.com/pfsense/pfsense.git
    git clone --depth 1 -b devel-main https://github.com/pfsense/FreeBSD-src.git
    git clone --depth 1 -b devel      https://github.com/pfsense/FreeBSD-ports.git
    # then check each out at PFSENSE_PIN / FREEBSD_PIN / PORTS_PIN
    for r in pfsense FreeBSD-src FreeBSD-ports; do echo "$r clone rc=0" > /usr/armsense/logs/clone-$r.log; done

## 2. What the overlay does

| Path | Purpose |
|---|---|
| `build/armsense.conf` | Product name, URLs, default password hash, upstream branches and commit pins, poudriere names, package server URL. |
| `build/src/rename-src.sh` | Cuts an `armsense` branch in the pfSense tree (product rename, renamed rc scripts and share directories, PHP extension name) and in the FreeBSD tree (`/etc/rc` hook, installer, loader, kernel config); runs `debrand-src.sh`; writes the GUI source tarball the `-system` port installs. |
| `build/src/debrand-src.sh` | Replaces logo, icons, themes, wizard and GUI text, footer, error pages, console art, license notice; removes vendor service hooks. |
| `build/ports/prepare-ports.sh` | Cuts an `armsense` branch in the ports tree: replaces the five components upstream fetches from a private server, renames the 83 pfSense ports, regenerates the `-system` packing list, sets the default configuration. |
| `build/kernel/armsense` | arm64 kernel configuration (upstream's `pfSense` config with stale entries removed). |
| `build/vm/phase1-base.sh` | `buildworld` and `buildkernel`. |
| `build/vm/phase2-poudriere.sh` | poudriere jail (null-mounted world), ports tree, make.conf, `bulk` of `build/ports/bulk-core.txt`; `rebuild <origin>` forces ports after edits. |
| `build/vm/phase3-image.sh` | Core packages (base, boot, kernel), final chroot, UEFI installer ISO, GPT disk image as raw and qcow2. |
| `build/vm/clean-build.sh` | All of the above from scratch. |
| `build/vm/smoke-disk.sh` | World-only boot image to validate the kernel/UEFI path early. |

## 3. Building

A clean build, in the VM (or on the host), logs to `/usr/armsense/logs`:

    buildvm/ssh.sh 'nohup sh /usr/armsense/overlay/vm/clean-build.sh > /usr/armsense/logs/clean-build.log 2>&1 &'
    buildvm/ssh.sh 'tail -f /usr/armsense/logs/clean-build.log'

Phase by phase, after editing the overlay and pushing it with `scp.sh`:

    sh /usr/armsense/overlay/src/rename-src.sh all      # re-cut the pfSense and FreeBSD branches
    sh /usr/armsense/overlay/ports/prepare-ports.sh     # re-cut the ports branch
    sh /usr/armsense/overlay/vm/phase1-base.sh          # world + kernel (NO_WORLD=1 for kernel only)
    sh /usr/armsense/overlay/vm/phase2-poudriere.sh all # jail, ports tree, make.conf, bulk
    sh /usr/armsense/overlay/vm/phase3-image.sh all     # core packages, chroot, iso, disk

The images land in `/usr/armsense/images/`:
`armsense-<version>-arm64-<date>.{iso,qcow2,raw}`.

Notes:

* poudriere only rebuilds a port when its package name changes; after
  editing a port's files run `phase2-poudriere.sh rebuild <origin>...`.
* The GUI source commit changes whenever `rename-src.sh pfsense` runs;
  `phase2-poudriere.sh setup` drops the stale `-system` package so the next
  bulk rebuilds it.
* `phase3-image.sh` reuses the stage world, so after a kernel-only change run
  `core` again before `final`.

## 4. Testing the images

On the Mac:

    buildvm/sync-packages.sh
    testvm/run.sh disk ~/.armsense/buildvm/images/armsense-*.qcow2   # GUI https://127.0.0.1:8443
    testvm/run.sh iso  ~/.armsense/buildvm/images/armsense-*.iso     # installer

`SERIAL_SOCK=1 testvm/run.sh ...` runs the VM detached with the serial
console on a socket; `testvm/console.py 'command'` drives it (the product
shell is tcsh, wrap commands in `sh -c`). Package updates inside a test VM
need `buildvm/serve-packages.sh` running on the Mac.

## 5. Publishing

See [docs/release.md](docs/release.md): tag `v*`, let the Release workflow
create the GitHub release, then `buildvm/publish-release.sh <tag>` uploads
the images (needs `gh auth login`).
