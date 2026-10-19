import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NIGHTLY = shutil.which(os.environ.get('VSVIM_NVIM', 'nvim-nightly'))
PINS = {
    'nvim-lspconfig': '45a3a444b710511c39abca3b60bb6e23a21e3de5',
    'mason.nvim': '2a6940af80375532e5e9e7c1f2fc6319a1b7a69d',
    'mason-lspconfig.nvim': '00b5473cca4db5b410ff4bae724e3b6e21f2687f',
    'scm.nvim': 'c6946caa84c49054f37bf9097b7f59bcadf2bfa7',
    'lazy.nvim': '85c7ff3711b730b4030d03144f6db6375044ae82',
    'sprite.nvim': 'a81577daaf834def81db9dc5935bfbd8353f643e',
    'svgtree.nvim': 'b1781a04d6147292ccd240cac8b73f6b31c679e3',
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
                'vim.g.vsvim_override_loaded = true\nvim.opt.shiftwidth = 4\n'
                'vim.g.vsvim_minimap = false\n')
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
            launch('+lua assert(vim.fn.exists(":VSVimMinimapToggle")==2); '
                   'assert(vim.g.vsvim_minimap==false); '
                   'assert(require("vsvim.minimap").provider().target()==nil)', '+qa!')
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
            definition_script = str(ROOT / 'tests/definition.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(definition_script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim definition navigation passed', output)
            picker_script = str(ROOT / 'tests/definition_picker.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(picker_script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim compact definition picker passed', output)
            setup_script = str(ROOT / 'tests/lsp_setup.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(setup_script) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('LSP setup passed', output)
            for script_name, marker in (
                    ('lsp_environment.lua', 'LSP environment passed'),
                    ('lsp_lifecycle.lua', 'LSP lifecycle passed')):
                script = str(ROOT / 'tests' / script_name)
                output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(script) +
                                '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
                self.assertIn(marker, output)
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
            tab_order = str(ROOT / 'tests/tab_order.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(tab_order) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('VSVim tab ordering passed', output)
            one_dark = str(ROOT / 'tests/one_dark.lua')
            output = launch('+lua local ok,e=pcall(dofile,' + json.dumps(one_dark) +
                            '); if not ok then print(e); vim.cmd("cquit 1") end', '+qa!')
            self.assertIn('One Dark syntax: PASS', output)
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
