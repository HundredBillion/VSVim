"""Run with VSVIM_SPRITE_SOURCE=<checkout> uv run --with pynvim python tests/markdown_integration_rpc.py."""
import json
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
NVIM = os.environ.get('VSVIM_NVIM', shutil.which('nvim'))
SPRITE = Path(os.environ['VSVIM_SPRITE_SOURCE'])
CACHE = Path(os.environ.get('VSVIM_PLUGIN_CACHE', Path.home() / '.local/share/vsvim/lazy'))


class MarkdownIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = tempfile.TemporaryDirectory(prefix='vsvim-markdown-plugins-')
        cls.plugins = Path(cls.profile.name) / 'lazy'
        for name in ('lazy.nvim', 'nvim-lspconfig', 'mason.nvim', 'mason-lspconfig.nvim',
                     'sprite.nvim', 'svgtree.nvim', 'scm.nvim'):
            source = SPRITE if name == 'sprite.nvim' else CACHE / name
            shutil.copytree(source, cls.plugins / name, ignore=shutil.ignore_patterns('.git'))

    @classmethod
    def tearDownClass(cls):
        cls.profile.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vsvim-markdown-')
        self.root = Path(self.temp.name)
        self.file = self.root / 'README.md'
        self.file.write_text('# Hello\n\nSome **Markdown**.\n')
        self.env = dict(os.environ, VSVIM_NVIM=NVIM)
        for name in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            self.env[f'XDG_{name}_HOME'] = str(self.root / name.lower())
        plugins = self.root / 'data/vsvim/lazy'
        shutil.copytree(self.plugins, plugins)
        self.env['VSVIM_SPRITE_SOURCE'] = str(plugins / 'sprite.nvim')
        config = self.root / 'config/vsvim'
        config.mkdir(parents=True)
        (config / 'user.lua').write_text('vim.g.vsvim_auto_explorer=false\nvim.g.vsvim_minimap=false\n')
        self.socket = Path(tempfile.mktemp(prefix='vsvim-md-host-', suffix='.sock', dir='/tmp'))
        self.editor_socket = Path(tempfile.mktemp(prefix='vsvim-md-editor-', suffix='.sock', dir='/tmp'))
        self.process = self.nvim = self.host = None

    def wait(self, predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.01)
        if self.process and self.process.poll() is not None:
            self.log.flush()
            self.fail((self.root / 'adapter.log').read_text())
        self.fail('Markdown editor did not reach the expected state')

    def launch(self, supported=True):
        features = ['grid-tabs-v1', 'grid-footer-v1']
        if supported:
            features.append('grid-markdown-v1')
        self.host = Host(self.socket, features)
        env = dict(self.env, SPRITE_SURFACE_SOCKET=str(self.socket), SPRITE_SURFACE_KEY='test-only', SPRITE_PANE='1')
        env.pop('NVIM', None)
        self.log = (self.root / 'adapter.log').open('w')
        self.process = subprocess.Popen([str(ROOT / 'bin/vsvim'), '--listen', str(self.editor_socket), str(self.file)],
                                        cwd=self.root, env=env, stdout=self.log, stderr=self.log)
        self.wait(self.editor_socket.exists)
        self.nvim = pynvim.attach('socket', path=str(self.editor_socket))
        self.wait(lambda: self.nvim.current.buffer.name == str(self.file.resolve()))
        if supported:
            self.wait(lambda: self.state().get('windows') and self.document())

    def latest(self, kind):
        return next((m for m in reversed(self.host.messages)
                     if m.get('type') == 'markdown' and m.get('kind') == kind), None)

    def state(self):
        return self.latest('state') or {}

    def document(self):
        return self.latest('document')

    def action(self, name='toggle', window=None):
        state = self.state()
        target = next(w for w in state['windows'] if w['window'] == (window or state['active']))
        self.host.send(dict(type='markdown_action', revision=state['revision'], window=target['window'],
                            buffer=target['buffer'], generation=target['generation'], action=name))

    def active_preview(self, preview):
        state = self.state()
        return any(w['window'] == state.get('active') and w['preview'] == preview for w in state.get('windows', []))

    def test_preview_source_unsaved_save_undo_and_prompt_use_one_buffer(self):
        self.launch()
        buffer = self.nvim.current.buffer.number
        self.assertTrue(self.active_preview(True))
        self.assertEqual(len(self.nvim.funcs.getbufinfo(dict(buflisted=1))), 1)
        self.action()
        self.wait(lambda: self.active_preview(False))
        self.host.send(dict(type='input', text='A unsaved'))
        self.host.send(dict(type='input', key='escape'))
        self.wait(lambda: self.nvim.current.buffer[0] == '# Hello unsaved')
        tick = self.nvim.api.buf_get_changedtick(buffer)
        self.wait(lambda: any(w['generation'] == tick for w in self.state().get('windows', [])))
        cursor, undo = self.nvim.current.window.cursor, self.nvim.funcs.undotree()['seq_cur']
        self.action()
        self.wait(lambda: self.active_preview(True) and self.document()['generation'] == tick)
        self.assertIn('unsaved', self.document()['text'])
        self.assertTrue(self.nvim.current.buffer.options['modified'])
        self.assertEqual(self.nvim.current.buffer.number, buffer)
        self.assertEqual(self.nvim.current.window.cursor, cursor)
        self.assertEqual(self.nvim.funcs.undotree()['seq_cur'], undo)
        self.assertNotIn('unsaved', self.file.read_text())
        self.host.send(dict(type='input', text='x'))
        self.host.send(dict(type='paste', text='must not change source'))
        self.host.send(dict(type='input', key='cmd-s'))
        self.wait(lambda: not self.nvim.current.buffer.options['modified'])
        self.assertEqual(self.file.read_text(), '# Hello unsaved\n\nSome **Markdown**.\n')
        self.assertFalse(self.nvim.current.buffer.options['modified'])
        self.host.send(dict(type='input', text=':'))
        self.wait(lambda: self.nvim.api.get_mode()['mode'] == 'c')
        self.host.send(dict(type='input', text='VSVimMarkdownToggle'))
        self.host.send(dict(type='input', key='enter'))
        self.wait(lambda: self.active_preview(False))
        self.host.send(dict(type='input', text='u'))
        self.wait(lambda: self.nvim.current.buffer[0] == '# Hello')
        self.host.send(dict(type='input', key='ctrl-r'))
        self.wait(lambda: self.nvim.current.buffer[0] == '# Hello unsaved')
        self.assertEqual(self.nvim.current.buffer.number, buffer)
        self.assertEqual(len(self.nvim.funcs.getbufinfo(dict(buflisted=1))), 1)

    def test_split_focus_and_rename_refresh_document_path(self):
        self.launch()
        other = self.root / 'other.md'
        other.write_text('# Other\n')
        self.host.command('vsplit ' + str(other))
        self.wait(lambda: len(self.state().get('windows', [])) == 2)
        state = self.state()
        original = next(w for w in state['windows'] if w['window'] != state['active'])
        self.action('focus', original['window'])
        self.wait(lambda: self.nvim.current.window.handle == original['window'])
        self.wait(lambda: self.state().get('active') == original['window'])
        self.assertEqual(self.nvim.current.buffer.name, str(self.file.resolve()))
        renamed = self.root / 'renamed.md'
        tick = self.nvim.api.buf_get_changedtick(original['buffer'])
        self.host.command('file ' + str(renamed))
        self.wait(lambda: self.document()['buffer'] == original['buffer'] and self.document()['path'] == str(renamed.resolve()))
        self.assertEqual(self.document()['generation'], tick)
        self.assertEqual(len(self.nvim.funcs.getbufinfo(dict(buflisted=1))), 2)

    def test_older_host_retains_editable_markdown(self):
        self.launch(False)
        self.assertFalse(self.nvim.exec_lua("return require('vsvim.markdown').previewing()"))
        self.assertIsNone(self.latest('state'))
        self.host.send(dict(type='input', text='x'))
        self.wait(lambda: self.nvim.current.buffer[0] == ' Hello')

    def tearDown(self):
        if self.nvim:
            self.nvim.close()
        if self.host and self.host.connection:
            try:
                self.host.command('qa!')
            except OSError:
                pass
        if self.process:
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
            self.log.close()
        if self.host:
            self.host.close()
        self.socket.unlink(missing_ok=True)
        self.editor_socket.unlink(missing_ok=True)
        self.temp.cleanup()


if __name__ == '__main__':
    unittest.main()
