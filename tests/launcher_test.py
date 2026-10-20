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
                       NVIM_APPNAME='existing-app', VSVIM_NVIM=str(executable), VSVIM_NATIVE='0')
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

    def test_sprite_uses_nightly_adapter_but_batch_and_nested_launches_do_not(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adapter = root / 'vsvim/lazy/sprite.nvim/lua/sprite/adapter.lua'
            adapter.parent.mkdir(parents=True)
            adapter.write_text('')
            executable = root / 'nightly'
            executable.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
            executable.chmod(0o755)
            env = dict(os.environ, VSVIM_NVIM=str(executable), XDG_DATA_HOME=str(root),
                       SPRITE_SURFACE_SOCKET='/test/socket', SPRITE_SURFACE_KEY='test-only',
                       SPRITE_PANE='0')
            env.pop('NVIM', None)
            env.pop('VSVIM_NATIVE', None)
            env.pop('VSVIM_SPRITE_SOURCE', None)
            base = ['-u', str(ROOT / 'init.lua')]
            for args, native in [(['a b.lua'], True), (['--headless', '+qa'], False),
                                 (['--version'], False), (['--embed'], False),
                                 (['-l', 'script.lua'], False)]:
                with self.subTest(args=args):
                    result = subprocess.run([str(ROOT / 'bin/vsvim'), *args], env=env,
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    prefix = ['-l', str(adapter)] if native else []
                    self.assertEqual(json.loads(result.stdout), prefix + base + args)
            source = root / 'adapter checkout'
            checkout_adapter = source / 'lua/sprite/adapter.lua'
            checkout_adapter.parent.mkdir(parents=True)
            checkout_adapter.write_text('')
            env['VSVIM_SPRITE_SOURCE'] = str(source)
            result = subprocess.run([str(ROOT / 'bin/vsvim'), 'README.md'], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), ['-l', str(checkout_adapter)] + base + ['README.md'])
            env['NVIM'] = '/nested/editor'
            result = subprocess.run([str(ROOT / 'bin/vsvim'), 'file.lua'], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), base + ['file.lua'])

if __name__ == '__main__':
    unittest.main()
