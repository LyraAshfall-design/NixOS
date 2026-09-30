#!/usr/bin/env bash
# Sourced only by setup's explicit disposable-test entry point. No standalone mode.

disposable_identity() {
  [[ "$disk" =~ ^/dev/disk/by-id/[A-Za-z0-9_.:+-]+$ ]] || die 'Disposable tests require an explicit whole-disk /dev/disk/by-id/... path.'
  [[ "$disk" != "$DESKTOP_DISK" ]] || die 'The production desktop SSD is NEVER a disposable target.'
  probe_disk
  [[ "$resolved" =~ ^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+)$ && "$resolved" != /dev/nvme0n1 ]] ||
    die 'Unsupported or production disk node; partitions, loop devices and device-mapper targets are refused.'
  local production root_source root_resolved ancestors live_disk live_tree
  if [[ -e "$DESKTOP_DISK" || -L "$DESKTOP_DISK" ]]; then
    production=$(readlink -e -- "$DESKTOP_DISK") || die 'Cannot resolve production SSD identity.'
    [[ "$resolved" != "$production" ]] || die 'Disposable alias resolves to the production SSD.'
  fi
  jq -e '.blockdevices[0] | .serial != "STX26012100037853" and .size >= 8589934592' \
    <<<"$disk_info" >/dev/null || die 'Production SSD serial or undersized disposable disk (minimum 8 GiB).'
  # Explicit live-root ancestry check, including dm/crypt parents. Refuse an
  # unresolvable root (e.g. overlay/live ISO) instead of guessing it is safe.
  # findmnt reports the actual partition source; /dev/block/<major>:<minor>
  # is not a portable pathname and was the cause of the previous false refusal.
  root_source=$(findmnt --noheadings --raw --mountpoint / --output SOURCE) || die 'Cannot identify live root.'
  [[ "$root_source" == /dev/* ]] || die 'Live root is not a plain block-device source; disposable test refused.'
  root_resolved=$(readlink -e -- "$root_source") || die 'Cannot resolve live root source.'
  is_block_device "$root_resolved" || die 'Live root source is not an identifiable block device; disposable test refused.'
  ancestors=$(lsblk --json --inverse --paths --output PATH,TYPE -- "$root_resolved") || die 'Cannot inspect live-root ancestry.'
  live_disk=$(jq -er '[.blockdevices[] | recurse(.children[]?) | select(.type == "disk") | .path] |
    unique | if length == 1 then .[0] else error("ambiguous live-root disk") end' <<<"$ancestors") ||
    die 'Live-root disk ancestry is missing or ambiguous.'
  live_tree=$(lsblk --json --tree --paths --output PATH,TYPE -- "$live_disk") || die 'Cannot inspect live-root disk tree.'
  jq -e --arg dev "$resolved" 'any(.blockdevices[] | recurse(.children[]?); .path == $dev) | not' <<<"$live_tree" >/dev/null ||
    die 'Disposable target is the live-root disk or one of its partitions.'
}

disposable_unused() {
  # Three Btrfs mountpoints intentionally share one partition. Reuse the existing
  # whole-disk busy/swap/holder/label-/mnt guards with one entry per partition.
  local plan
  plan=$(jq '.filesystems |= with_entries(select(.key == "/" or .key == "/boot"))' <<<"$test_plan")
  check_unused
}

evaluate_disposable() {
  local target=nixos-desktop production_plan
  evaluate_plan
  validate_desktop_plan
  production_plan=$plan
  local -a args=(--file "${snapshot#path:}/tests/disposable-disko.nix" --argstr snapshot "$snapshot" --argstr device "$resolved")
  read_plan "${args[@]}" config
  test_plan=$plan
  # Prove the override changed ONLY the target, not labels, partition sizes,
  # subvolumes, swap, options or mount destinations. Derivation hashes must differ.
  jq -e --arg dev "$resolved" --argjson original "$production_plan" '
    .disks[0].device == $dev and .disks[0].contentDevice == $dev and
    ((del(.systemDrv, .diskoDrv) | .disks[0].device = $original.disks[0].device |
      .disks[0].contentDevice = $original.disks[0].contentDevice) ==
      ($original | del(.systemDrv, .diskoDrv)))' <<<"$test_plan" >/dev/null ||
    die 'Disposable override changed more than the target disk.'
}

build_disposable() {
  script_output=$(nix_cmd build --no-link --print-out-paths \
    --file "${snapshot#path:}/tests/disposable-disko.nix" \
    --argstr snapshot "$snapshot" --argstr device "$resolved" script 9>&-)
  [[ "$script_output" == /nix/store/* && "$script_output" != *$'\n'* &&
    -x "$script_output/bin/disko-destroy-format-mount" ]] || die 'Unexpected disposable Disko output.'
}

verified_partition() {
  local label=$1 node=$2 inventory=$3 candidates candidate canonical parent metadata identity chosen='' chosen_id=''
  candidates=$(jq -er --arg label "$label" '
    [.blockdevices[] | recurse(.children[]?) | select(.partlabel == $label) | .path] |
    if length > 0 and all(.[]; type == "string" and startswith("/dev/"))
    then .[] else error("missing partition identity") end' <<<"$inventory") || die "Missing partition identity: $label"
  # Include the expected label alias and GPT node; all identities must agree.
  candidates+=$'\n'"/dev/disk/by-partlabel/$label"$'\n'"$node"
  while IFS= read -r candidate; do
    canonical=$(readlink -e -- "$candidate") || die "Cannot resolve partition identity: $candidate"
    is_block_device "$canonical" || die "Partition identity is not a block device: $candidate"
    metadata=$(lsblk --json --nodeps --paths --output PATH,TYPE,PKNAME,PARTLABEL,MAJ:MIN -- "$canonical") || die 'Cannot inspect partition identity.'
    jq -e --arg dev "$canonical" --arg label "$label" '
      (.blockdevices | length) == 1 and (.blockdevices[0] |
      .path == $dev and .type == "part" and .partlabel == $label and
      (.pkname | type == "string" and startswith("/dev/")) and
      (.["maj:min"] | type == "string" and test("^[0-9]+:[0-9]+$")))' <<<"$metadata" >/dev/null || die 'Invalid partition identity metadata.'
    parent=$(readlink -e -- "$(jq -er '.blockdevices[0].pkname' <<<"$metadata")") || die 'Cannot resolve partition parent.'
    [[ "$parent" == "$resolved" ]] || die 'Partition belongs to another disk.'
    identity=$(jq -er '.blockdevices[0]["maj:min"]' <<<"$metadata") || die 'Missing partition device number.'
    if [[ -n "$chosen" ]]; then
      [[ "$canonical" == "$chosen" && "$identity" == "$chosen_id" ]] || die 'Ambiguous partition identities.'
    else
      chosen=$canonical chosen_id=$identity
    fi
  done <<<"$candidates"
  printf '%s %s\n' "$chosen" "$chosen_id"
}

verify_disposable() {
  local table esp root size esp_id root_id mp info expected entries files
  size=$(jq -er '.blockdevices[0].size' <<<"$disk_info")
  table=$(sfdisk --json "$resolved") || die 'Cannot read disposable GPT.'
  jq -e --argjson size "$size" --arg dev "$resolved" '
    .partitiontable | . as $t | .partitions[0] as $e | .partitions[1] as $r |
    .label == "gpt" and .device == $dev and .unit == "sectors" and
    (.sectorsize == 512 or .sectorsize == 4096) and (.partitions | length) == 2 and
    ($e.type | ascii_downcase) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" and
    ($r.type | ascii_downcase) == "0fc63daf-8483-4772-8e79-3d69d8477de4" and
    ($e.size * $t.sectorsize) >= 1072693248 and ($e.size * $t.sectorsize) <= 1074790400 and
    $e.start > 0 and $r.start >= ($e.start + $e.size) and
    ($r.start - $e.start - $e.size) * $t.sectorsize <= 1048576 and
    ($r.start + $r.size) * $t.sectorsize <= $size and
    ($size - ($r.start + $r.size) * $t.sectorsize) < 16777216 and
    $r.size * $t.sectorsize >= ($size - 1074790400 - 16777216)
  ' <<<"$table" >/dev/null || die 'Disposable GPT/ESP/remainder validation failed.'
  esp=$(jq -er '.partitiontable.partitions[0].node' <<<"$table")
  root=$(jq -er '.partitiontable.partitions[1].node' <<<"$table")
  for mp in "$esp" "$root"; do
    jq -e --arg dev "$mp" 'any(.blockdevices[0].children[]?; .path == $dev and .type == "part")' \
      <<<"$disk_info" >/dev/null || die 'GPT partition does not belong to disposable disk.'
  done
  [[ "$(blkid -p -s TYPE -o value "$esp")" == vfat && "$(blkid -p -s TYPE -o value "$root")" == btrfs ]] ||
    die 'Disposable filesystem types are incorrect.'
  local inventory verified
  inventory=$(lsblk --json --list --paths --output PATH,PARTLABEL) || die 'Cannot enumerate partition identities.'
  verified=$(verified_partition disk-main-ESP "$esp" "$inventory") || die 'ESP identity verification failed.'
  read -r esp esp_id <<<"$verified"
  verified=$(verified_partition disk-main-root "$root" "$inventory") || die 'Root identity verification failed.'
  read -r root root_id <<<"$verified"
  [[ "$esp_id" =~ ^[0-9]+:[0-9]+$ && "$root_id" =~ ^[0-9]+:[0-9]+$ && "$esp_id" != "$root_id" ]] || die 'Ambiguous partition identities.'
  for mp in / /home /nix /boot; do
    info=$(findmnt --json --nofsroot --mountpoint "/mnt${mp%/}" --output SOURCE,MAJ:MIN,FSTYPE,FSROOT,OPTIONS) || die "Missing disposable mount: $mp"
    if [[ "$mp" == /boot ]]; then
      jq -e --arg id "$esp_id" '(.filesystems | length) == 1 and (.filesystems[0] |
        .["maj:min"] == $id and .fstype == "vfat" and .fsroot == "/" and
        (.options | split(",") | (index("umask=0077") != null or
          (index("fmask=0077") != null and index("dmask=0077") != null))))' <<<"$info" >/dev/null || die 'Incorrect disposable ESP mount/permissions.'
    else
      case "$mp" in /) expected=/@root ;; /home) expected=/@home ;; /nix) expected=/@nix ;; esac
      # Btrfs mount MAJ:MIN is an anonymous filesystem device (e.g. 0:97),
      # not the backing partition's device number. --nofsroot exposes only
      # the source device; FSROOT independently verifies the subvolume below.
      local source source_device
      source=$(jq -er 'if (.filesystems | length) == 1 then
        .filesystems[0].source | select(type == "string" and startswith("/dev/"))
        else error("ambiguous mount source") end' <<<"$info") || die "Missing Btrfs backing device: $mp"
      source_device=$(readlink -e -- "$source") || die "Cannot resolve Btrfs backing device: $mp"
      is_block_device "$source_device" && [[ "$source_device" == "$root" ]] || die "Incorrect Btrfs backing device: $mp"
      jq -e --arg subvol "$expected" '(.filesystems | length) == 1 and (.filesystems[0] |
        .fstype == "btrfs" and .fsroot == $subvol and
        (.options | split(",") | index("noatime") != null and any(.[]; test("^compress=zstd(:[0-9]+)?$"))))' \
        <<<"$info" >/dev/null || die "Incorrect disposable Btrfs mount: $mp"
    fi
  done
  entries=$(btrfs subvolume list /mnt) || die 'Cannot list disposable subvolumes.'
  [[ "$(sed -n 's/^.* path //p' <<<"$entries" | LC_ALL=C sort)" == $'@home\n@nix\n@root' ]] || die 'Unexpected or missing Btrfs subvolumes.'
  # A fresh Disko-only layout has no regular files: this also detects swapfiles
  # under any of the three subvolumes (which -xdev visits separately).
  for mp in /mnt /mnt/home /mnt/nix /mnt/boot; do
    files=$(find "$mp" -xdev -type f -printf occupied -quit) || die 'Cannot inspect disposable files.'
    [[ -z "$files" ]] || die 'Unexpected file (possibly swap) in fresh disposable layout.'
  done
  printf 'DISPOSABLE LAYOUT VERIFIED: GPT, 1 GiB ESP, Btrfs remainder, @root/@home/@nix, mount options, no swap/files.\n'
}

# Dynamic scope supplies repo/target/friendly to setup helpers and phase to its ERR trap.
# shellcheck disable=SC2034
disposable_main() {
  local mode=$1 disk=$2 repo=$3 target=disposable friendly=desktop-disposable phase='disposable preflight'
  local resolved disk_info fingerprint snapshot plan test_plan script_output expected command
  require_root
  [[ "$mode" == --verify-disko ]] || require_terminal
  for command in nix jq lsblk findmnt swapon readlink find flock sfdisk blkid btrfs sed sort; do
    command -v "$command" >/dev/null || die "Missing disposable-test tool: $command"
  done
  disposable_identity
  expected=$fingerprint
  evaluate_disposable
  if [[ "$mode" == --verify-disko ]]; then
    phase='read-only disposable verification'
    verify_disposable
    return
  fi
  disposable_unused
  show_disk
  lock_installation
  phase='building the pinned disposable Disko helper'
  build_disposable
  disposable_identity
  [[ "$fingerprint" == "$expected" ]] || die 'Disposable identity changed during preflight.'
  disposable_unused
  confirm_erase
  disposable_identity
  [[ "$fingerprint" == "$expected" ]] || die 'Disposable identity changed after confirmation.'
  disposable_unused
  phase='formatting only the confirmed disposable disk'
  run_disko
  disposable_identity
  [[ "$fingerprint" == "$expected" ]] || die 'Disposable identity changed during Disko.'
  phase='verifying the disposable layout'
  verify_disposable
  printf 'No NixOS installation or password changes performed. Test mounts remain under /mnt.\nUse --verify-disko to inspect again without formatting; inspect before manually unmounting.\n'
}
