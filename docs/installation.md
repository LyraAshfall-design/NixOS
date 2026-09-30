# Local installation

Boot a NixOS live installer in **UEFI mode**, connect to the network, clone this
repository, then inspect the plan first:

```sh
./setup --help
./setup --check desktop
```

No host currently permits a full installation through `setup`.
`desktop` maps to `nixos-desktop` and supports **only** `./setup --check desktop`.
Destructive `./setup desktop` is unconditionally refused before privilege checks,
confirmation, builds, or operations, even when the identity/layout checks pass.
`laptop` and `server` are not implemented. Unknown names are rejected.

The desktop review checks the intentional stable path
`/dev/disk/by-id/nvme-SIX_X7400_SSD_STX26012100037853`, resolved `/dev/nvme0n1`,
model `SIX X7400 SSD`, serial `STX26012100037853`, and capacity 1,024,209,543,168
bytes (953.9 GiB, tolerance ±1 GiB). Duplicate serial identities are refused.
UEFI is required. Current partitions and mounts are displayed; mounted production
storage is allowed for this read-only review, which returns before install gates.

## Safety boundaries

- Check mode can run without root. It evaluates the configuration and inspects
  the local disks, fetching locked Nix sources if needed. It does not build or
  execute Disko, mount filesystems, install a system, or change passwords.
- Installation requires root and a terminal. Do not pipe it through `tee`, run
  it with tracing, or use terminal session recording while entering passwords.
- All phases use one immutable snapshot of the repository and its locked inputs.
  The wrapper never updates `flake.lock` or fetches a separate latest Disko.
- Desktop review uses an explicit path-flake snapshot, including unstaged new
  layout files. Review the checkout
  before use; path-flake snapshots include untracked files and are not secret storage.
- Desktop review supports only the Btrfs layout below.
  Additional disks, LUKS/LVM/ZFS, other mount
  layouts, and declaratively managed Corey passwords need a reviewed extension.
- Mounted disks, active swap, block-device holders, partition-label collisions,
  and an occupied/nonempty/symlinked `/mnt` are refused. Nothing is automatically
  unmounted or deactivated to make a disk available. These are disposable-test
  readiness checks, not requirements for reviewing the mounted desktop SSD.
- Failed directory/disk/mount/swap inspection is fatal. Root and EFI labels,
  partition paths, and filesystem targets must be distinct and consistent;
  existing target aliases must belong to the selected disk and remain distinct.
- The disk path, resolved path, model, serial/WWN, size and partition layout are
  displayed. The disposable test requires `ERASE <selected-by-id-path>`. Disk identity
  and busy-state checks are repeated immediately before Disko runs.

The pinned Disko module generates
`system.build.destroyFormatMount/bin/disko-destroy-format-mount`. The disposable
storage test builds that output before confirmation and invokes it with the
pinned version's `--yes-wipe-all-disks` flag only after exact typed confirmation.
It never installs NixOS or changes passwords.

Generic installation helpers remain for a future reviewed enablement change.
They use the immutable host snapshot, install under `/mnt`, and invoke the
installed `passwd corey` interactively through `nixos-enter`. Passwords must
never be captured in variables, logs, arguments, or temporary files. This flow
is currently unreachable for every supported host. Its ordering and failure
boundaries remain covered by a synthetic, non-destructive test harness.

On any failure, stop and inspect the reported phase. There is no automatic
rollback, unmount, or reboot.

## Review-only desktop layout

`hosts/desktop/disko.nix` defines GPT with a 1 GiB vfat ESP at `/boot`
(`umask=0077`) and the remaining space as Btrfs:

| Subvolume | Mount | Options |
| --- | --- | --- |
| `@root` | `/` | `compress=zstd,noatime` |
| `@home` | `/home` | `compress=zstd,noatime` |
| `@nix` | `/nix` | `compress=zstd,noatime` |

No encryption, swapfile, or incidental service subvolumes are added. The existing
systemd-boot/UEFI settings and non-filesystem hardware configuration are retained.
The old UUID mount declarations are replaced by Disko's future-install mounts.
**Do not rebuild/switch/boot this configuration on the current installation:**
its top-level root and `home`/`nix` subvolumes are not `@root`/`@home`/`@nix`.
This definition is a fresh-install plan, not an in-place data migration.

Before a later reviewed change can enable destructive desktop installation:

1. Verify complete backups and a tested restore plan; explicitly authorize erasure.
2. Test this Btrfs design on disposable media with a separately reviewed test target.
3. Preserve the desktop policy: 50% RAM zram, no disk-backed swap or hibernation.
4. Add Btrfs-aware install/mount validation and unused-disk checks for a live-ISO
   environment, and re-review device identity, confirmation, and failure recovery.

Never substitute a guessed stable ID or treat `/dev/sda`/`/dev/nvme0n1` as a
physical-machine installation identity.

## Non-destructive validation

```sh
bash -n setup tests/disposable-disko.sh
shellcheck setup tests/disposable-disko.sh
python3 tests/setup.py
./setup --help
./setup --check desktop
nix flake check --no-update-lock-file path:.
git diff --check
```

Tests use synthetic metadata and mocked installation boundaries, including
failure injection and confirmation/phase-order checks. They never execute Disko,
nixos-install, nixos-enter or passwd.

Preflight cannot make storage operations atomic with hotplug or other tools.
Keep disposable test storage isolated and do not change disks or mounts during testing.
Failures may leave partial filesystems/mounts; inspection and recovery remain
manual, as does deciding whether the displayed disk is safe to erase.

Until the new Disko file is tracked in Git, ordinary Git-flake validation excludes
it. Use `nix flake check --no-update-lock-file path:.` to validate the full reviewed
working tree without staging. This does not change the lock file or enable installs.

## Disposable desktop layout test

This is a separate, explicitly destructive **storage test**, not desktop installation.
It never calls nixos-install, passwd, or activates a system. Normal `./setup desktop`
remains disabled. `tests/disposable-disko.nix` extends the immutable desktop
configuration and overrides only `disko.devices.disk.main.device`; the production
definition stays fixed. The evaluated layout must otherwise match exactly.
No environment variable selects or overrides a device.

Attach a separately identified, expendable whole SSD/USB/NVMe disk of at least
8 GiB, then substitute its actual by-id path below (never the production SSD):

```sh
sudo ./setup --test-disko desktop /dev/disk/by-id/ACTUAL_DISPOSABLE_DISK_ID
```

The command requires root, a terminal, Nix/jq, util-linux tools (including sfdisk,
blkid, lsblk, findmnt and swapon), and btrfs-progs. It displays the disk and resolved
identity and requires exactly `ERASE /dev/disk/by-id/ACTUAL_DISPOSABLE_DISK_ID`.
Do not use a disk whose contents need preserving.

Safety checks reject the production path, its resolved aliases/serial, the known
production `/dev/nvme0n1` node, live-root disk ancestry, partitions, read-only or
undersized disks, mounted children, swap, holders, ambiguous metadata, conflicting
partition labels and occupied `/mnt`. Only explicit by-id whole disks resolving
to supported physical/virtio disk nodes are accepted; loops and device-mapper
targets are deliberately unsupported. Live-root ancestry must be resolvable to
a block device: an overlay-root live ISO is refused rather than guessed safe.
Use a normal installed test machine or disposable guest with a separate test disk.
Identity and busy checks repeat after building and immediately after confirmation.

The pinned Disko helper formats **only the selected disk**, mounts under `/mnt`,
then read-only validation checks GPT, two partition types, a 1 GiB ESP, Btrfs using
the remaining space, filesystem types, exactly three subvolumes, mount source
identities, subvolume mapping, zstd/noatime, and restrictive EFI masks. The Nix plan
must have no swap configuration; no regular files (including swapfiles) may exist
in the freshly mounted subvolumes or ESP. Nothing installs an operating system.

Successful test mounts remain under `/mnt` for inspection. Re-run **only validation**,
without formatting or mounting anything, using:

```sh
sudo ./setup --verify-disko desktop /dev/disk/by-id/ACTUAL_DISPOSABLE_DISK_ID
```

Running `--test-disko` again is not a read-only operation and will refuse the still
mounted target. No automatic unmount or rollback occurs, on success or failure;
inspect mount sources before manually cleaning up disposable mounts. Never change
attached storage during the test. Host installation remains blocked pending backup,
restore, storage-test and separate installer-enablement review.
