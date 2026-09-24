"""One-way Camera archive. Android operations are explicitly read-only below."""
import ctypes
import datetime
import fcntl
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import signal
import stat
import subprocess
import sys

SOURCE = "/sdcard/DCIM/Camera"
# Each record is ASCII metadata, newline, then a NUL-terminated filename.
# Filenames are passed as positional arguments, never evaluated as shell code.
LIST_COMMAND = (
    "find " + SOURCE + " -type f -exec sh -c " + shlex.quote(
        'for p do stat -c "%s %Y" "$p" || exit 1; printf "%s\\000" "$p"; done'
    ) + " sh {} +"
)
LOG = logging.getLogger("phone-photo-import")


def run(args, timeout=30):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=timeout, check=False)
    if result.stderr:
        LOG.info("%r: %s", args, os.fsdecode(result.stderr[-4096:]))
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {args!r}; "
                           f"{os.fsdecode(result.stderr[-1024:])}")
    return result.stdout


def remote_shell(device, command, timeout=30):
    return run(["adb", "-s", device, "shell", "-T", command], timeout)


def remote_stat(device, path):
    # shlex.quote protects even embedded newlines, apostrophes and shell syntax.
    raw = remote_shell(device, "stat -c '%s %Y' " + shlex.quote(path))
    size, mtime = map(int, raw.split())
    return size, mtime


def listing(device):
    data = remote_shell(device, LIST_COMMAND, 300)
    if data and not data.endswith(b"\0"):
        raise ValueError("Incomplete remote listing")
    result = []
    for record in data.split(b"\0")[:-1]:
        metadata, path = record.split(b"\n", 1)
        size, mtime = map(int, metadata.split())
        path = os.fsdecode(path)
        relative = PurePosixPath(path).relative_to(SOURCE)
        if not relative.parts or ".." in relative.parts or size < 0:
            raise ValueError("Invalid remote path or size")
        result.append((path, size, mtime))
    return result


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_jsonl(path, records):
    temporary = path.with_name(path.name + ".tmp")
    # Only our own fixed staging file is replaced; never the archive contents.
    with temporary.open("w", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record, ensure_ascii=True, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    fsync_dir(path.parent)


def identity(device_id, path, size, mtime):
    raw = json.dumps([device_id, path, size, mtime], ensure_ascii=True).encode()
    return hashlib.sha256(raw).hexdigest()


def validate_record(record):
    if not isinstance(record, dict):
        raise ValueError("expected a JSON object")
    for field in ("schema_version", "remote_size", "remote_mtime", "local_size"):
        if type(record.get(field)) is not int:
            raise ValueError(f"{field}: expected an integer")
    if record["schema_version"] != 1:
        raise ValueError("schema_version: unsupported version")
    for field in ("id", "device_id", "remote_path", "filename", "local_path", "sha256", "imported_at"):
        value = record.get(field)
        if not isinstance(value, str) or not value or "\0" in value:
            raise ValueError(f"{field}: expected a nonempty string without NUL")
    for field in ("id", "sha256"):
        if not re.fullmatch(r"[0-9a-f]{64}", record[field]):
            raise ValueError(f"{field}: expected a SHA-256 hex digest")
    if record["remote_size"] < 0 or record["local_size"] != record["remote_size"]:
        raise ValueError("local_size/remote_size: expected equal nonnegative sizes")
    remote = PurePosixPath(record["remote_path"])
    try:
        relative = remote.relative_to(SOURCE)
    except ValueError as exc:
        raise ValueError("remote_path: outside the Camera directory") from exc
    if not relative.parts or ".." in relative.parts or record["filename"] != remote.name:
        raise ValueError("remote_path/filename: invalid Camera file path")
    if not Path(record["local_path"]).is_absolute():
        raise ValueError("local_path: expected an absolute path")
    try:
        timestamp = datetime.datetime.fromisoformat(record["imported_at"])
    except ValueError as exc:
        raise ValueError("imported_at: expected an ISO 8601 timestamp") from exc
    if timestamp.utcoffset() is None:
        raise ValueError("imported_at: expected a timezone")
    if record["id"] != identity(record["device_id"], record["remote_path"],
                                record["remote_size"], record["remote_mtime"]):
        raise ValueError("id: does not match the recorded remote identity")
    return record


def read_records(path):
    records = []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try:
            records.append(validate_record(json.loads(line)))
        except ValueError as exc:
            raise ValueError(f"Invalid archive record in {path}:{number}: {exc}") from exc
    return records


def parse_checksum(output):
    fields = output.split()
    if len(fields) != 2 or fields[1] != b"-" or not re.fullmatch(rb"[0-9a-f]{64}", fields[0]):
        raise ValueError("Invalid SHA-256 response from phone; expected a digest for stdin")
    return fields[0].decode("ascii")


def rename_no_replace(source, destination):
    # Linux atomic rename with no overwrite, including symlinks and concurrent
    # non-importer writers. Both paths are on the archive filesystem.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renameat2(-100, os.fsencode(source), -100, os.fsencode(destination), 1):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


class Archive:
    def __init__(self, state, destination):
        self.state = state
        self.destination = destination
        self.manifest = state / "manifest.jsonl"
        self.pending = state / "pending.jsonl"
        self.staging = destination / ".phone-photo-import"
        self.staging.mkdir(mode=0o700, exist_ok=True)
        if self.staging.is_symlink():
            raise ValueError("Refusing symlink staging directory")
        self.partial = self.staging / "transfer.part"
        self.records = []
        if self.manifest.exists():
            # Fail closed on corrupt state; never silently forget past imports.
            self.records = read_records(self.manifest)
        self.known = {r["id"] for r in self.records}

    def commit(self, record):
        atomic_jsonl(self.manifest, self.records + [record])
        self.records.append(record)
        self.known.add(record["id"])

    def recover(self):
        if self.pending.exists():
            records = read_records(self.pending)
            if len(records) != 1:
                raise ValueError(f"Invalid recovery state in {self.pending}: expected one record")
            record = records[0]
            final = Path(record["local_path"])
            if final.parent != self.destination:
                raise ValueError("Invalid pending archive path")
            if record["id"] not in self.known and not self.partial.exists():
                # A missing staging file indicates the atomic rename completed.
                # Do not invent success if the final file is missing or changed.
                if (final.is_symlink() or not final.is_file()
                        or final.stat().st_size != record["local_size"]
                        or digest(final) != record["sha256"]):
                    raise ValueError("Pending archive copy missing/changed; manual review required")
                self.commit(record)
            self.pending.unlink()
            fsync_dir(self.state)
        # No recursive deletion, globbing, or cleanup of users' photos.
        self.partial.unlink(missing_ok=True)
        for name in ("manifest.jsonl.tmp", "pending.jsonl.tmp"):
            (self.state / name).unlink(missing_ok=True)

    def target(self, filename, key):
        reserved = {r["local_path"] for r in self.records}
        candidate = self.destination / filename
        if not os.path.lexists(candidate) and str(candidate) not in reserved:
            return candidate
        # Full stable identity suffix; fallback also handles long basenames.
        suffix = Path(filename).suffix
        if len(os.fsencode(suffix)) > 20:
            suffix = ""
        candidate = self.destination / ("photo-" + key + suffix)
        if os.path.lexists(candidate) or str(candidate) in reserved:
            raise FileExistsError(f"Archive collision requires review: {candidate}")
        return candidate

    def import_file(self, device, device_id, path, size, mtime):
        key = identity(device_id, path, size, mtime)
        filename = PurePosixPath(path).name
        final = self.target(filename, key)
        try:
            run(["adb", "-s", device, "pull", path, str(self.partial)], timeout=600)
            info = self.partial.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_size != size:
                raise ValueError("Incomplete/non-regular pulled file")
            local_hash = digest(self.partial)
            # Verify source content as well as size/mtime, only for new files.
            remote_hash = parse_checksum(remote_shell(
                device, "sha256sum < " + shlex.quote(path), 600
            ))
            if remote_hash != local_hash or remote_stat(device, path) != (size, mtime):
                raise ValueError("Source changed or checksum mismatch; will retry next run")
            os.utime(self.partial, (mtime, mtime))
            with self.partial.open("rb") as stream:
                os.fsync(stream.fileno())
            record = dict(schema_version=1, id=key, device_id=device_id,
                          remote_path=path, filename=filename, remote_size=size,
                          remote_mtime=mtime, local_path=str(final), local_size=size,
                          sha256=local_hash,
                          imported_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
            atomic_jsonl(self.pending, [record])
            rename_no_replace(self.partial, final)
            fsync_dir(self.staging)
            fsync_dir(self.destination)
            self.commit(record)
            self.pending.unlink()
            fsync_dir(self.state)
        finally:
            # Keep a prepared transaction intact for recovery if commit failed.
            if not self.pending.exists():
                self.partial.unlink(missing_ok=True)


def interrupted(signum, _frame):
    raise InterruptedError(f"Interrupted by signal {signum}")


def main():
    os.umask(0o077)
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "phone-photo-import"
    state.mkdir(parents=True, exist_ok=True)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Phone photo import already running; skipped.")
            return 0
        handler = RotatingFileHandler(state / "import.log", maxBytes=2_000_000, backupCount=2)
        LOG.addHandler(handler)
        LOG.setLevel(logging.INFO)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, interrupted)
        try:
            # An unavailable phone is an ordinary timer skip, not a notification.
            try:
                device = run(["phone-adb-connect"], timeout=120).decode().strip()
            except (RuntimeError, subprocess.TimeoutExpired) as exc:
                LOG.info("Phone unavailable: %s", exc)
                print("Phone unavailable; skipped. See " + str(state / "import.log"))
                return 0
            device_id = remote_shell(device, "getprop ro.serialno").decode().strip()
            if not device_id:
                raise ValueError("Phone did not provide a stable device identity")
            files = listing(device)
            destination = Path.home() / "Pictures/Phone/Camera"
            destination.mkdir(parents=True, exist_ok=True)
            destination = destination.resolve()
            archive = Archive(state, destination)
            archive.recover()
            counts = dict(scanned=len(files), previously_imported=0, new=0, imported=0, failed=0)
            for path, size, mtime in files:
                if identity(device_id, path, size, mtime) in archive.known:
                    counts["previously_imported"] += 1
                    continue
                counts["new"] += 1
                try:
                    archive.import_file(device, device_id, path, size, mtime)
                    counts["imported"] += 1
                except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
                    counts["failed"] += 1
                    LOG.exception("Failed %r", path)
                    if counts["failed"] <= 10:
                        print(f"Failed {path!r}: {exc}", file=sys.stderr)
                    elif counts["failed"] == 11:
                        print("Further failures are in import.log.", file=sys.stderr)
                    if archive.pending.exists() or isinstance(exc, (InterruptedError, subprocess.TimeoutExpired)):
                        # Never start another transaction over an unresolved one.
                        # A stalled connection can wait for the next timer run.
                        break
            print("; ".join(f"{k.replace('_', ' ')}: {v}" for k, v in counts.items()))
            LOG.info("Summary: %s", counts)
            return 1 if counts["failed"] else 0
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
            LOG.exception("Import aborted")
            print(f"Import aborted: {exc}. See {state / 'import.log'}", file=sys.stderr)
            return 1
        finally:
            LOG.removeHandler(handler)
            handler.close()


if __name__ == "__main__":
    sys.exit(main())
