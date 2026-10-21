"""Exercise VSVim's Follow adapter and Sprite host with known files."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

import pynvim
from minimap_integration_rpc import Host

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = Path(os.environ['VSVIM_SPRITE_SOURCE'])
CACHE = Path.home() / '.local/share/vsvim/lazy'
NVIM = os.environ.get('VSVIM_NVIM', str(Path.home() / '.local/nvim-nightly/bin/nvim'))


class FollowIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vsvim-follow-')
        self.base = Path(self.temp.name).resolve()
        self.project = self.base / 'project'
        self.project.mkdir()
        self.first = self.project / 'first.lua'
        self.first.write_text('local first = 1\n')
        self.target = self.project / 'nested/main.lua'
        self.target.parent.mkdir()
        self.target.write_text('one\ntwo\nthree\n')
        self.env = dict(os.environ, VSVIM_NVIM=NVIM)
        for name in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            self.env[f'XDG_{name}_HOME'] = str(self.base / name.lower())
        plugins = self.base / 'data/vsvim/lazy'
        for name in ('lazy.nvim', 'nvim-lspconfig', 'mason.nvim', 'mason-lspconfig.nvim',
                     'sprite.nvim', 'svgtree.nvim', 'scm.nvim'):
            source = ADAPTER if name == 'sprite.nvim' else CACHE / name
            shutil.copytree(source, plugins / name, ignore=shutil.ignore_patterns('.git', '.worktrees'))
        self.env['VSVIM_SPRITE_SOURCE'] = str(plugins / 'sprite.nvim')
        config = self.base / 'config/vsvim'
        config.mkdir(parents=True)
        (config / 'user.lua').write_text('vim.g.vsvim_auto_explorer=false\nvim.g.vsvim_minimap=false\n')
        self.socket = Path(tempfile.mktemp(prefix='follow-host-', suffix='.sock', dir='/tmp'))
        self.editor_socket = Path(tempfile.mktemp(prefix='follow-editor-', suffix='.sock', dir='/tmp'))
        self.process = self.nvim = self.host = None
        self.log = (self.base / 'editor.log').open('w')

    def wait(self, predicate):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if predicate():
                return
            if self.process and self.process.poll() is not None:
                self.fail((self.base / 'editor.log').read_text())
            time.sleep(.02)
        self.fail('Follow timed out: ' + (self.base / 'editor.log').read_text())

    def launch(self, native=True):
        features = ['grid-tabs-v1', 'grid-footer-v1']
        if native:
            features.append('grid-follow-v1')
        self.host = Host(self.socket, features)
        env = dict(self.env, SPRITE_SURFACE_SOCKET=str(self.socket), SPRITE_SURFACE_KEY='test', SPRITE_PANE='1')
        env.pop('NVIM', None)
        self.process = subprocess.Popen([str(ROOT / 'bin/vsvim'), '--listen', str(self.editor_socket), str(self.first)],
                                        cwd=self.project, env=env, stdout=self.log, stderr=self.log)
        self.wait(self.editor_socket.exists)
        self.nvim = pynvim.attach('socket', path=str(self.editor_socket))
        self.wait(lambda: self.nvim.current.buffer.name == str(self.first))
        self.nvim.command('badd ' + self.nvim.funcs.fnameescape(str(self.target)))

    def footer(self):
        return next((message for message in reversed(self.host.messages) if message.get('type') == 'footer'), {})

    def test_native_toggle_external_write_cursor_and_stop(self):
        self.launch()
        self.wait(lambda: self.footer().get('follow') is not None)
        self.assertFalse(self.footer()['follow']['enabled'])
        self.host.send(dict(type='follow_action', action='toggle'))
        self.wait(lambda: self.footer().get('follow', {}).get('ready'))
        self.assertEqual(self.nvim.current.buffer.name, str(self.first))
        started = time.monotonic()
        self.target.write_text('one\ntwo\nexternally changed\n')
        self.wait(lambda: self.nvim.current.buffer.name == str(self.target))
        self.assertEqual(self.nvim.current.window.cursor, (1, 0))
        self.assertEqual(self.nvim.current.buffer[2], 'externally changed')
        print(f'Native external-write-to-cursor: {(time.monotonic()-started)*1000:.0f} ms')
        self.assertTrue(self.nvim.exec_lua("return require('vsvim.follow').status().enabled"))
        self.host.send(dict(type='follow_action', action='toggle'))
        self.wait(lambda: not self.footer().get('follow', {}).get('enabled', True))
        self.first.write_text('must not jump\n')
        time.sleep(.7)
        self.assertEqual(self.nvim.current.buffer.name, str(self.target))

    def test_older_host_uses_clickable_statusline_and_commands(self):
        self.launch(False)
        self.wait(lambda: self.footer().get('cells'))
        self.assertNotIn('follow', self.footer())
        text = ''.join(cell[0] * (cell[2] if len(cell) > 2 else 1) for cell in self.footer()['cells'])
        self.assertIn('FOLLOW Off', text)
        self.nvim.command('VSVimFollowOn')
        self.wait(lambda: self.nvim.exec_lua("return require('vsvim.follow').status().ready"))
        self.target.write_text('one\nexternal fallback\nthree\n')
        self.wait(lambda: self.nvim.current.buffer.name == str(self.target))
        self.assertEqual(self.nvim.current.window.cursor, (1, 0))
        self.nvim.exec_lua("VSVimFollowClick(0,1,'l','')")
        self.assertFalse(self.nvim.exec_lua("return require('vsvim.follow').status().enabled"))

    def test_native_toggle_controls_live_preview(self):
        self.launch()
        self.wait(lambda: self.footer().get('follow') is not None)
        self.host.send(dict(type='follow_action', action='toggle'))
        self.wait(lambda: self.footer().get('follow', {}).get('ready'))

        def preview(text):
            return self.nvim.exec_lua(
                "return require('vsvim.follow').preview(...)",
                dict(path=str(self.target), text=text, cursor=[1, 3]))

        self.assertTrue(preview('stream one'))
        self.assertEqual(self.nvim.current.buffer[0], 'stream one')
        self.host.send(dict(type='follow_action', action='toggle'))
        self.wait(lambda: not self.footer().get('follow', {}).get('enabled', True))
        self.assertFalse(preview('stream two'))
        self.assertEqual(self.nvim.current.buffer[0], 'stream one')
        self.host.send(dict(type='follow_action', action='toggle'))
        self.wait(lambda: self.footer().get('follow', {}).get('ready'))
        self.assertTrue(preview('stream three'))
        self.assertEqual(self.nvim.current.buffer[0], 'stream three')
        self.assertEqual(self.nvim.current.window.cursor, (1, 3))
        self.assertEqual(self.target.read_text(), 'one\ntwo\nthree\n')

    def tearDown(self):
        if self.nvim:
            try:
                self.nvim.command('qa!')
            except (EOFError, OSError):
                pass
            self.nvim.close()
        if self.process:
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        if self.host:
            self.host.close()
        self.log.close()
        self.socket.unlink(missing_ok=True)
        self.editor_socket.unlink(missing_ok=True)
        self.temp.cleanup()


if __name__ == '__main__':
    unittest.main()
