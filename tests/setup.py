#!/usr/bin/env python3
"""Installer safety gates with synthetic metadata; never run Disko/install/passwd."""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLAN = {
    "platform": "x86_64-linux", "hostname": "nixos-vm", "hasDisko": True,
    "root": "/mnt", "uefi": True, "esp": "/boot", "mutableUser": True,
    "passwordUnmanaged": True, "otherDevices": [],
    "disks": [{"device": "/dev/vda", "contentDevice": "/dev/vda", "destroy": True, "type": "gpt", "partitions": [
        {"device": "/dev/disk/by-partlabel/disk-main-root", "label": "disk-main-root",
         "filesystemDevice": "/dev/disk/by-partlabel/disk-main-root",
         "type": "8300", "contentType": "filesystem", "format": "ext4", "mountpoint": "/"},
        {"device": "/dev/disk/by-partlabel/disk-main-ESP", "label": "disk-main-ESP",
         "filesystemDevice": "/dev/disk/by-partlabel/disk-main-ESP",
         "type": "EF00", "contentType": "filesystem", "format": "vfat", "mountpoint": "/boot"},
    ]}],
    "filesystems": {
        "/": {"device": "/dev/disk/by-partlabel/disk-main-root", "fsType": "ext4"},
        "/boot": {"device": "/dev/disk/by-partlabel/disk-main-ESP", "fsType": "vfat"},
    },
}
DISK = {"blockdevices": [{"path": "/dev/vda", "kname": "setup-fixture-disk",
    "type": "disk", "ro": False, "size": 34359738368, "model": "Fixture",
    "serial": "TEST", "wwn": None, "maj:min": "252:0", "mountpoints": [None]}]}

# Only source functions: tests have no installation entry point. Host commands
# are replaced in the test shell, without adding bypass flags to the installer.
PRELUDE = r'''
source "$SETUP"
plan=$PLAN
target=nixos-vm
friendly=vm
snapshot=/nix/store/fixture-source
disk=/dev/vda
resolved=/dev/vda
disk_info=$DISK
uname() { printf 'x86_64\n'; }
systemd-detect-virt() { printf 'kvm\n'; }
readlink() {
  if [[ "${*: -1}" == /dev/vda* ]]; then printf '%s\n' "${*: -1}";
  else command readlink "$@"; fi
}
lsblk() {
  if [[ "$*" == *PATH,PARTLABEL* ]]; then printf '%s\n' "$ALL_DISKS";
  else printf '%s\n' "$DISK"; fi
}
swapon() { printf '%s' "$SWAPS"; }
findmnt() { printf '%s\n' "$MOUNTS"; }
'''


class SetupTests(unittest.TestCase):
    def run_gate(self, body, *, plan=None, disk=None, all_disks=None, mounts=None, swaps="", answer=None):
        env = dict(os.environ, SETUP=str(ROOT / 'setup'), PLAN=json.dumps(PLAN if plan is None else plan),
                   DISK=json.dumps(DISK if disk is None else disk),
                   ALL_DISKS=json.dumps(DISK if all_disks is None else all_disks),
                   MOUNTS=json.dumps({"filesystems": [{"target": "/"}]} if mounts is None else mounts), SWAPS=swaps)
        return subprocess.run(['bash', '-c', PRELUDE + '\n' + body], env=env,
                              capture_output=True, text=True, timeout=10, input=answer)

    def test_whitelist_and_help(self):
        for name in ('vm', 'desktop'):
            self.assertEqual(self.run_gate(f'select_host {name}').returncode, 0)
        for name in ('laptop', 'server', '../vm', 'nixos-vm', 'vm;reboot'):
            result = subprocess.run([str(ROOT / 'setup'), '--check', name], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, name)
        result = subprocess.run([str(ROOT / 'setup'), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('--check', result.stdout)

    def test_valid_plan_and_missing_disko(self):
        self.assertEqual(self.run_gate('validate_plan').returncode, 0)
        plan = copy.deepcopy(PLAN)
        plan['hasDisko'] = False
        result = self.run_gate('validate_plan', plan=plan)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not install-ready', result.stderr)

    def test_ambiguous_or_unsupported_plans_are_refused(self):
        changes = [dict(disks=[]), dict(disks=PLAN['disks'] * 2), dict(root='/'),
                   dict(otherDevices=['zpool']), dict(mutableUser=False),
                   dict(passwordUnmanaged=False), dict(uefi=False), dict(esp='/efi')]
        for change in changes:
            with self.subTest(change=change):
                self.assertNotEqual(self.run_gate('validate_plan', plan=PLAN | change).returncode, 0)
        plan = copy.deepcopy(PLAN)
        plan['filesystems']['/']['device'] = '/dev/sda2'
        self.assertNotEqual(self.run_gate('validate_plan', plan=plan).returncode, 0)
        plan = copy.deepcopy(PLAN)
        plan['disks'][0]['contentDevice'] = '/dev/sdb'
        self.assertNotEqual(self.run_gate('validate_plan', plan=plan).returncode, 0)

    def test_physical_disk_requires_stable_id(self):
        self.assertNotEqual(self.run_gate('target=nixos-desktop; validate_plan').returncode, 0)
        plan = copy.deepcopy(PLAN)
        plan['disks'][0]['device'] = '/dev/disk/by-id/fixture-only'
        plan['disks'][0]['contentDevice'] = '/dev/disk/by-id/fixture-only'
        self.assertEqual(self.run_gate('target=nixos-desktop; validate_plan', plan=plan).returncode, 0)

    def test_duplicate_partition_identities(self):
        for identity in ('label', 'device', 'both', 'filesystemDevice'):
            plan = copy.deepcopy(PLAN)
            root, esp = plan['disks'][0]['partitions']
            if identity in ('label', 'both'):
                esp['label'] = root['label']
            if identity in ('device', 'both'):
                esp['device'] = root['device']
                esp['filesystemDevice'] = root['device']
                plan['filesystems']['/boot']['device'] = root['device']
            if identity == 'filesystemDevice':
                esp['filesystemDevice'] = root['device']
            with self.subTest(identity=identity):
                self.assertNotEqual(self.run_gate('validate_plan', plan=plan).returncode, 0)

    def test_vm_requires_successful_qemu_or_kvm_detection(self):
        for name in ('qemu', 'kvm'):
            self.assertEqual(self.run_gate(
                f'systemd-detect-virt() {{ echo {name}; }}; require_vm').returncode, 0)
        for response in ('echo none; return 1', 'return 1', 'echo none', 'echo docker', 'echo vmware'):
            result = self.run_gate('systemd-detect-virt() { ' + response + '; }; require_vm')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('disposable QEMU/KVM', result.stderr)

    def test_missing_or_malformed_disk_metadata(self):
        for disk in ({}, {'blockdevices': []}, {'blockdevices': [{}]}):
            self.assertNotEqual(self.run_gate('is_block_device() { :; }; probe_disk', disk=disk).returncode, 0)
        for key in ('path', 'kname', 'size', 'ro', 'type', 'maj:min', 'mountpoints'):
            disk = copy.deepcopy(DISK)
            del disk['blockdevices'][0][key]
            with self.subTest(missing=key):
                self.assertNotEqual(self.run_gate('is_block_device() { :; }; probe_disk', disk=disk).returncode, 0)
        for change in ({'size': 'large'}, {'path': '/dev/sdb'}, {'mountpoints': 'none'}):
            disk = copy.deepcopy(DISK)
            disk['blockdevices'][0].update(change)
            self.assertNotEqual(self.run_gate('is_block_device() { :; }; probe_disk', disk=disk).returncode, 0)
        self.assertNotEqual(self.run_gate(
            "is_block_device() { :; }; lsblk() { echo '{broken'; }; probe_disk").returncode, 0)

    def test_missing_readonly_small_partition_and_multi_disks_refused(self):
        self.assertNotEqual(self.run_gate('is_block_device() { return 1; }; probe_disk').returncode, 0)
        for change in ({'ro': True}, {'size': 1024}, {'type': 'part'}):
            disk = copy.deepcopy(DISK)
            disk['blockdevices'][0].update(change)
            self.assertNotEqual(self.run_gate('is_block_device() { return 0; }; probe_disk', disk=disk).returncode, 0)
        disk = {'blockdevices': DISK['blockdevices'] * 2}
        self.assertNotEqual(self.run_gate('is_block_device() { return 0; }; probe_disk', disk=disk).returncode, 0)
        self.assertEqual(self.run_gate('is_block_device() { return 0; }; probe_disk').returncode, 0)

    def test_busy_disk_and_swap_are_refused(self):
        for change in ({'mountpoints': ['/']}, {'mountpoints': ['[SWAP]']}, {'type': 'crypt'}):
            disk = copy.deepcopy(DISK)
            disk['blockdevices'][0]['children'] = [dict(path='/dev/vda1', kname='setup-fixture-part', **change)]
            result = self.run_gate('check_unused', disk=disk)
            self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(self.run_gate('check_unused', swaps='/dev/vda\n').returncode, 0)

    def test_partition_label_collision_on_other_disk(self):
        other = {'blockdevices': [{'path': '/dev/sdb1', 'partlabel': 'disk-main-root'}]}
        result = self.run_gate('check_mount_directory() { :; }; check_unused', all_disks=other)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('another disk', result.stderr)

    def test_only_exact_disk_confirmation_is_accepted(self):
        for answer in ('yes\n', 'y\n', 'ERASE /dev/sda\n', 'ERASE /dev/vda \n', '', '\n'):
            self.assertNotEqual(self.run_gate('confirm_erase', answer=answer).returncode, 0)
        self.assertEqual(self.run_gate('confirm_erase', answer='ERASE /dev/vda\n').returncode, 0)

    def test_mount_verification_checks_both_partitions_and_filesystem_types(self):
        disk = copy.deepcopy(DISK)
        disk['blockdevices'][0]['children'] = [{'path': '/dev/vda1'}, {'path': '/dev/vda2'}]
        body = r'''
readlink() {
  case "${*: -1}" in
    */disk-main-root) printf '/dev/vda2\n' ;;
    */disk-main-ESP) printf '/dev/vda1\n' ;;
    *) printf '%s\n' "${*: -1}" ;;
  esac
}
findmnt() {
  if [[ "$*" == *FSTYPE ]]; then
    if [[ "$*" == *'/mnt/boot'* ]]; then printf '%s\n' "${BOOT_TYPE:-vfat}";
    else printf 'ext4\n'; fi
  elif [[ "$*" == *'/mnt/boot'* ]]; then printf '%s\n' "${BOOT_DEVICE:-/dev/vda1}";
  else printf '/dev/vda2\n'; fi
}
verify_mounts
'''
        self.assertEqual(self.run_gate(body, disk=disk).returncode, 0)
        for fault in ('BOOT_TYPE=ext4', 'BOOT_DEVICE=/dev/sdb1'):
            self.assertNotEqual(self.run_gate(fault + '\n' + body, disk=disk).returncode, 0)

    def test_mount_directory_must_be_empty_unmounted_and_not_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            body = f'check_mount_directory "{path}"'
            self.assertEqual(self.run_gate(body).returncode, 0)
            for target in (str(path), str(path / 'boot')):
                result = self.run_gate(body, mounts={'filesystems': [{'target': target}]})
                self.assertNotEqual(result.returncode, 0)
            (path / 'keep').touch()
            self.assertNotEqual(self.run_gate(body).returncode, 0)
            (path / 'keep').unlink()
            (path / 'boot').symlink_to('/tmp')
            self.assertNotEqual(self.run_gate(body).returncode, 0)

    def test_check_mode_stops_before_any_installation_command(self):
        # An end-to-end check with synthetic hardware; any destructive boundary
        # or Nix build invocation is an immediate test failure, not a real call.
        result = self.run_gate(r'''
evaluate_plan() { snapshot=/nix/store/fixture-source; plan=$PLAN; }
require_uefi() { :; }
is_block_device() { return 0; }
check_mount_directory() { :; }
nix_cmd() { die 'UNEXPECTED nix operation'; }
nixos-install() { die 'UNEXPECTED installation'; }
nixos-enter() { die 'UNEXPECTED chroot'; }
main --check vm
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CHECK PASSED', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stderr)

    def run_install(self, fault='', *, answer='ERASE /dev/vda\n'):
        # Exercise main, real validation, repeated preflight, and exact confirmation.
        # Replace ALL effectful boundaries before entry: no store builds, /run lock,
        # Disko, installation, chroot, terminal password I/O, or mounts can run.
        with tempfile.TemporaryDirectory() as tmp:
            body = r'''
require_root() { :; }
require_terminal() { :; }
require_uefi() { :; }
evaluate_plan() { echo EVENT:preflight; snapshot=/nix/store/fixture-source; plan=$PLAN; }
is_block_device() { :; }
show_disk() { :; }
lock_installation() { echo EVENT:lock; }
build_disko() { echo EVENT:build; }
run_disko() { echo EVENT:disko; }
nixos-install() {
  [[ "$*" == *'--root /mnt --flake /nix/store/fixture-source#nixos-vm'* ]] || return 99
  echo EVENT:install
}
set_password() { echo EVENT:passwd; }
verify_mounts() { echo EVENT:mount-verification; }
verify_installation() { echo "EVENT:$phase"; }
nix_cmd() { die 'UNEXPECTED real Nix call'; }
nixos-enter() { die 'UNEXPECTED real chroot call'; }
eval "$(declare -f confirm_erase | sed '1s/confirm_erase/real_confirm_erase/')"
confirm_erase() { real_confirm_erase; echo EVENT:confirmed; }
eval "$(declare -f check_mount_directory | sed '1s/check_mount_directory/real_check_mount_directory/')"
'''
            body += f'check_mount_directory() {{ real_check_mount_directory "{tmp}"; }}\n'
            return self.run_gate(body + fault + '\nmain vm', answer=answer)

    def test_mocked_successful_install_sequence(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [line for line in result.stdout.splitlines() if 'EVENT:' in line]
        events = [line[line.index('EVENT:') + 6:] for line in events]
        self.assertEqual(events, [
            'preflight', 'lock', 'build', 'confirmed', 'disko',
            'mount-verification', 'install', 'verification before setting password',
            'passwd', 'post-install verification',
        ])

    def test_failed_preflight_never_reaches_destructive_phases(self):
        faults = [
            'find() { return 1; }',
            'find() { printf occupied; return 1; }',
            'lsblk() { return 1; }',
            'findmnt() { return 1; }',
            'swapon() { return 1; }',
            'lsblk() { echo "{}"; }',
            'lsblk() { echo malformed; }',
            'findmnt() { echo "{}"; }',
            'systemd-detect-virt() { echo none; return 1; }',
        ]
        for fault in faults:
            with self.subTest(fault=fault):
                result = self.run_install(fault)
                self.assertNotEqual(result.returncode, 0)
                for event in ('lock', 'build', 'confirmed', 'disko', 'install', 'passwd'):
                    self.assertNotIn('EVENT:' + event, result.stdout)

    def test_confirmation_failure_never_reaches_disko(self):
        for answer in ('', 'yes\n', 'ERASE /dev/sda\n', 'ERASE /dev/vda \n'):
            result = self.run_install(answer=answer)
            self.assertNotEqual(result.returncode, 0)
            for event in ('confirmed', 'disko', 'install', 'passwd'):
                self.assertNotIn('EVENT:' + event, result.stdout)

    def test_disko_failure_stops_install_and_password(self):
        result = self.run_install('run_disko() { echo EVENT:disko; return 42; }')
        self.assertEqual(result.returncode, 42)
        self.assertIn('EVENT:disko', result.stdout)
        self.assertNotIn('EVENT:install', result.stdout)
        self.assertNotIn('EVENT:passwd', result.stdout)

    def test_install_failure_stops_password(self):
        result = self.run_install('nixos-install() { echo EVENT:install; return 43; }')
        self.assertEqual(result.returncode, 43)
        self.assertIn('EVENT:install', result.stdout)
        self.assertNotIn('EVENT:passwd', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
