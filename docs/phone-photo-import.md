# Phone Camera archive

`phone-photo-import` archives regular files recursively from
`/sdcard/DCIM/Camera/` into `~/Pictures/Phone/Camera/`. This includes videos and
other regular Camera files. It never sends local changes to Android.

Home Manager installs the command and a user service/timer. The timer runs on
each hour and half hour, and catches up after the next user-manager startup.
It does not enable user lingering. An unavailable phone is a successful skip;
there are no importer desktop notifications. Run the command manually for a
summary, or inspect `journalctl --user -u phone-photo-import.service`.

`phone-control` and the importer use the same packaged `phone-adb-connect`
helper, retaining wireless ADB/Avahi discovery without fixed addresses or
ports. The helper reuses a connected wireless device and rejects ambiguous
multiple connections. Only connect the intended phone; it does not filter by
Samsung model. A read-only device serial query separates importer identities
across phones. Super+P continues to launch scrcpy through `phone-control`.

## State and incremental behavior

State is in `$XDG_STATE_HOME/phone-photo-import`, defaulting to
`~/.local/state/phone-photo-import`:

- `manifest.jsonl`: one JSON object per successfully archived file version.
- `lock`: persistent advisory lock shared by manual and timer runs.
- `pending.jsonl`: recovery record for one prepared archive transaction.
- `import.log`: diagnostics, rotated at approximately 2 MB, with two backups.

Manifest records contain `schema_version`, `id`, `device_id`, `remote_path`,
`filename`, `remote_size`, `remote_mtime` (Unix seconds), `local_path`,
`local_size`, `sha256`, and `imported_at` (UTC ISO 8601). JSON escaping preserves
newlines and unusual filename bytes while keeping one record per line.

The stable ID hashes the device serial, full Android path, size and mtime.
Each run lists metadata; only unseen identities are pulled. Completed records
are not removed or revalidated against local presence. Thus deleting a local
copy does not cause it to be downloaded again. Deleting a phone copy never
removes a local copy or its record. Changed remote metadata creates a new
version. A remote modification that preserves both size and second-resolution
mtime cannot be detected for a previously imported identity. Keep the manifest
alongside your archive backups: losing it loses the import/deletion history.

## Transfer, collision and recovery safety

A new file is pulled into the archive's reserved `.phone-photo-import/transfer.part`.
The importer checks that it is a regular file, validates its size, compares
its local SHA-256 against Android's read-only `sha256sum`, and rechecks remote
size/mtime. It preserves the remote mtime locally and flushes the file to disk.

The final basename is used if neither an existing file nor a historical
manifest record claims it. Otherwise `photo-<full stable ID><extension>` is
used. An occupied fallback causes a reported failure, never an overwrite.
Linux `renameat2(RENAME_NOREPLACE)` atomically installs the completed copy,
including protection against an unrelated writer racing to create that name.

Before placement, an atomically written recovery record describes the
validated copy. After placement and directory flushes, the entire JSONL
manifest is replaced atomically and flushed. Only then is the import complete.
This favors a simple, recoverable format over an append-only partial-line
repair scheme; manifest rewrite cost grows with archive history.

A later connected run recovers an interrupted transaction: if placement
completed, it verifies the final hash/size before recording success, without
pulling again. If placement did not complete, it discards the staging file and
retries. A missing or changed final copy during recovery stops for manual
review. Malformed manifest data also stops rather than forgetting history.
Cleanup is limited to the importer's fixed staging/state temporary files;
it never recursively removes directories or deletes archived photos.
SIGINT/SIGTERM and ordinary failed transfers clean their partial data;
a hard kill may leave staging data for the next connected run to clean.

## Android read-only audit

The only Android operations are:

- `adb devices` and `adb connect` through the shared discovery helper; Avahi
  browses the connection service, not the pairing service.
- `adb -s DEVICE shell -T ...` for `getprop ro.serialno`, a fixed `find`/`sh`
  listing loop using `stat` and `printf`, per-file `stat`, and `sha256sum` with
  input-only redirection.
- `adb -s DEVICE pull REMOTE LOCAL_TEMP`.

No Android write, push, remove, move, copy, mkdir or sync commands exist.
The static listing loop receives filenames as positional arguments and quotes
all expansions. Per-file shell paths use Python `shlex.quote`; pull uses an
argument list with no local shell. Listings use NUL-delimited paths, not `ls`.
Spaces, quotes, parentheses, Unicode, newlines and shell metacharacters are
covered by tests. Android/Linux filenames cannot contain NUL or `/` within a
single component. The implementation requires Android's usual `find -exec ...
+`, `stat -c`, `sha256sum`, and non-PTY ADB shell support. Missing support fails
closed; there is no fallback to an unsafe parser.

## Validation

Run `PYTHONDONTWRITEBYTECODE=1 python3 tests/phone-photo-import.py` for offline
mocked importer and launcher regression tests. No test contacts a phone.
Use `nix flake check --no-build` from the repository for configuration
evaluation. No activation is needed for these checks.
