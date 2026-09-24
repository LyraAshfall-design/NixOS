#!/usr/bin/env python3
"""Offline importer/discovery tests. No commands contact Android or user data."""
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "modules/home/phone"
spec = importlib.util.spec_from_file_location("importer", SCRIPTS / "phone-photo-import.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.state = self.home / "state/phone-photo-import"
        self.dest = self.home / "Pictures/Phone/Camera"
        self.files = {}
        self.calls = []
        self.offline = False
        self.pull_failure = None
        self.bad_hash = False
        self.checksum_output = None
        self.changed = False
        self.env = patch.dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home / "state"))
        self.env.start()
        self.addCleanup(self.env.stop)
        self.runner = patch.object(m, "run", side_effect=self.command)
        self.runner.start()
        self.addCleanup(self.runner.stop)

    def add(self, name="photo.jpg", content=b"camera bytes", mtime=1780000000):
        path = m.SOURCE + "/" + name
        self.files[path] = (content, mtime)
        return path

    def command(self, args, timeout=30):
        self.calls.append(args)
        if args == ["phone-adb-connect"]:
            if self.offline:
                raise RuntimeError("offline")
            return b"192.0.2.1:12345\n"
        self.assertEqual(args[:3], ["adb", "-s", "192.0.2.1:12345"])
        if args[3] == "pull":
            data, _ = self.files[args[4]]
            Path(args[5]).write_bytes(data if not self.pull_failure else data[:2])
            if self.pull_failure == "timeout":
                raise subprocess.TimeoutExpired(args, timeout)
            if self.pull_failure == "exit":
                raise RuntimeError("pull interrupted")
            if self.pull_failure == "signal":
                raise InterruptedError("SIGTERM")
            return b""
        self.assertEqual(args[3:5], ["shell", "-T"])
        cmd = args[5]
        if cmd == "getprop ro.serialno":
            return b"TEST-S23\n"
        if cmd == m.LIST_COMMAND:
            return b"".join(f"{len(data)} {mtime}\n".encode() + os.fsencode(path) + b"\0"
                            for path, (data, mtime) in self.files.items())
        tokens = shlex.split(cmd)
        if tokens[:3] == ["stat", "-c", "%s %Y"]:
            self.assertEqual(len(tokens), 4)
            data, mtime = self.files[tokens[3]]
            return f"{len(data)} {mtime + int(self.changed)}\n".encode()
        self.assertEqual(tokens[:2], ["sha256sum", "<"])
        self.assertEqual(len(tokens), 3)
        data, _ = self.files[tokens[2]]
        if self.checksum_output is not None:
            return self.checksum_output
        return (hashlib.sha256(data if not self.bad_hash else b"wrong").hexdigest() + "  -\n").encode()

    def execute(self, status=0):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(m.main(), status, output.getvalue())
        return output.getvalue()

    def records(self):
        p = self.state / "manifest.jsonl"
        return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []

    def pulls(self):
        return [args for args in self.calls if len(args) > 3 and args[3] == "pull"]

    def test_first_noop_and_new(self):
        path = self.add()
        self.execute()
        record, = self.records()
        self.assertEqual(record["remote_path"], path)
        self.assertEqual(record["device_id"], "TEST-S23")
        self.assertEqual(record["remote_mtime"], self.files[path][1])
        self.assertEqual(record["sha256"], hashlib.sha256(self.files[path][0]).hexdigest())
        self.assertEqual(record["local_size"], record["remote_size"])
        self.assertEqual(Path(record["local_path"]).read_bytes(), self.files[path][0])
        original = (self.state / "manifest.jsonl").read_bytes()
        self.assertIn("previously imported: 1", self.execute())
        self.assertEqual(len(self.pulls()), 1)
        self.assertEqual(original, (self.state / "manifest.jsonl").read_bytes())
        self.add("new.jpg", b"new")
        self.execute()
        self.assertEqual(len(self.pulls()), 2)
        self.assertEqual(self.records()[0], record)

    def test_offline(self):
        self.add()
        self.execute()
        before = (self.state / "manifest.jsonl").read_bytes()
        self.offline = True
        self.assertIn("skipped", self.execute())
        self.assertEqual(before, (self.state / "manifest.jsonl").read_bytes())
        self.assertEqual((self.dest / "photo.jpg").read_bytes(), b"camera bytes")

    def test_failed_and_interrupted_pull(self):
        self.add()
        for failure in ("exit", "timeout", "short", "signal"):
            with self.subTest(failure=failure):
                self.pull_failure = failure
                self.execute(status=1)
                self.assertEqual(self.records(), [])
                self.assertFalse((self.dest / "photo.jpg").exists())
                self.assertFalse((self.dest / ".phone-photo-import/transfer.part").exists())

    def test_checksum_and_changing_source(self):
        self.add()
        self.bad_hash = True
        self.execute(status=1)
        self.bad_hash = False
        self.changed = True
        self.execute(status=1)
        self.assertEqual(self.records(), [])

    def test_local_deletion_is_not_resurrected(self):
        path = self.add()
        self.execute()
        before = self.records()
        (self.dest / "photo.jpg").unlink()
        self.execute()
        self.assertFalse((self.dest / "photo.jpg").exists())
        self.assertEqual(len(self.pulls()), 1)
        self.assertIn(path, self.files)
        self.assertEqual(before, self.records())

    def test_remote_deletion_is_not_propagated(self):
        self.add()
        self.execute()
        before = self.records()
        self.files.clear()
        self.execute()
        self.assertTrue((self.dest / "photo.jpg").exists())
        self.assertEqual(before, self.records())

    def test_filename_safety(self):
        names = ["a b (1).jpg", "日本語-é.jpg", "x'; $(touch INJECTED); `id`.jpg", "line\nbreak\t.jpg", "-option.jpg"]
        for name in names:
            self.add(name)
        self.execute()
        self.assertEqual(len(self.records()), len(names))
        self.assertEqual({p.name for p in self.dest.iterdir() if p.is_file()}, set(names))
        # Execute the real static listing shell against local fixture files.
        # This tests framing and quoting, independent of the mock's output.
        command = m.LIST_COMMAND.replace(m.SOURCE, shlex.quote(str(self.dest)))
        result = subprocess.run(["sh", "-c", command], capture_output=True, check=True)
        records = result.stdout.split(b"\0")[:-1]
        self.assertEqual({os.fsdecode(x.split(b"\n", 1)[1]) for x in records},
                         {str(self.dest / n) for n in names})
        self.assertFalse((self.home / "INJECTED").exists())

    def test_collisions_and_changed_metadata(self):
        self.add("one/same.jpg", b"one")
        self.add("two/same.jpg", b"two")
        self.dest.mkdir(parents=True)
        (self.dest / "same.jpg").write_bytes(b"pre-existing")
        self.execute()
        records = self.records()
        self.assertEqual(len({r["local_path"] for r in records}), 2)
        self.assertEqual((self.dest / "same.jpg").read_bytes(), b"pre-existing")
        self.add("one/same.jpg", b"replacement", 1780000001)
        self.execute()
        self.assertEqual(len(self.records()), 3)
        self.assertTrue(all(Path(r["local_path"]).exists() for r in records))

    def test_manifest_write_failure_recovers_without_repull(self):
        self.add()
        original = m.atomic_jsonl
        def fail_manifest(path, records):
            if path.name == "manifest.jsonl":
                path.with_name(path.name + ".tmp").write_text('{"interrupted":')
                raise OSError("simulated crash before manifest replacement")
            original(path, records)
        with patch.object(m, "atomic_jsonl", side_effect=fail_manifest):
            self.execute(status=1)
        self.assertEqual(self.records(), [])
        self.assertTrue((self.dest / "photo.jpg").exists())
        self.assertTrue((self.state / "pending.jsonl").exists())
        self.execute()
        self.assertEqual(len(self.records()), 1)
        self.assertEqual(len(self.pulls()), 1)
        self.assertFalse((self.state / "pending.jsonl").exists())
        self.assertFalse((self.state / "manifest.jsonl.tmp").exists())

    def test_interrupted_before_rename_and_stale_partial(self):
        self.add()
        with patch.object(m, "rename_no_replace", side_effect=OSError("crash before rename")):
            self.execute(status=1)
        self.assertEqual(self.records(), [])
        self.execute()
        self.assertEqual(len(self.records()), 1)
        (self.dest / ".phone-photo-import/transfer.part").write_bytes(b"stale")
        unrelated = self.dest / ".phone-photo-import/keep-me"
        unrelated.write_bytes(b"user file")
        self.execute()
        self.assertFalse((unrelated.parent / "transfer.part").exists())
        self.assertTrue(unrelated.exists())

    def test_interrupted_after_manifest_replacement(self):
        self.add()
        original = m.atomic_jsonl
        def interrupt_after_commit(path, records):
            original(path, records)
            if path.name == "manifest.jsonl":
                raise InterruptedError("after atomic replacement")
        with patch.object(m, "atomic_jsonl", side_effect=interrupt_after_commit):
            self.execute(status=1)
        self.assertEqual(len(self.records()), 1)
        # An intentional deletion after the committed manifest stays deleted.
        (self.dest / "photo.jpg").unlink()
        self.execute()
        self.assertEqual(len(self.pulls()), 1)
        self.assertFalse((self.dest / "photo.jpg").exists())

    def test_missing_pending_copy_fails_closed(self):
        self.add()
        with patch.object(m.Archive, "commit", side_effect=OSError("manifest failed")):
            self.execute(status=1)
        (self.dest / "photo.jpg").unlink()
        self.execute(status=1)
        self.assertEqual(self.records(), [])
        self.assertEqual(len(self.pulls()), 1)
        self.assertTrue((self.state / "pending.jsonl").exists())

    def test_deleted_historical_path_is_reserved_for_a_new_version(self):
        self.add()
        self.execute()
        (self.dest / "photo.jpg").unlink()
        self.add(content=b"new version", mtime=1780000001)
        self.execute()
        old, new = self.records()
        self.assertNotEqual(old["local_path"], new["local_path"])
        self.assertFalse(Path(old["local_path"]).exists())
        self.assertTrue(Path(new["local_path"]).exists())

    def test_atomic_rename_refuses_overwrite(self):
        src, dst = self.home / "src", self.home / "dst"
        src.write_bytes(b"new")
        dst.write_bytes(b"old")
        with self.assertRaises(FileExistsError):
            m.rename_no_replace(src, dst)
        self.assertEqual(dst.read_bytes(), b"old")
        self.assertTrue(src.exists())

    def test_corrupt_manifest_fails_closed(self):
        self.add()
        self.execute()
        (self.state / "manifest.jsonl").write_text('{"partial":')
        self.execute(status=1)
        self.assertEqual(len(self.pulls()), 1)

    def test_invalid_checksum_output_fails_without_installing(self):
        self.add()
        for output in (b"", b"\n", b"not-a-digest  -\n", b"f" * 63 + b"  -\n",
                       b"\xff" * 64 + b"  -\n", b"a" * 64,
                       b"a" * 64 + b"  -\nextra output"):
            with self.subTest(output=output):
                self.checksum_output = output
                self.assertIn("Invalid SHA-256 response", self.execute(status=1))
                self.assertEqual(self.records(), [])
                self.assertFalse((self.dest / "photo.jpg").exists())
                self.assertFalse((self.dest / ".phone-photo-import/transfer.part").exists())

    def test_malformed_json_records_fail_closed_with_location(self):
        self.add()
        self.execute()
        valid, = self.records()
        invalid = [None, [], 123, "record", {}, {"id": valid["id"]}]
        for field in valid:
            record = valid.copy()
            del record[field]
            invalid.append(record)
        for field, value in (
            ("schema_version", 2), ("schema_version", True), ("remote_size", -1),
            ("local_size", "12"), ("remote_mtime", 1.5), ("sha256", "bad"),
            ("device_id", []), ("id", "0" * 64), ("local_path", "relative.jpg"),
            ("filename", "wrong.jpg"), ("remote_path", "/sdcard/other.jpg"),
            ("remote_path", m.SOURCE + "/../other.jpg"), ("filename", "bad\0name"),
            ("imported_at", "yesterday"), ("imported_at", "2026-09-23T12:00:00"),
        ):
            invalid.append(dict(valid, **{field: value}))
        manifest = self.state / "manifest.jsonl"
        for record in invalid:
            with self.subTest(record=record):
                contents = json.dumps(record) + "\n"
                manifest.write_text(contents)
                output = self.execute(status=1)
                self.assertIn("Invalid archive record", output)
                self.assertIn("manifest.jsonl:1", output)
                self.assertEqual(manifest.read_text(), contents)
                self.assertEqual(len(self.pulls()), 1)
                self.assertEqual((self.dest / "photo.jpg").read_bytes(), b"camera bytes")

    def test_invalid_pending_record_is_preserved_for_review(self):
        self.add()
        self.execute()
        pending = self.state / "pending.jsonl"
        pending.write_text('{"id": "incomplete"}\n')
        self.assertIn("pending.jsonl:1", self.execute(status=1))
        self.assertTrue(pending.exists())
        self.assertEqual(len(self.records()), 1)
        self.assertEqual(len(self.pulls()), 1)

    def test_concurrent_process_is_excluded(self):
        self.state.mkdir(parents=True)
        # A separate process holds the exact production lock while main runs.
        code = "import fcntl,sys; f=open(sys.argv[1],'a'); fcntl.flock(f,fcntl.LOCK_EX); print('ready',flush=True); sys.stdin.read()"
        child = subprocess.Popen(["python3", "-c", code, str(self.state / "lock")], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        try:
            self.assertEqual(child.stdout.readline(), b"ready\n")
            self.assertIn("already running", self.execute())
            self.assertEqual(self.calls, [])
            self.assertEqual(self.records(), [])
        finally:
            child.communicate(timeout=5)


MOCK = r'''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ['FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
case = os.environ['CASE']
with (root/'calls').open('a') as f: f.write(name+' '+ ' '.join(sys.argv[1:])+'\n')
if name == 'adb':
    if sys.argv[1] == 'devices':
        if case == 'adb-fail': sys.exit(1)
        print('List of devices attached\nUSB123 device\nemulator-5554 device\n192.0.2.1:1234 offline')
        if case in ('connected','scrcpy-fail') or (root/'connected').exists(): print('192.0.2.2:45678 device')
        if case == 'mdns-serial': print('adb-test._adb-tls-connect._tcp device')
        if case == 'multiple': print('192.0.2.2:45678 device\n192.0.2.3:45679 device')
    elif sys.argv[1] == 'connect':
        if case == 'discover': (root/'connected').touch()
        else: print('failed to connect')
    else: sys.exit(99)
elif name == 'avahi-browse':
    print('=;wlan0;IPv4;pair;_adb-tls-pairing._tcp;local;phone.local;192.0.2.2;9999;')
    if case in ('discover','connect-fail'): print('=;wlan0;IPv4;phone;_adb-tls-connect._tcp;local;phone.local;192.0.2.2;45678;')
elif name == 'scrcpy' and case == 'scrcpy-fail': sys.exit(1)
'''


class DiscoveryTests(unittest.TestCase):
    def test_phone_control_regression(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ('adb', 'avahi-browse', 'scrcpy', 'notify-send'):
                p = root / name
                p.write_text(MOCK)
                p.chmod(0o755)
            for name in ('phone-adb-connect', 'phone-control'):
                p = root / name
                p.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + (SCRIPTS / (name + '.sh')).read_text())
                p.chmod(0o755)
            for case in ('connected','mdns-serial','discover','missing','connect-fail','multiple','adb-fail','scrcpy-fail'):
                with self.subTest(case=case):
                    for name in ('calls','connected'):
                        (root/name).unlink(missing_ok=True)
                    env = dict(os.environ, PATH=tmp+':'+os.environ['PATH'], FIXTURE=tmp, XDG_RUNTIME_DIR=tmp, CASE=case)
                    result = subprocess.run([str(root/'phone-control')], env=env, capture_output=True)
                    calls = (root/'calls').read_text()
                    success = case in ('connected','mdns-serial','discover')
                    self.assertEqual(result.returncode, 0 if success else 1)
                    self.assertEqual('scrcpy --serial=' in calls, success or case == 'scrcpy-fail')
                    self.assertEqual('notify-send' in calls, not success)
                    if case in ('connected','mdns-serial'):
                        self.assertNotIn('avahi-browse', calls)
                    if case == 'discover':
                        self.assertIn('adb connect 192.0.2.2:45678', calls)
                        self.assertNotIn('adb connect 192.0.2.2:9999', calls)
            (root/'calls').unlink()
            with (root/'phone-control.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = subprocess.run([str(root/'phone-control')], env=env, capture_output=True)
                self.assertEqual(result.returncode, 0)
                self.assertFalse((root/'calls').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
