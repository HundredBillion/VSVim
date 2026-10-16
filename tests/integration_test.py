import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NIGHTLY = shutil.which(os.environ.get('VSVIM_NVIM', 'nvim-nightly'))
PINS = {
    'scm.nvim': '8aeb27e3e9b5edd824c0abe31e55f328c06ea5ef',
    'lazy.nvim': '85c7ff3711b730b4030d03144f6db6375044ae82',
    'sprite.nvim': '05adda83c090da78f4faf30bdae3b678990d2b0e',
    'svgtree.nvim': 'd33176b24600dd36521fe1137ff8e40e84b40f71',
}


class IntegrationTest(unittest.TestCase):
    def test_fresh_install_and_cached_explorer(self):
        with tempfile.TemporaryDirectory(prefix='vsvim-integration-') as directory:
            root = Path(directory)
            env = dict(os.environ, VSVIM_NVIM=NIGHTLY)
            for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
                env[f'XDG_{kind}_HOME'] = str(root / kind.lower())
            config = root / 'config/vsvim'
            config.mkdir(parents=True)
            (config / 'user.lua').write_text(
                'vim.g.vsvim_override_loaded = true\nvim.opt.shiftwidth = 4\n')
            ordinary = root / 'config/nvim'
            ordinary.mkdir()
            sentinel = ordinary / 'init.lua'
            sentinel.write_text('error("ordinary config must not load")\n')
            original = sentinel.read_bytes()

            def launch(*args):
                result = subprocess.run([str(ROOT / 'bin/vsvim'), '--headless', *args],
                                        cwd=root, env=env, text=True,
                                        capture_output=True, timeout=180)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout + result.stderr

            launch('+Lazy! sync', '+qa')
            for name, commit in PINS.items():
                actual = subprocess.check_output(
                    ['git', '-C', str(root / 'data/vsvim/lazy' / name),
                     'rev-parse', 'HEAD'], text=True).strip()
                self.assertEqual(actual, commit, name)
            import json
            scm_script = str(ROOT / 'tests/scm.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(scm_script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim SCM passed', output)
            native_script = str(ROOT / 'tests/native_handoff.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(native_script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim native handoff passed', output)
            tools = root / 'bin'
            tools.mkdir()
            (tools / 'dirname').symlink_to(shutil.which('dirname'))
            env['PATH'] = str(tools)
            script = str(ROOT / 'tests/smoke.lua')
            import json
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa')
            self.assertIn('VSVim smoke passed', output)
            appearance = str(ROOT / 'tests/appearance.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(appearance) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim appearance passed', output)
            self.assertEqual(sentinel.read_bytes(), original)
            for name in ('sprite.nvim', 'svgtree.nvim', 'scm.nvim'):
                shutil.rmtree(root / 'data/vsvim/lazy' / name)
            git = tools / 'git'
            git.write_text('#!/bin/sh\necho "simulated offline clone failure" >&2\nexit 1\n')
            git.chmod(0o755)
            failed = subprocess.run([str(ROOT / 'bin/vsvim'), '--headless', '+qa'],
                                    cwd=root, env=env, text=True,
                                    capture_output=True, timeout=30)
            self.assertNotEqual(failed.returncode, 0, failed.stderr)
            self.assertIn('VSVim required plugins unavailable', failed.stderr)


if __name__ == '__main__':
    unittest.main()
