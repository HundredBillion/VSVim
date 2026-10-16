import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class LauncherTest(unittest.TestCase):
    def test_isolation_arguments_and_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'nvim-nightly'
            executable.write_text('''#!/usr/bin/env python3
import json, os, sys
print(json.dumps({'args': sys.argv[1:], 'app': os.environ['NVIM_APPNAME'],
                 'root': os.environ['VSVIM_ROOT'], 'cwd': os.getcwd(),
                 'home': os.environ['HOME']}))
sys.exit(23)
''')
            executable.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       NVIM_APPNAME='existing-app', VSVIM_NVIM=str(executable))
            result = subprocess.run(
                ['sh', str(ROOT / 'bin/vsvim'), 'file with spaces.lua', '+set number'],
                env=env, cwd=root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            record = json.loads(result.stdout)
            self.assertEqual(record['app'], 'vsvim')
            self.assertEqual(Path(record['root']), ROOT)
            self.assertEqual(record['args'], ['-u', str(ROOT / 'init.lua'),
                                            'file with spaces.lua', '+set number'])
            self.assertEqual(Path(record['cwd']).resolve(), root.resolve())
            self.assertEqual(record['home'], os.environ['HOME'])
            links = root / 'launch links'
            links.mkdir()
            (links / 'target').symlink_to(ROOT / 'bin/vsvim')
            (links / 'vsvim').symlink_to('target')
            result = subprocess.run(
                [str(links / 'vsvim'), 'file with spaces.lua', '+set number'],
                env=env, cwd=root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertEqual(json.loads(result.stdout), record)

if __name__ == '__main__':
    unittest.main()
