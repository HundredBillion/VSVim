import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NIGHTLY = shutil.which(os.environ.get('VSVIM_NVIM', 'nvim-nightly'))


class StartupTest(unittest.TestCase):
    def test_failed_bootstrap_is_explicit_and_leaves_no_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / 'bin'
            tools.mkdir()
            for name in ('dirname',):
                (tools / name).symlink_to(shutil.which(name))
            env = dict(os.environ, VSVIM_NVIM=NIGHTLY, PATH=str(tools))
            for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
                env[f'XDG_{kind}_HOME'] = str(root / kind.lower())
            result = subprocess.run([str(ROOT / 'bin/vsvim'), '--headless', '+qa'],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertIn('VSVim plugin bootstrap failed', result.stderr)
            self.assertFalse((root / 'data/vsvim/lazy/lazy.nvim').exists())
            self.assertEqual(list((root / 'data/vsvim/lazy').glob('*.install-*')), [])


if __name__ == '__main__':
    unittest.main()
