#!/usr/bin/env python3
"""Mock menu/compositor/terminal boundaries; never open a real session or editor."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "modules/home/system-tools.nix"
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['CALLS'], 'a') as stream:
    stream.write(json.dumps([name, *sys.argv[1:]]) + '\n')
if name == 'fuzzel':
    print(os.environ.get('CHOICE', ''))
    sys.exit(int(os.environ.get('MENU_STATUS', '0')))
if name == 'kitty':
    sys.exit(int(os.environ.get('KITTY_STATUS', '0')))
'''


class GrimoireTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        # Keep the script inline in its existing module; exercise that exact body.
        source = SOURCE.read_text().split('systemGrimoire =', 1)[1]
        body = textwrap.dedent(source.split("text = ''\n", 1)[1].split("\n    '';", 1)[0])
        self.assertNotIn('${', body, 'Use Nix evaluation if the body gains interpolation')
        self.script = self.root / 'system-grimoire'
        self.script.write_text('#!/usr/bin/env bash\nset -euo pipefail\n' + body)
        for name in ('swaymsg', 'fuzzel', 'kitty'):
            command = self.root / name
            command.write_text(MOCK)
            command.chmod(0o755)
        self.calls = self.root / 'calls.jsonl'

    def execute(self, choice='', status=0, **extra):
        self.calls.unlink(missing_ok=True)
        env = dict(os.environ, PATH=str(self.root) + ':' + os.environ['PATH'],
                   CALLS=str(self.calls), CHOICE=choice, **extra)
        env.pop('EDITOR', None)
        result = subprocess.run(['bash', str(self.script)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, status, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls[:2][0], ['swaymsg', 'focus_follows_mouse', 'no'])
        self.assertEqual(calls[1][0], 'fuzzel')
        self.assertEqual(calls[2], ['swaymsg', 'focus_follows_mouse', 'yes'])
        self.assertEqual(sum(call[0] == 'swaymsg' for call in calls), 2)
        return calls

    def test_all_actions_restore_before_exec(self):
        for choice in ('Rebuild', 'Generations', 'Rollback', 'System info', 'Services', 'Logs', 'Open config'):
            with self.subTest(choice=choice):
                calls = self.execute(choice)
                self.assertEqual(len(calls), 4)
                self.assertEqual(calls[3][0], 'kitty')
                subprocess.run(['fish', '--no-config', '-n', '-c', calls[3][-1]], check=True)

    def test_cancel_empty_and_unknown_restore_focus(self):
        for choice, status in (('', '1'), ('', '0'), ('unknown', '0')):
            with self.subTest(choice=choice, status=status):
                self.assertEqual(len(self.execute(choice, MENU_STATUS=status)), 3)

    def test_terminal_failure_still_restores_focus(self):
        self.execute('Rebuild', status=7, KITTY_STATUS='7')

    def test_open_config_uses_explicit_editor_and_checks_cd(self):
        command = self.execute('Open config')[3][-1]
        self.assertEqual(command, 'cd ~/nixos-config; and exec vim flake.nix')
        self.assertNotIn('$EDITOR', command)


if __name__ == '__main__':
    unittest.main(verbosity=2)
