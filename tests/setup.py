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
# Synthetic two-filesystem fixture for reusable helpers; not an installable host.
PLAN = {
    "platform": "x86_64-linux", "hostname": "fixture-host", "hasDisko": True,
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
    "serial": "TEST", "wwn": None, "maj:min": "252:0", "mountpoints": [None],
    "children": [{"path": f"/dev/vda{n}", "kname": f"setup-fixture-part{n}",
                  "type": "part", "mountpoints": [None]} for n in (1, 2)]}]}

DESKTOP_DEVICE = '/dev/disk/by-id/nvme-SIX_X7400_SSD_STX26012100037853'
DESKTOP_PLAN = copy.deepcopy(PLAN)
DESKTOP_PLAN.update(hostname='nixos-desktop', swapDevices=[])
DESKTOP_PLAN['disks'][0].update(device=DESKTOP_DEVICE, contentDevice=DESKTOP_DEVICE)
root, esp = DESKTOP_PLAN['disks'][0]['partitions']
root.update(size='100%', contentType='btrfs', format=None, mountpoint=None, swap={}, subvolumes={})
esp.update(size='1G', mountOptions=['umask=0077'])
DESKTOP_PLAN['filesystems']['/boot']['options'] = ['umask=0077']
for name, mountpoint in (('@root', '/'), ('@home', '/home'), ('@nix', '/nix')):
    root['subvolumes'][name] = dict(name=name, mountpoint=mountpoint,
                                  mountOptions=['compress=zstd', 'noatime'], swap={})
    DESKTOP_PLAN['filesystems'][mountpoint] = dict(
        device=root['device'], fsType='btrfs', options=['compress=zstd', 'noatime', f'subvol={name}'])
    if mountpoint in ('/', '/nix'):
        DESKTOP_PLAN['filesystems'][mountpoint]['options'].insert(0, 'x-initrd.mount')
DESKTOP_DISK = {'blockdevices': [dict(
    path='/dev/nvme0n1', kname='setup-fixture-nvme', type='disk', ro=False,
    size=1024209543168, model='SIX X7400 SSD', serial='STX26012100037853', wwn=None,
    **{'maj:min': '259:0', 'mountpoints': [None], 'children': [dict(
        path='/dev/nvme0n1p2', kname='setup-fixture-nvme-part', type='part', mountpoints=['/', '/home', '/nix'])]})]}

TEST_DEVICE = '/dev/disk/by-id/usb-DISPOSABLE_TEST_ONLY'
TEST_PLAN = copy.deepcopy(DESKTOP_PLAN)
TEST_PLAN['disks'][0].update(device='/dev/sdz', contentDevice='/dev/sdz')
TEST_DISK = copy.deepcopy(DISK)
TEST_DISK['blockdevices'][0].update(path='/dev/sdz', size=17179869184, serial='DISPOSABLE', children=[
    dict(path='/dev/sdz1', kname='setup-fixture-esp', type='part', mountpoints=[None]),
    dict(path='/dev/sdz2', kname='setup-fixture-btrfs', type='part', mountpoints=[None]),
])
TEST_TABLE = {'partitiontable': dict(label='gpt', device='/dev/sdz', unit='sectors', sectorsize=512, partitions=[
    dict(node='/dev/sdz1', start=2048, size=2097152, type='C12A7328-F81F-11D2-BA4B-00A0C93EC93B'),
    dict(node='/dev/sdz2', start=2099200, size=31455200, type='0FC63DAF-8483-4772-8E79-3D69D8477DE4'),
])}

# Only source functions: tests have no installation entry point. Host commands
# are replaced in the test shell, without adding bypass flags to the installer.
PRELUDE = r'''
source "$SETUP"
source "${SETUP%/*}/tests/disposable-disko.sh"
plan=$PLAN
target=fixture-host
friendly=fixture
snapshot=/nix/store/fixture-source
disk=/dev/vda
resolved=/dev/vda
disk_info=$DISK
is_block_device() { :; }
eval "$(declare -f check_holders | sed '1s/check_holders/real_check_holders/')"
check_holders() { real_check_holders "$HOLDER_DIR"; }
uname() { printf 'x86_64\n'; }
readlink() {
  if [[ "${*: -1}" == /dev/vda* || "${*: -1}" == /dev/sdy* ]]; then printf '%s\n' "${*: -1}";
  elif [[ "${*: -1}" == /dev/disk/by-partlabel/disk-main-ESP ]]; then echo /dev/vda1;
  elif [[ "${*: -1}" == /dev/disk/by-partlabel/disk-main-root ]]; then echo /dev/vda2;
  else command readlink "$@"; fi
}
lsblk() {
  if [[ "$*" == *--inverse* ]]; then
    echo '{"blockdevices":[{"path":"/dev/sdy2","type":"part","children":[{"path":"/dev/sdy","type":"disk"}]}]}'
  elif [[ "$*" == *--tree* && "${*: -1}" == /dev/sdy ]]; then
    echo '{"blockdevices":[{"path":"/dev/sdy","type":"disk","children":[{"path":"/dev/sdy2","type":"part"}]}]}'
  elif [[ "$*" == *PATH,PARTLABEL* ]]; then printf '%s\n' "$ALL_DISKS";
  else printf '%s\n' "$DISK"; fi
}
swapon() { printf '%s' "$SWAPS"; }
findmnt() {
  if [[ "$*" == *'--mountpoint / --output SOURCE'* ]]; then echo /dev/sdy2;
  else printf '%s\n' "$MOUNTS"; fi
}
'''


class SetupTests(unittest.TestCase):
    def run_gate(self, body, *, plan=None, disk=None, all_disks=None, mounts=None, swaps="", answer=None, extra_env=None):
        env = dict(os.environ, SETUP=str(ROOT / 'setup'), PLAN=json.dumps(PLAN if plan is None else plan),
                   DISK=json.dumps(DISK if disk is None else disk),
                   ALL_DISKS=json.dumps(DISK if all_disks is None else all_disks),
                   MOUNTS=json.dumps({"filesystems": [{"target": "/"}]} if mounts is None else mounts), SWAPS=swaps)
        env.update(extra_env or {})
        with tempfile.TemporaryDirectory() as holders:
            env['HOLDER_DIR'] = holders
            return subprocess.run(['bash', '-c', PRELUDE + '\n' + body], env=env,
                                  capture_output=True, text=True, timeout=10, input=answer)

    def test_whitelist_and_help(self):
        for name in ('desktop',):
            self.assertEqual(self.run_gate(f'select_host {name}').returncode, 0)
        for name in ('vm', 'laptop', 'server', '../fixture', 'fixture-host', 'fixture;reboot'):
            result = subprocess.run([str(ROOT / 'setup'), '--check', name], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, name)
        result = subprocess.run([str(ROOT / 'setup'), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('--check', result.stdout)

    def test_valid_plan_and_missing_disko(self):
        self.assertEqual(self.run_gate('validate_plan', plan=DESKTOP_PLAN).returncode, 0)
        plan = copy.deepcopy(DESKTOP_PLAN)
        plan['hasDisko'] = False
        result = self.run_gate('validate_plan', plan=plan)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not install-ready', result.stderr)

    def test_ambiguous_or_unsupported_plans_are_refused(self):
        changes = [dict(disks=[]), dict(disks=DESKTOP_PLAN['disks'] * 2), dict(root='/'),
                   dict(otherDevices=['zpool']), dict(mutableUser=False),
                   dict(passwordUnmanaged=False), dict(uefi=False), dict(esp='/efi')]
        for change in changes:
            with self.subTest(change=change):
                self.assertNotEqual(self.run_gate('validate_plan', plan=DESKTOP_PLAN | change).returncode, 0)
        plan = copy.deepcopy(DESKTOP_PLAN)
        plan['filesystems']['/']['device'] = '/dev/sda2'
        self.assertNotEqual(self.run_gate('validate_plan', plan=plan).returncode, 0)
        plan = copy.deepcopy(DESKTOP_PLAN)
        plan['disks'][0]['contentDevice'] = '/dev/sdb'
        self.assertNotEqual(self.run_gate('validate_plan', plan=plan).returncode, 0)

    def test_physical_disk_requires_stable_id(self):
        self.assertNotEqual(self.run_gate('target=nixos-desktop; validate_plan').returncode, 0)
        self.assertEqual(self.run_gate('target=nixos-desktop; validate_plan', plan=DESKTOP_PLAN).returncode, 0)

    def run_desktop(self, fault='', *, plan=None, disk=None, install=False):
        # No real block-device/firmware calls, Nix evaluation, or install boundary.
        body = r'''
evaluate_plan() { snapshot=path:/nix/store/fixture-source; plan=$PLAN; }
is_uefi() { :; }
is_block_device() { :; }
eval "$(declare -f readlink | sed '1s/readlink/fixture_readlink/')"
readlink() {
  if [[ "${*: -1}" == "$DESKTOP_DISK" ]]; then printf '/dev/nvme0n1\n';
  else fixture_readlink "$@"; fi
}
require_root() { die 'UNEXPECTED root check'; }
require_terminal() { die 'UNEXPECTED terminal check'; }
check_unused() { die 'UNEXPECTED unused-disk check'; }
lock_installation() { die 'UNEXPECTED lock'; }
build_disko() { die 'UNEXPECTED build'; }
run_disko() { die 'UNEXPECTED Disko'; }
confirm_erase() { die 'UNEXPECTED confirmation'; }
nix_cmd() { die 'UNEXPECTED Nix operation'; }
nixos-install() { die 'UNEXPECTED installation'; }
nixos-enter() { die 'UNEXPECTED chroot'; }
set_password() { die 'UNEXPECTED password'; }
'''
        body += fault + '\nmain ' + ('desktop' if install else '--check desktop')
        return self.run_gate(body, plan=DESKTOP_PLAN if plan is None else plan,
                             disk=DESKTOP_DISK if disk is None else disk)

    def test_desktop_check_accepts_exact_identity_and_mounted_production_disk(self):
        result = self.run_desktop()
        self.assertEqual(result.returncode, 0, result.stderr)
        for message in ('DESKTOP REVIEW CHECK PASSED', DESKTOP_DEVICE, 'SIX X7400 SSD',
                        'STX26012100037853', '/dev/nvme0n1', 'Current mounts', '@root'):
            self.assertIn(message, result.stdout)
        self.assertNotIn('UNEXPECTED', result.stderr)

    def test_desktop_identity_failures(self):
        for change in ({'serial': 'WRONG'}, {'model': 'WRONG'}, {'size': 500000000000},
                       {'size': 2048000000000}):
            disk = copy.deepcopy(DESKTOP_DISK)
            disk['blockdevices'][0].update(change)
            with self.subTest(change=change):
                self.assertNotEqual(self.run_desktop(disk=disk).returncode, 0)
        for fault in (
            'is_block_device() { return 1; }',
            'readlink() { if [[ "${*: -1}" == "$DESKTOP_DISK" ]]; then echo /dev/nvme1n1; else fixture_readlink "$@"; fi; }',
            'is_uefi() { return 1; }',
            'lsblk() { printf "%s\\n" "$DISK" | jq ".blockdevices += .blockdevices"; }',
            'lsblk() { if [[ "$*" == *--nodeps* ]]; then printf "%s\\n" "$DISK" | jq ".blockdevices += .blockdevices"; else printf "%s\\n" "$DISK"; fi; }',
        ):
            result = self.run_desktop(fault)
            self.assertNotEqual(result.returncode, 0, fault)
            self.assertNotIn('UNEXPECTED', result.stderr)

    def test_desktop_capacity_tolerance(self):
        for delta in (-1073741824, 1073741824):
            disk = copy.deepcopy(DESKTOP_DISK)
            disk['blockdevices'][0]['size'] += delta
            self.assertEqual(self.run_desktop(disk=disk).returncode, 0)

    def test_desktop_rejects_mismatched_plan(self):
        for device in ('/dev/nvme0n1', '/dev/disk/by-id/wrong-ssd'):
            plan = copy.deepcopy(DESKTOP_PLAN)
            plan['disks'][0].update(device=device, contentDevice=device)
            self.assertNotEqual(self.run_desktop(plan=plan).returncode, 0)
        for fault in ('subvolume', 'filesystem', 'esp-size', 'swap'):
            plan = copy.deepcopy(DESKTOP_PLAN)
            if fault == 'subvolume':
                plan['disks'][0]['partitions'][0]['subvolumes']['@home']['mountpoint'] = '/'
            elif fault == 'filesystem':
                plan['filesystems']['/home']['options'] = ['compress=zstd', 'noatime', 'subvol=@root']
            elif fault == 'esp-size':
                plan['disks'][0]['partitions'][1]['size'] = '2G'
            else:
                plan['swapDevices'] = ['/swapfile']
            self.assertNotEqual(self.run_desktop(plan=plan).returncode, 0)

    def test_desktop_install_is_disabled_even_with_valid_identity_and_plan(self):
        self.assertEqual(self.run_desktop().returncode, 0)
        result = self.run_desktop(install=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('destructive desktop installation is not yet enabled', result.stderr)
        self.assertNotIn('UNEXPECTED', result.stderr)

    def test_duplicate_partition_identities(self):
        for identity in ('label', 'device', 'both', 'filesystemDevice'):
            plan = copy.deepcopy(DESKTOP_PLAN)
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

    def test_missing_readonly_partition_and_multi_disks_refused(self):
        self.assertNotEqual(self.run_gate('is_block_device() { return 1; }; probe_disk').returncode, 0)
        for change in ({'ro': True}, {'type': 'part'}):
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

    def test_duplicate_label_on_two_target_partitions_is_refused(self):
        inventory = copy.deepcopy(DISK)
        for part in inventory['blockdevices'][0]['children']:
            part['partlabel'] = 'disk-main-root'
        result = self.run_gate('check_mount_directory() { :; }; check_unused', all_disks=inventory)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Ambiguous planned partition label', result.stderr)

    def test_only_exact_disk_confirmation_is_accepted(self):
        for answer in ('yes\n', 'y\n', 'ERASE /dev/sda\n', 'ERASE /dev/vda \n', '', '\n'):
            self.assertNotEqual(self.run_gate('confirm_erase', answer=answer).returncode, 0)
        self.assertEqual(self.run_gate('confirm_erase', answer='ERASE /dev/vda\n').returncode, 0)

    def test_holder_inspection_failures_and_active_holders(self):
        for fault in (
            'real_check_holders /definitely-missing-holder-directory',
            'find() { return 1; }; real_check_holders "$HOLDER_DIR"',
            'find() { echo occupied; }; real_check_holders "$HOLDER_DIR"',
        ):
            result = self.run_gate(fault)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('holder', result.stderr.lower())
        self.assertEqual(self.run_gate('real_check_holders "$HOLDER_DIR"').returncode, 0)

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
        result = self.run_desktop()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CHECK PASSED', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stderr)

    def run_install(self, fault='', *, answer='ERASE /dev/vda\n'):
        # Exercise reusable installation ordering with a synthetic host only.
        # Production host selection and the desktop lock are tested separately.
        # Replace ALL effectful boundaries before entry: no store builds, /run lock,
        # Disko, installation, chroot, terminal password I/O, or mounts can run.
        with tempfile.TemporaryDirectory() as tmp:
            body = r'''
select_host() { [[ "$1" == fixture ]] || return 1; target=fixture-host; }
require_install_enabled() { :; }
validate_plan() { disk=$(jq -er ".disks[0].device" <<<"$plan"); }
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
  [[ "$*" == *'--root /mnt --flake /nix/store/fixture-source#fixture-host'* ]] || return 99
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
            return self.run_gate(body + fault + '\nmain fixture', answer=answer)

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


class DisposableTests(unittest.TestCase):
    run_gate = SetupTests.run_gate

    def run_disposable(self, body, *, disk=None, table=None, swaps='', answer=None, identities=None, production=False):
        mocks = r'''
target=disposable
disk=/dev/disk/by-id/usb-DISPOSABLE_TEST_ONLY
resolved=/dev/sdz
test_plan=$PLAN
repo=${SETUP%/*}
is_block_device() { :; }
readlink() {
  case "${*: -1}" in
    /dev/disk/by-id/usb-DISPOSABLE_TEST_ONLY) echo /dev/sdz ;;
    "$DESKTOP_DISK") echo /dev/nvme0n1 ;;
    /dev/nvme0n1p2) echo /dev/nvme0n1p2 ;;
    /dev/disk/by-partlabel/disk-main-ESP|/dev/disk/by-id/test-part1) echo /dev/sdz1 ;;
    /dev/disk/by-partlabel/disk-main-root|/dev/disk/by-id/test-part2) echo /dev/sdz2 ;;
    /dev/*) printf '%s\n' "${*: -1}" ;;
    *) command readlink "$@" ;;
  esac
}
lsblk() {
  if [[ "$*" == *--inverse* ]]; then
    echo '{"blockdevices":[{"path":"/dev/nvme0n1p2","type":"part","children":[{"path":"/dev/nvme0n1","type":"disk"}]}]}'
  elif [[ "$*" == *--tree* && "$*" == */dev/nvme0n1 ]]; then
    echo '{"blockdevices":[{"path":"/dev/nvme0n1","type":"disk","children":[{"path":"/dev/nvme0n1p1","type":"part"},{"path":"/dev/nvme0n1p2","type":"part"}]}]}'
  elif [[ "$*" == *--nodeps* && "$*" == *MAJ:MIN* ]]; then
    local dev=${*: -1} label id parent=/dev/sdz
    case "$dev" in
      /dev/sdz1) label=disk-main-ESP; id=8:241 ;;
      /dev/sdz2) label=disk-main-root; id=8:242 ;;
      /dev/sdz3) label=disk-main-ESP; id=8:243 ;;
      /dev/sdy1) label=disk-main-ESP; id=8:225; parent=/dev/sdy ;;
      *) return 1 ;;
    esac
    printf '{"blockdevices":[{"path":"%s","type":"part","pkname":"%s","partlabel":"%s","maj:min":"%s"}]}\n' "$dev" "$parent" "$label" "$id"
  elif [[ "$*" == *--list* ]]; then echo "$IDENTITIES"
  elif [[ "$*" == *PATH,PARTLABEL* ]]; then echo "$ALL_DISKS"
  else echo "$DISK"; fi
}
findmnt() {
  if [[ "$*" == *'--mountpoint / --output SOURCE'* ]]; then echo /dev/nvme0n1p2
  elif [[ "$*" == *'--mountpoint / --output MAJ:MIN'* ]]; then echo 259:2
  elif [[ "$*" == *'--output TARGET'* ]]; then echo "$MOUNTS"
  elif [[ "$*" == *'/mnt/boot'* ]]; then
    echo '{"filesystems":[{"maj:min":"8:241","fstype":"vfat","fsroot":"/","options":"rw,fmask=0077,dmask=0077"}]}'
  else
    local subvol=/@root
    [[ "$*" != *'/mnt/home'* ]] || subvol=/@home
    [[ "$*" != *'/mnt/nix'* ]] || subvol=/@nix
    [[ "$*" == *--nofsroot* ]] || return 1
    printf '{"filesystems":[{"source":"%s","maj:min":"0:97","fstype":"btrfs","fsroot":"%s","options":"rw,noatime,compress=zstd:3"}]}\n' "${BTRFS_SOURCE:-/dev/sdz2}" "$subvol"
  fi
}
sfdisk() { echo "$TABLE"; }
blkid() { case "${*: -1}" in /dev/sdz1) echo vfat ;; /dev/sdz2) echo btrfs ;; *) return 1 ;; esac; }
btrfs() { printf 'ID 256 gen 1 top level 5 path @root\nID 257 gen 1 top level 5 path @home\nID 258 gen 1 top level 5 path @nix\n'; }
find() { if [[ "${1:-}" == "$HOLDER_DIR" ]]; then command find "$@"; fi; }
check_mount_directory() { :; }
require_root() { :; }
require_terminal() { :; }
evaluate_disposable() { test_plan=$PLAN; snapshot=path:/nix/store/fixture-source; }
lock_installation() { echo EVENT:lock; }
build_disposable() { echo EVENT:build; }
run_disko() { echo EVENT:disko; }
nix_cmd() { die 'UNEXPECTED real Nix call'; }
nixos-install() { die 'UNEXPECTED install'; }
nixos-enter() { die 'UNEXPECTED chroot'; }
set_password() { die 'UNEXPECTED passwd'; }
'''
        if production:
            mocks = mocks.replace('/dev/nvme0n1p2', '/dev/sdy2').replace('/dev/nvme0n1p1', '/dev/sdy1').replace('/dev/nvme0n1', '/dev/sdy')
            for n in (1, 2, 3):
                mocks = mocks.replace(f'/dev/sdz{n}', f'/dev/nvme0n1p{n}')
            mocks = mocks.replace('/dev/sdz', '/dev/nvme0n1').replace('target=disposable', 'target=nixos-desktop')
            mocks = mocks.replace('disk=/dev/disk/by-id/usb-DISPOSABLE_TEST_ONLY', 'disk=$DESKTOP_DISK')
            mocks = mocks.replace('"$DESKTOP_DISK") echo /dev/sdy', '"$DESKTOP_DISK") echo /dev/nvme0n1')
            disk = copy.deepcopy(DESKTOP_DISK) if disk is None else disk
            if identities is None:
                identities = [{'path': f'/dev/nvme0n1p{n}', 'partlabel': label}
                              for n, label in ((1, 'disk-main-ESP'), (2, 'disk-main-root'))]
        return self.run_gate(mocks + '\n' + body, plan=DESKTOP_PLAN if production else TEST_PLAN,
                             disk=TEST_DISK if disk is None else disk, swaps=swaps,
                             extra_env={'TABLE': json.dumps(TEST_TABLE if table is None else table),
                                        'IDENTITIES': json.dumps({'blockdevices': identities if identities is not None else [
                                            {'path': '/dev/sdz1', 'partlabel': 'disk-main-ESP'},
                                            {'path': '/dev/sdz2', 'partlabel': 'disk-main-root'}]})}, answer=answer)

    def run_production_install(self, fault='', *, disk=None):
        # Keep real plan/disk/ancestry/busy/partition/mount validation. Only
        # hardware commands and destructive/install/password boundaries are mocked.
        disk = copy.deepcopy(DESKTOP_DISK) if disk is None else disk
        disk['blockdevices'][0]['children'] = [
            dict(path=f'/dev/nvme0n1p{n}', kname=f'fixture-part{n}', type='part', mountpoints=[None])
            for n in (1, 2)]
        body = r'''
check=false
phase=preflight
friendly=desktop
snapshot=path:/nix/store/fixture-source
is_uefi() { :; }
partition_identity_exists() { :; }
# Give real /mnt inspection an empty temporary directory rather than touching /mnt.
eval "$(declare -f find | sed '1s/find/fixture_find/')"
find() { if [[ "${1:-}" == "$HOLDER_DIR"* ]]; then command find "$@"; else fixture_find "$@"; fi; }
# Source the original check (the disposable harness mocks it).
eval "$(sed -n '/^check_mount_directory() {/,/^}/p' "$SETUP" | sed '1s/check_mount_directory/real_mount_directory/')"
check_mount_directory() { real_mount_directory "$HOLDER_DIR"; }
build_disko() { echo EVENT:build; }
run_disko() { echo EVENT:disko; }
nixos-install() {
  [[ "$*" == *'--root /mnt --flake path:/nix/store/fixture-source#nixos-desktop'* ]] || return 99
  echo EVENT:install
}
set_password() { echo EVENT:passwd; }
# Boot file and installed-user checks are simulated; mount verification is real.
verify_installation() { verify_mounts; echo EVENT:verified; }
'''
        body += fault + r'''
validate_plan
require_uefi
probe_disk
install_target
'''
        return self.run_disposable(body, disk=disk, production=True,
                                   answer=f'ERASE {DESKTOP_DEVICE}\n')

    def test_production_btrfs_install_validation_and_order(self):
        result = self.run_production_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = [line[line.index('EVENT:'):] for line in result.stdout.splitlines() if 'EVENT:' in line]
        self.assertEqual(events, ['EVENT:lock', 'EVENT:build', 'EVENT:disko',
                                  'EVENT:install', 'EVENT:verified', 'EVENT:passwd', 'EVENT:verified'])

    def test_production_safety_failures_prevent_disko(self):
        faults = [
            'find() { return 1; }',
            'check_holders() { real_check_holders /missing-holders; }',
            'swapon() { echo /dev/nvme0n1p2; }',
            'lsblk() { return 1; }',
            r'''eval "$(declare -f findmnt | sed '1s/findmnt/original_findmnt/')"
findmnt() { if [[ "$*" == *'--mountpoint / --output SOURCE'* ]]; then echo /dev/nvme0n1p2; else original_findmnt "$@"; fi; }''',
        ]
        for fault in faults:
            result = self.run_production_install(fault)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('EVENT:disko', result.stdout)
            self.assertNotIn('EVENT:install', result.stdout)
        for change in ({'serial': 'wrong'}, {'mountpoints': ['/']}):
            disk = copy.deepcopy(DESKTOP_DISK)
            disk['blockdevices'][0].update(change)
            result = self.run_production_install(disk=disk)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('EVENT:disko', result.stdout)

    def test_production_distinct_partitions_cannot_share_identity(self):
        fault = r'''
eval "$(declare -f readlink | sed '1s/readlink/original_readlink/')"
readlink() { if [[ "${*: -1}" == /dev/disk/by-partlabel/disk-main-ESP ]]; then echo /dev/nvme0n1p2; else original_readlink "$@"; fi; }
'''
        result = self.run_production_install(fault)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Filesystem targets resolve to the same device', result.stderr)
        self.assertNotIn('EVENT:disko', result.stdout)

    def test_production_live_root_disk_is_refused(self):
        fault = r'''
eval "$(declare -f findmnt | sed '1s/findmnt/original_findmnt/')"
eval "$(declare -f lsblk | sed '1s/lsblk/original_lsblk/')"
findmnt() { if [[ "$*" == *'--mountpoint / --output SOURCE'* ]]; then echo /dev/nvme0n1p2; else original_findmnt "$@"; fi; }
lsblk() {
  if [[ "$*" == *--inverse* ]]; then
    echo '{"blockdevices":[{"path":"/dev/nvme0n1p2","type":"part","children":[{"path":"/dev/nvme0n1","type":"disk"}]}]}'
  else original_lsblk "$@"; fi
}
'''
        result = self.run_production_install(fault)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Selected target is the live-root disk', result.stderr)
        self.assertNotIn('EVENT:disko', result.stdout)

    def test_production_bad_mounts_prevent_install_and_password(self):
        changes = [
            ('/mnt/home', '.filesystems[0].fsroot = "/@root"'),
            ('/mnt/nix', '.filesystems[0].source = "/dev/sdy2"'),
            ('/mnt', '.filesystems[0].options = "rw,noatime"'),
            ('/mnt/home', '.filesystems[0].options = "rw,compress=zstd"'),
            ('/mnt/boot', '.filesystems[0].options = "rw,fmask=0022,dmask=0022"'),
            ('/mnt/boot', '.filesystems[0]["maj:min"] = "8:242"'),
            ('/mnt/nix', '.filesystems = []'),
        ]
        for mount, change in changes:
            fault = r'''eval "$(declare -f findmnt | sed '1s/findmnt/original_findmnt/')"
findmnt() {
  local output
  output=$(original_findmnt "$@") || return
''' + f'  if [[ "$*" == *"--mountpoint {mount} --output"* ]]; then jq \'{change}\' <<<"$output"; else printf "%s\\n" "$output"; fi; }}'
            result = self.run_production_install(fault)
            self.assertNotEqual(result.returncode, 0, (mount, result.stdout))
            self.assertIn('EVENT:disko', result.stdout)
            self.assertNotIn('EVENT:install', result.stdout)
            self.assertNotIn('EVENT:passwd', result.stdout)

    def test_live_root_inventory_must_contain_root_and_disk(self):
        for tree in ({'blockdevices': []}, {}, {'blockdevices': [{'path': '/dev/nvme0n1', 'type': 'disk'}]},
                     {'blockdevices': [{'path': '/dev/sdy', 'type': 'disk', 'children': [{'path': '/dev/nvme0n1p2', 'type': 'part'}]}]}):
            fault = r'''eval "$(declare -f lsblk | sed '1s/lsblk/original_lsblk/')"
lsblk() { if [[ "$*" == *--tree* && "${*: -1}" == /dev/nvme0n1 ]]; then printf '%s\n' ''' + "'" + json.dumps(tree) + "'" + r'''; else original_lsblk "$@"; fi; }
disposable_identity
'''
            result = self.run_disposable(fault)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('live-root disk tree', result.stderr)

    def test_partition_aliases_deduplicate_for_both_filesystems(self):
        identities = [
            {'path': path, 'partlabel': label}
            for number, label in ((1, 'disk-main-ESP'), (2, 'disk-main-root'))
            for path in (f'/dev/sdz{number}', f'/dev/disk/by-partlabel/{label}',
                         f'/dev/disk/by-id/test-part{number}')]
        result = self.run_disposable('verify_disposable', identities=identities)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_btrfs_anonymous_mount_identity_uses_canonical_backing_device(self):
        for source in ('/dev/sdz2', '/dev/disk/by-id/test-part2'):
            result = self.run_disposable(f'BTRFS_SOURCE={source}; verify_disposable')
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_btrfs_wrong_or_unresolvable_backing_device_is_refused(self):
        for source in ('/dev/nvme0n1p2', '/dev/sdz1', 'none'):
            result = self.run_disposable(f'BTRFS_SOURCE={source}; verify_disposable')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('backing device', result.stderr)
        result = self.run_disposable('''
eval "$(declare -f readlink | sed '1s/readlink/fixture_readlink/')"
readlink() { [[ "${*: -1}" != /dev/missing ]] || return 1; fixture_readlink "$@"; }
BTRFS_SOURCE=/dev/missing
verify_disposable
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot resolve Btrfs backing device', result.stderr)

    def test_distinct_partition_candidates_and_foreign_parent_fail(self):
        for path, message in (('/dev/sdz3', 'Ambiguous partition identities'),
                              ('/dev/sdy1', 'Partition belongs to another disk')):
            result = self.run_disposable('verify_disposable', identities=[
                {'path': '/dev/sdz1', 'partlabel': 'disk-main-ESP'},
                {'path': path, 'partlabel': 'disk-main-ESP'},
                {'path': '/dev/sdz2', 'partlabel': 'disk-main-root'}])
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_missing_unresolvable_or_uninspectable_partition_fails(self):
        result = self.run_disposable('verify_disposable', identities=[])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing partition identity', result.stderr)
        for fault, message in (
                ('readlink() { return 1; }', 'Cannot resolve partition identity'),
                ('lsblk() { return 1; }', 'Cannot enumerate partition identities'),
                ('is_block_device() { return 1; }', 'not a block device')):
            result = self.run_disposable(f'{fault}; verify_disposable')
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)

    def test_explicit_disposable_sequence_and_repeat_readonly_verification(self):
        result = self.run_disposable('disposable_main --test-disko "$disk" "$repo"', answer=f'ERASE {TEST_DEVICE}\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('EVENT:disko'), 1)
        self.assertIn('DISPOSABLE LAYOUT VERIFIED', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stderr)
        result = self.run_disposable('disposable_main --verify-disko "$disk" "$repo"; disposable_main --verify-disko "$disk" "$repo"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('DISPOSABLE LAYOUT VERIFIED'), 2)
        self.assertNotIn('EVENT:', result.stdout)

    def test_confirmation_eof_or_mismatch_stops_disko(self):
        for answer in ('', 'yes\n', 'ERASE /dev/sdz\n'):
            result = self.run_disposable('disposable_main --test-disko "$disk" "$repo"', answer=answer)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('EVENT:disko', result.stdout)

    def test_production_disk_and_implicit_override_are_refused(self):
        for path in (DESKTOP_DEVICE, '/dev/nvme0n1', '/dev/sdz', '/dev/loop0', ''):
            result = self.run_disposable(f'disk="{path}"; disposable_identity')
            self.assertNotEqual(result.returncode, 0)
        for change in ({'serial': 'STX26012100037853'}, {'size': 1073741824}, {'type': 'part'}, {'ro': True}):
            disk = copy.deepcopy(TEST_DISK)
            disk['blockdevices'][0].update(change)
            self.assertNotEqual(self.run_disposable('disposable_identity', disk=disk).returncode, 0)
        # An arbitrary environment value is never an override in the ordinary path.
        result = self.run_gate('TEST_DEVICE=/dev/sdz; main desktop', plan=DESKTOP_PLAN)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('destructive desktop installation is not yet enabled', result.stderr)
        result = self.run_gate('main --test-disko vm /dev/sdz')
        self.assertNotEqual(result.returncode, 0)

    def test_live_root_ancestry_and_ambiguous_disk_are_refused(self):
        fault = r'''lsblk() { if [[ "$*" == *--inverse* ]]; then echo '{"blockdevices":[{"path":"/dev/sdz2","children":[{"path":"/dev/sdz"}]}]}'; else echo "$DISK"; fi; }
disposable_identity'''
        self.assertNotEqual(self.run_disposable(fault).returncode, 0)
        disk = {'blockdevices': TEST_DISK['blockdevices'] * 2}
        self.assertNotEqual(self.run_disposable('disposable_identity', disk=disk).returncode, 0)
        self.assertNotEqual(self.run_disposable('findmnt() { return 1; }; disposable_identity').returncode, 0)

    def test_live_root_partition_resolves_to_disk_and_target_relationships(self):
        self.assertEqual(self.run_disposable('disposable_identity').returncode, 0)
        for target in ('/dev/nvme0n1', '/dev/nvme0n1p1', '/dev/nvme0n1p2'):
            fault = f'''readlink() {{
  case "${{*: -1}}" in
    /dev/disk/by-id/usb-DISPOSABLE_TEST_ONLY) echo {target} ;;
    "$DESKTOP_DISK") echo /dev/nvme0n1 ;;
    /dev/*) printf '%s\\n' "${{*: -1}}" ;;
    *) command readlink "$@" ;;
  esac
}}
disposable_identity'''
            result = self.run_disposable(fault)
            self.assertNotEqual(result.returncode, 0)
        # A separate /dev/sda tree is outside the live NVMe ancestry.
        self.assertEqual(self.run_disposable('disposable_identity').returncode, 0)

    def test_live_root_discovery_failures_are_fatal(self):
        cases = [
            'findmnt() { return 1; }; disposable_identity',
            'findmnt() { echo /dev/nvme0n1p2; }; readlink() { return 1; }; disposable_identity',
            'findmnt() { echo /dev/nvme0n1p2; }; lsblk() { if [[ "$*" == *--inverse* ]]; then return 1; else echo "$DISK"; fi; }; disposable_identity',
            'findmnt() { echo /dev/nvme0n1p2; }; lsblk() { if [[ "$*" == *--inverse* ]]; then echo "{broken"; else echo "$DISK"; fi; }; disposable_identity',
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertNotEqual(self.run_disposable(case).returncode, 0)

    def test_ambiguous_or_non_block_live_root_is_refused(self):
        cases = [
            'findmnt() { echo overlay; }; disposable_identity',
            'findmnt() { echo /dev/nvme0n1p2; }; lsblk() { if [[ "$*" == *--inverse* ]]; then echo "{\\"blockdevices\\":[{\\"path\\":\\"/dev/nvme0n1p2\\",\\"type\\":\\"part\\"}]}"; else echo "$DISK"; fi; }; disposable_identity',
            'findmnt() { echo /dev/nvme0n1p2; }; lsblk() { if [[ "$*" == *--inverse* ]]; then echo "{\\"blockdevices\\":[{\\"path\\":\\"/dev/nvme0n1\\",\\"type\\":\\"disk\\"},{\\"path\\":\\"/dev/nvme1n1\\",\\"type\\":\\"disk\\"}]}"; else echo "$DISK"; fi; }; disposable_identity',
        ]
        for case in cases:
            with self.subTest(case=case):
                self.assertNotEqual(self.run_disposable(case).returncode, 0)

    def test_mounted_or_swap_target_is_refused_before_build(self):
        for mount in ('/', '/mnt/other', '[SWAP]'):
            disk = copy.deepcopy(TEST_DISK)
            disk['blockdevices'][0]['children'][0]['mountpoints'] = [mount]
            result = self.run_disposable('disposable_main --test-disko "$disk" "$repo"', disk=disk)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('EVENT:', result.stdout)
        result = self.run_disposable('disposable_main --test-disko "$disk" "$repo"', swaps='/dev/sdz2\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('EVENT:', result.stdout)

    def test_partition_table_validation(self):
        for fault in ('label', 'esp-size', 'esp-type', 'root-size', 'extra-partition'):
            table = copy.deepcopy(TEST_TABLE)
            p = table['partitiontable']
            if fault == 'label': p['label'] = 'dos'
            elif fault == 'esp-size': p['partitions'][0]['size'] = 1024
            elif fault == 'esp-type': p['partitions'][0]['type'] = 'swap'
            elif fault == 'root-size': p['partitions'][1]['size'] = 1024
            else: p['partitions'].append(p['partitions'][1])
            self.assertNotEqual(self.run_disposable('verify_disposable', table=table).returncode, 0)

    def test_bad_filesystems_mounts_subvolumes_or_files_fail_verification(self):
        for fault in (
            'blkid() { echo ext4; }',
            '''findmnt() { echo '{"filesystems":[{"maj:min":"259:2","fstype":"btrfs","fsroot":"/@root","options":"noatime,compress=zstd"}]}'; }''',
            '''findmnt() { echo '{"filesystems":[{"maj:min":"8:242","fstype":"btrfs","fsroot":"/@home","options":"relatime"}]}'; }''',
            'btrfs() { echo "ID 1 path @unexpected"; }',
            'find() { echo occupied; }',
            'sfdisk() { return 1; }',
        ):
            with self.subTest(fault=fault):
                self.assertNotEqual(self.run_disposable(fault + '\nverify_disposable').returncode, 0)

    def test_failed_disko_never_reports_verification_success(self):
        result = self.run_disposable('run_disko() { return 42; }; disposable_main --test-disko "$disk" "$repo"', answer=f'ERASE {TEST_DEVICE}\n')
        self.assertEqual(result.returncode, 42)
        self.assertNotIn('DISPOSABLE LAYOUT VERIFIED', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
