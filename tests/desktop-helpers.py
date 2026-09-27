#!/usr/bin/env python3
"""Exercise inline desktop helpers with mocked command boundaries; no activation."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['CALLS'], 'a') as stream:
    stream.write(json.dumps([name, *sys.argv[1:]]) + '\n')
if name == 'sudo':
    print('rebuild stdout')
    print('rebuild stderr', file=sys.stderr)
    sys.exit(int(os.environ['REBUILD_STATUS']))
if name == 'notify-send':
    sys.exit(13)  # An unavailable notification daemon must not mask rebuild status.
if name == 'hostname':
    print('nixos-desktop')
if name == 'readlink':
    print('system-47-link')
if name == 'playerctl':
    players = json.loads(os.environ.get('PLAYERS', '{}'))
    if sys.argv[1:] == ['-l']:
        print('\n'.join(players))
    elif sys.argv[3] == 'status':
        print(players[sys.argv[2]])
    elif sys.argv[3] == 'metadata':
        print('A & B' if sys.argv[4] == 'artist' else 'Track <Live>')
    else:
        sys.exit(int(os.environ.get('PLAYER_STATUS', '0')))
'''


def inline_body(source, assignment):
    body = re.search(r'\b' + assignment + r"\s*=\s*''\n(.*?)\n\s*'';", source, re.S)
    if body is None:
        raise AssertionError(f'Missing inline script: {assignment}')
    return textwrap.dedent(body[1])


class DesktopHelpersTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.calls = self.root / 'calls'
        for name in ('sudo', 'notify-send', 'hostname', 'readlink', 'nix', 'playerctl'):
            command = self.root / name
            command.write_text(MOCK)
            command.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), CALLS=str(self.calls),
                        PATH=str(self.root) + ':' + os.environ['PATH'])

    def commands(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def fish_function(self, name):
        body = inline_body((ROOT / 'home/corey.nix').read_text(), name)
        self.assertNotIn('${', body, 'Use Nix evaluation if interpolation is added')
        return f'function {name}\n{body}\nend\n{name}\nexit $status'

    def test_rebuild_preserves_output_status_and_notification_severity(self):
        for status in (0, 1, 42, 130):
            with self.subTest(status=status):
                self.calls.unlink(missing_ok=True)
                result = subprocess.run(['fish', '--no-config', '-c', self.fish_function('rebuild')],
                                        env=self.env | {'REBUILD_STATUS': str(status)},
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(result.stdout, 'rebuild stdout\n')
                self.assertEqual(result.stderr, 'rebuild stderr\n')
                commands = self.commands()
                self.assertIn(['sudo', 'nixos-rebuild', 'switch', '--flake',
                               str(self.root / 'nixos-config') + '#nixos-desktop'], commands)
                notification, = [c for c in commands if c[0] == 'notify-send']
                if status == 0:
                    self.assertIn('System rebuild succeeded', notification)
                    self.assertIn('Active generation: 47', notification)
                    self.assertNotIn('critical', notification)
                else:
                    self.assertIn('critical', notification)
                    self.assertIn('System rebuild failed', notification)
                    self.assertNotIn('System rebuild succeeded', notification)

    def test_update_stops_if_repository_is_missing(self):
        result = subprocess.run(['fish', '--no-config', '-c', self.fish_function('update')],
                                env=self.env, capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def media(self, players, *args, status=0):
        source = (ROOT / 'modules/home/waybar.nix').read_text().split('nowPlaying =', 1)[1]
        body = inline_body(source, 'text').replace("''${status,,}", '${status,,}')
        self.assertNotIn("''${", body, 'Review new Nix escaping before extracting')
        return subprocess.run(['bash', '-euo', 'pipefail', '-c', body, 'waybar-now-playing', *args],
                              env=self.env | {'PLAYERS': json.dumps(players), 'PLAYER_STATUS': str(status)},
                              capture_output=True, text=True, timeout=5)

    def test_display_and_actions_select_playing_before_paused(self):
        players = {'browser': 'Paused', 'music': 'Playing'}
        result = self.media(players)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['text'], '♪ A & B — Track <Live>')
        self.assertEqual(json.loads(result.stdout)['class'], 'playing')
        for action in ('play-pause', 'previous', 'next'):
            result = self.media(players, action)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.commands()[-1], ['playerctl', '-p', 'music', action])

    def test_paused_fallback_empty_stopped_and_action_failure(self):
        result = self.media({'browser': 'Stopped', 'music': 'Paused'})
        self.assertEqual(json.loads(result.stdout)['class'], 'paused')
        for players in ({}, {'browser': 'Stopped'}):
            for args in ((), ('play-pause',)):
                result = self.media(players, *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, '')
        self.assertEqual(self.media({'music': 'Playing'}, 'next', status=7).returncode, 7)


if __name__ == '__main__':
    unittest.main(verbosity=2)
