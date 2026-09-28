# Local installation

Boot a NixOS live installer in **UEFI mode**, connect to the network, clone this
repository, then inspect the plan first:

```sh
./setup --help
./setup --check vm
sudo ./setup vm
```

Only `vm` is currently installable. It maps to `nixos-vm`, using the existing
Disko GPT layout on `/dev/vda`: a 1 GiB FAT ESP and remaining space as ext4 root.
The wrapper requires at least 32 GiB, including room for the configured 8 GiB
swapfile. It preserves the existing XFCE/LightDM, Home Manager, QEMU guest, SSH,
and systemd-boot configuration. The desktop's public key remains authorized for
Corey. Existing nixos-anywhere use is unaffected; this wrapper is an alternative
local workflow, not a replacement host definition.

VM preflight requires `systemd-detect-virt` to successfully report `qemu` or
`kvm`; physical machines, containers, unknown types, and detection failures are
refused. This does **not** prove `/dev/vda` is disposable. Use a newly created
disposable guest with no valuable disks or host block-device passthrough.

`desktop` maps to `nixos-desktop` but is deliberately refused: that host has
existing filesystem UUIDs, not a reviewed Disko installation definition.
`laptop` and `server` are not implemented. Unknown names are rejected.

## Safety boundaries

- Check mode can run without root. It evaluates the configuration and inspects
  the local disks, fetching locked Nix sources if needed. It does not build or
  execute Disko, mount filesystems, install a system, or change passwords.
- Installation requires root and a terminal. Do not pipe it through `tee`, run
  it with tracing, or use terminal session recording while entering passwords.
- All phases use one immutable snapshot of the repository and its locked inputs.
  The wrapper never updates `flake.lock` or fetches a separate latest Disko.
- The supported layout is deliberately narrow: one writable GPT disk, ext4 `/`,
  vfat `/boot`, and systemd-boot. Additional disks, LUKS/LVM/ZFS, other mount
  layouts, and declaratively managed Corey passwords need a reviewed extension.
- Mounted disks, active swap, block-device holders, partition-label collisions,
  and an occupied/nonempty/symlinked `/mnt` are refused. Nothing is automatically
  unmounted or deactivated to make a disk available.
- Failed directory/disk/mount/swap inspection is fatal. Root and EFI labels,
  partition paths, and filesystem targets must be distinct and consistent;
  existing target aliases must belong to the selected disk and remain distinct.
- The disk path, resolved path, model, serial/WWN, size and partition layout are
  displayed. The exact confirmation is `ERASE /dev/vda` for the VM. Disk identity
  and busy-state checks are repeated immediately before Disko runs.

The pinned Disko module generates
`system.build.destroyFormatMount/bin/disko-destroy-format-mount`. The wrapper
builds that output before confirmation and invokes it with the pinned version's
`--yes-wipe-all-disks` flag only after the stronger typed confirmation. It then
checks that `/mnt` and `/mnt/boot` are backed by the selected disk before calling
`nixos-install --root /mnt --flake SNAPSHOT#nixos-vm`. No root password prompt is
requested; root SSH remains disabled by the existing configuration.

After installation and mount/bootloader/user checks, `nixos-enter --root /mnt`
runs `/nix/var/nix/profiles/system/sw/bin/passwd corey` directly on the terminal.
The password is handled only by the installed `passwd`, never a setup variable,
pipe, command argument, log, Nix expression or plaintext temporary file. The
existing mutable-user policy allows that local password to persist on rebuilds.
No sops-nix or private key management is involved.
Mount, bootloader, and user verification is repeated after password setup before
reporting completion.

On any failure, stop and inspect the reported phase. There is no automatic
rollback or unmount. In particular, if installation succeeded but setting the
password failed, **do not erase/reinstall**; repair it interactively with:

```sh
sudo nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd corey'
```

On success, filesystems remain mounted and reboot is your choice. This wrapper
does not copy a writable Git checkout into Corey's home; clone the repository
there after login for subsequent maintenance.

## Preparing a physical desktop installer

Before adding desktop Disko, supply and review:

1. The actual target disk's `/dev/disk/by-id/...` path, model, serial/WWN and size.
2. Explicit authorization to erase it, verified backups, and whether any existing
   partitions/data or another operating system must be preserved.
3. The intended filesystem/subvolume layout, encryption, swap/hibernation needs,
   and EFI partition size. Current desktop Btrfs root/home/nix settings must not
   be silently replaced by the VM's ext4 layout.
4. A matching physical Disko module/import and reconciliation of the old hardware
   configuration's filesystem UUIDs, followed by installation tests on disposable
   media/VMs. Extend the wrapper's layout checks if that reviewed design needs it.

Never substitute a guessed stable ID or treat `/dev/sda`/`/dev/nvme0n1` as a
physical-machine installation identity.

## Non-destructive validation

```sh
bash -n setup
shellcheck setup
python3 tests/setup.py
./setup --help
./setup --check vm
nix flake check --no-update-lock-file
git diff --check
```

On the physical desktop, VM check mode must refuse the non-QEMU/KVM environment.
Tests use synthetic metadata and mocked installation boundaries, including
failure injection and confirmation/phase-order checks. They never execute Disko,
nixos-install, nixos-enter or passwd.

Preflight cannot make storage operations atomic with hotplug or other tools.
Keep the guest isolated and do not change disks or mounts during installation.
Failures may leave partial filesystems/mounts; inspection and recovery remain
manual, as does deciding whether the displayed disk is safe to erase.
