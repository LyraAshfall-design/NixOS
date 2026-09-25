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
import shutil
import signal
import subprocess
import tempfile
import time
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
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ['FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
case = os.environ['CASE']
with (root/'calls').open('a') as f: f.write(name+' '+ ' '.join(sys.argv[1:])+'\n')
# Deliberately preserve inherited FDs, like a daemonizing ADB server.
if name == os.environ.get('PERSIST_FROM') and not (root/'child.pid').exists():
    child = subprocess.Popen(['sleep', '60'], close_fds=False,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    (root/'child.pid').write_text(str(child.pid))
if name == 'jq':
    os.execv(os.environ['REAL_JQ'], ['jq', *sys.argv[1:]])
if name == 'swaymsg':
    if os.environ.get('SWAY_FAIL'): sys.exit(1)
    if sys.argv[1:] == ['-r', '-t', 'get_tree']:
        nodes = [json.loads(p.read_text()) for p in root.glob('*.window')]
        print(json.dumps({'nodes': [], 'floating_nodes': nodes}))
    else:
        assert sys.argv[1] == '-q'
        target = int(sys.argv[2].removeprefix('[con_id=').removesuffix('] kill'))
        for p in root.glob('*.window'):
            if json.loads(p.read_text())['id'] == target:
                p.with_suffix('.close').touch()
    sys.exit(0)
if name == 'adb' and os.environ.get('BLOCK_ADB'):
    (root/'adb.ready').touch()
    while not (root/'adb.release').exists(): time.sleep(0.01)
if name == 'scrcpy' and os.environ.get('BLOCK_SCRCPY'):
    (root/'scrcpy.ready').touch()
    while not (root/'scrcpy.release').exists(): time.sleep(0.01)
if name == 'scrcpy' and os.environ.get('RUN_WINDOW'):
    managed = '--window-title=phone-control' in sys.argv
    key = 'managed' if managed else 'unrelated'
    window = root/(key+'.window')
    assert not window.exists(), 'Duplicate scrcpy window'
    pending = root/(key+'.pending')
    pending.write_text(json.dumps({'type': 'con', 'id': os.getpid(),
                                   'name': 'phone-control' if managed else 'Other phone'}))
    pending.replace(window)
    while not (root/(key+'.close')).exists(): time.sleep(0.01)
    window.unlink()
    if managed and os.environ.get('BLOCK_SHUTDOWN'):
        (root/'shutdown.ready').touch()
        while not (root/'shutdown.release').exists(): time.sleep(0.01)
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
    def wait_for(self, path):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(path.exists(), str(path))

    def control_fixture(self, root, **extra):
        for name in ('adb', 'avahi-browse', 'scrcpy', 'notify-send', 'swaymsg', 'jq'):
            p = root / name
            p.write_text(MOCK)
            p.chmod(0o755)
        for name in ('phone-adb-connect', 'phone-control'):
            p = root / name
            p.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + (SCRIPTS / (name + '.sh')).read_text())
            p.chmod(0o755)
        return dict(os.environ, PATH=str(root)+':'+os.environ['PATH'],
                    FIXTURE=str(root), XDG_RUNTIME_DIR=str(root), REAL_JQ=shutil.which('jq'), **extra)

    def test_toggle_open_close_reopen_preserves_unrelated_scrcpy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = self.control_fixture(root, CASE='connected', RUN_WINDOW='1', BLOCK_SHUTDOWN='1')
            unrelated = subprocess.Popen([str(root/'scrcpy'), '--serial=other'], env=env)
            launcher = None
            try:
                self.wait_for(root/'unrelated.window')
                for cycle in range(2):
                    for name in ('managed.close', 'shutdown.ready', 'shutdown.release'):
                        (root/name).unlink(missing_ok=True)
                    launcher = subprocess.Popen([str(root/'phone-control')], env=env)
                    self.wait_for(root/'managed.window')
                    pid = json.loads((root/'managed.window').read_text())['id']
                    calls = (root/'calls').read_text()
                    result = subprocess.run([str(root/'phone-control')], env=env,
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    close_calls = (root/'calls').read_text()[len(calls):]
                    self.assertIn(f'swaymsg -q [con_id={pid}] kill', close_calls)
                    self.assertNotIn('adb ', close_calls)
                    self.assertNotIn('scrcpy ', close_calls)
                    self.wait_for(root/'shutdown.ready')
                    # The window is gone, but launch remains excluded until scrcpy exits.
                    result = subprocess.run([str(root/'phone-control')], env=env,
                                            capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual((root/'calls').read_text().count('scrcpy --serial=192.'), cycle + 1)
                    (root/'shutdown.release').touch()
                    self.assertEqual(launcher.wait(timeout=5), 0)
                    self.assertFalse(Path(f'/proc/{pid}').exists(), 'scrcpy was not reaped')
                    with (root/'phone-control.lock').open('a') as lock:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.assertIsNone(unrelated.poll())
                    self.assertFalse((root/'unrelated.close').exists())
            finally:
                for name in ('managed.close', 'unrelated.close', 'shutdown.release'):
                    (root/name).touch()
                if launcher is not None:
                    launcher.wait(timeout=5)
                unrelated.wait(timeout=5)

    def test_rapid_presses_during_connection_and_window_startup(self):
        for stage in ('adb', 'scrcpy'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                env = self.control_fixture(root, CASE='connected', **{'BLOCK_'+stage.upper(): '1'})
                launcher = subprocess.Popen([str(root/'phone-control')], env=env)
                repeats = []
                try:
                    self.wait_for(root/(stage+'.ready'))
                    calls = (root/'calls').read_text()
                    repeats = [subprocess.Popen([str(root/'phone-control')], env=env) for _ in range(8)]
                    for repeat in repeats:
                        self.assertEqual(repeat.wait(timeout=5), 0)
                    new_calls = (root/'calls').read_text()[len(calls):].splitlines()
                    self.assertEqual(len(new_calls), 16)
                    self.assertTrue(all(line.startswith(('swaymsg ', 'jq ')) for line in new_calls))
                finally:
                    (root/(stage+'.release')).touch()
                    for repeat in repeats:
                        repeat.wait(timeout=5)
                    launcher.wait(timeout=5)
                self.assertEqual(launcher.returncode, 0)
                self.assertEqual((root/'calls').read_text().count('scrcpy --serial='), 1)

    def test_sway_failure_does_not_launch_or_contact_adb(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = self.control_fixture(root, CASE='connected', SWAY_FAIL='1')
            result = subprocess.run([str(root/'phone-control')], env=env, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            calls = (root/'calls').read_text()
            self.assertIn('notify-send', calls)
            self.assertNotIn('adb ', calls)
            self.assertNotIn('scrcpy ', calls)

    def test_persistent_children_do_not_retain_control_lock(self):
        for command, case in (('adb', 'discover'), ('scrcpy', 'connected'),
                              ('notify-send', 'adb-fail'), ('swaymsg', 'connected'),
                              ('jq', 'connected')):
            with self.subTest(command=command), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                env = self.control_fixture(root, CASE=case, PERSIST_FROM=command)
                try:
                    result = subprocess.run([str(root/'phone-control')], env=env,
                                            capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 1 if case == 'adb-fail' else 0)
                    pid = int((root/'child.pid').read_text())
                    os.kill(pid, 0)  # The daemon outlives the launcher.
                    lock_path = root/'phone-control.lock'
                    inherited = [p.resolve() for p in Path(f'/proc/{pid}/fd').iterdir()]
                    self.assertNotIn(lock_path, inherited)
                    with lock_path.open('a') as lock:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    # A successful exit alone is insufficient: duplicates exit 0 too.
                    (root/'calls').unlink()
                    result = subprocess.run([str(root/'phone-control')],
                                            env=dict(env, CASE='connected'),
                                            capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 0)
                    self.assertIn('scrcpy --serial=', (root/'calls').read_text())
                finally:
                    if (root/'child.pid').exists():
                        os.kill(int((root/'child.pid').read_text()), signal.SIGTERM)

    def test_duplicate_is_excluded_during_scrcpy(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = self.control_fixture(root, CASE='connected', BLOCK_SCRCPY='1')
            launcher = subprocess.Popen([str(root/'phone-control')], env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not (root/'scrcpy.ready').exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue((root/'scrcpy.ready').exists())
                calls = (root/'calls').read_text()
                result = subprocess.run([str(root/'phone-control')], env=env,
                                        capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0)
                self.assertEqual([line.split()[0] for line in
                                  (root/'calls').read_text()[len(calls):].splitlines()], ['swaymsg', 'jq'])
            finally:
                (root/'scrcpy.release').touch()
                launcher.wait(timeout=5)
            self.assertEqual(launcher.returncode, 0)

    def test_phone_control_regression(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            env = self.control_fixture(root, CASE='connected')
            for case in ('connected','mdns-serial','discover','missing','connect-fail','multiple','adb-fail','scrcpy-fail'):
                with self.subTest(case=case):
                    for name in ('calls','connected'):
                        (root/name).unlink(missing_ok=True)
                    env = dict(env, CASE=case)
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
                self.assertEqual([line.split()[0] for line in (root/'calls').read_text().splitlines()],
                                 ['swaymsg', 'jq'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
