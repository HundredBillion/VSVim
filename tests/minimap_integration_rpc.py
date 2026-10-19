"""Full setup with an isolated plugin profile and the real native adapter.

Run: uv run --with pynvim python tests/minimap_integration_rpc.py
Set VSVIM_SPRITE_SOURCE and VSVIM_PLUGIN_CACHE to alternate local checkouts/cache.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest

import pynvim

ROOT = Path(__file__).resolve().parents[1]
NVIM = os.environ.get('VSVIM_NVIM', '/Users/davidlee/.local/nvim-nightly/bin/nvim')
SPRITE = Path(os.environ.get('VSVIM_SPRITE_SOURCE', ROOT.parent / 'sprite.nvim'))
CACHE = Path(os.environ.get('VSVIM_PLUGIN_CACHE', Path.home() / '.local/share/vsvim/lazy'))


class Host:
    def __init__(self, path, features):
        self.features, self.messages, self.connection = features, [], None
        self.socket = socket.socket(socket.AF_UNIX)
        self.socket.bind(str(path))
        self.socket.listen()
        self.socket.settimeout(.1)
        self.closed = False
        self.clients = []
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while not self.closed:
            try:
                client, _ = self.socket.accept()
            except (TimeoutError, OSError):
                continue
            self.clients.append(client)
            threading.Thread(target=self.read, args=(client,), daemon=True).start()

    def read(self, client):
        try:
            with client.makefile('rb') as stream:
                first = json.loads(stream.readline().split(b' ', 1)[1])
                if first['type'] == 'capabilities':
                    client.sendall((json.dumps(dict(type='capabilities', version=1,
                                                   eligible=True, features=[], limits={})) + '\n').encode())
                    return
                self.connection = client
                self.send(dict(type='opened', surface=1, features=self.features))
                self.send(dict(type='resize', width=800, height=480, cols=100, rows=30))
                for line in stream:
                    self.messages.append(json.loads(line))
        except (OSError, ValueError, IndexError):
            pass

    def send(self, message):
        self.connection.sendall((json.dumps(message) + '\n').encode())

    def command(self, text):
        self.send(dict(type='input', text=':' + text))
        self.send(dict(type='input', key='enter'))

    def close(self):
        self.closed = True
        for client in self.clients:
            try:
                client.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            client.close()
        self.socket.close()


class MinimapIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = tempfile.TemporaryDirectory(prefix='vsvim-minimap-plugins-')
        cls.plugins = Path(cls.profile.name) / 'lazy'
        for name in ('lazy.nvim', 'nvim-lspconfig', 'mason.nvim', 'mason-lspconfig.nvim',
                     'sprite.nvim', 'svgtree.nvim', 'scm.nvim'):
            source = SPRITE if name == 'sprite.nvim' else CACHE / name
            if not source.is_dir():
                raise RuntimeError(f'Missing plugin cache: {source}')
            shutil.copytree(source, cls.plugins / name, ignore=shutil.ignore_patterns('.git'))

    @classmethod
    def tearDownClass(cls):
        cls.profile.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vsvim-minimap-')
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, NVIM_APPNAME='vsvim', VSVIM_ROOT=str(ROOT))
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            self.env[f'XDG_{kind}_HOME'] = str(self.root / kind.lower())
        data = self.root / 'data/vsvim'
        data.mkdir(parents=True)
        shutil.copytree(self.plugins, data / 'lazy')
        self.config = self.root / 'config/vsvim'
        self.config.mkdir(parents=True)
        self.user('')
        self.file = self.root / 'fixture.txt'
        self.file.write_text('word first line\n' + '\n'.join(f'word row {i}' for i in range(2, 1001)) + '\n')
        self.git('init', '-q')
        self.git('add', 'fixture.txt')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
        self.observed = self.root / 'observed.json'
        self.init = self.root / 'init.lua'
        self.init.write_text('''
vim.opt.rtp:prepend(vim.env.VSVIM_ROOT)
_G.jobs={source=0,git=0,cancel=0,stop=0}
local source=require('vsvim.minimap.source')
local rows=source.rows
source.rows=function(...)
 jobs.source=jobs.source+1
 local cancel=rows(...)
 return function() jobs.cancel=jobs.cancel+1; cancel() end
end
for _,name in ipairs({'vsvim.minimap.git','vsvim.minimap.worker'}) do
 local module=require(name)
 local watch=module.watch
 module.watch=function(...)
  jobs.git=jobs.git+1
  local stop=watch(...)
  return function() jobs.stop=jobs.stop+1; stop() end
 end
end
dofile(vim.env.VSVIM_ROOT..'/init.lua')
vim.api.nvim_clear_autocmds({group='VSVimLsp',event='UIEnter'})
vim.o.swapfile=false
local function observe()
 local p=require('vsvim.minimap').provider()
 local value={command=vim.fn.exists(':VSVimMinimapToggle'),enabled=vim.g.vsvim_minimap,
   jobs=jobs,target=p.target() or vim.NIL,width=vim.api.nvim_win_get_width(0),
   line=vim.api.nvim_get_current_line(),mode=vim.fn.mode()}
 local path=vim.env.VSVIM_OBSERVED
 vim.fn.writefile({vim.json.encode(value)},path..'.tmp')
 vim.uv.fs_rename(path..'.tmp',path)
 vim.defer_fn(observe,20)
end
vim.defer_fn(observe,20)
''')
        self.env['VSVIM_OBSERVED'] = str(self.observed)
        self.process = self.host = self.nvim = None

    def git(self, *args):
        subprocess.check_call(['git', '-C', str(self.root), *args], stdout=subprocess.DEVNULL)

    def user(self, text):
        (self.config / 'user.lua').write_text('vim.g.vsvim_auto_explorer=false\n' + text)

    def snapshot(self):
        try:
            return json.loads(self.observed.read_text())
        except (FileNotFoundError, ValueError):
            return {}

    def wait(self, predicate):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.02)
        self.fail(f'timed out: {self.snapshot()}')

    def launch(self, features):
        path = Path(tempfile.mktemp(prefix='vsvim-mm-', suffix='.sock', dir='/tmp'))
        self.socket_path = path
        self.host = Host(path, features)
        env = dict(self.env, SPRITE_SURFACE_SOCKET=str(path), SPRITE_SURFACE_KEY='testkey', SPRITE_PANE='1')
        self.log = (self.root / 'adapter.log').open('w')
        self.process = subprocess.Popen([NVIM, '-l', str(SPRITE / 'lua/sprite/adapter.lua'),
                                         '-u', str(self.init), str(self.file)],
                                        cwd=self.root, env=env, stdout=self.log, stderr=self.log)
        self.wait(lambda: self.snapshot().get('command') == 2)

    def latest(self, kind):
        return next((m for m in reversed(self.host.messages)
                     if m.get('type') == 'minimap' and m.get('kind') == kind), None)

    def first_lines(self):
        return next((m['lines'] for m in reversed(self.host.messages)
                     if m.get('type') == 'minimap' and m.get('kind') == 'lines' and m['offset'] == 0), [])

    def tearDown(self):
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
            self.socket_path.unlink(missing_ok=True)
        if self.nvim:
            try:
                self.nvim.command('qa!')
            except (EOFError, OSError):
                pass
            self.nvim.close()
        self.temp.cleanup()

    def test_supported_setup_live_layers_toggle_and_window_identity(self):
        self.launch(['grid-minimap-v1', 'grid-tabs-v1'])
        self.wait(lambda: self.latest('state') is not None)
        self.assertEqual(self.first_lines()[0]['text'], 'word first line')
        self.host.command("syntax on | setfiletype lua | lua vim.api.nvim_set_hl(0,'String',{fg='#12ab34'}); vim.api.nvim_buf_set_lines(0,0,1,false,{'local x = \"word\"'})")
        self.wait(lambda: any(row['spans'] for m in self.host.messages if m.get('kind') == 'lines'
                              for row in m['lines']))
        self.wait(lambda: bool(self.latest('state')['changes']))
        self.host.send(dict(type='input', text='gg0v4l'))
        self.wait(lambda: self.latest('state')['selection'] is not None)
        target = self.latest('state')['target']
        self.host.send(dict(type='input', key='escape'))
        self.host.command('vnew | setlocal buftype=nofile')
        self.wait(lambda: self.snapshot().get('line') == '' and self.snapshot().get('target', {}).get('target') == target)
        self.host.command("enew | setlocal buftype= | call setline(1,'different file')")
        self.wait(lambda: self.latest('state')['target'] != target)
        self.assertIsNone(self.latest('state')['selection'])
        self.host.command('VSVimMinimapToggle')
        self.wait(lambda: self.latest('hide') is not None and self.snapshot().get('enabled') is False)
        self.assertIsNone(self.snapshot()['target'])
        jobs = self.snapshot()['jobs']
        self.assertGreater(jobs['stop'], 0)
        self.host.command("call setline(1,'current text')")
        self.wait(lambda: self.snapshot().get('line') == 'current text')
        self.assertEqual(self.snapshot()['jobs'], jobs)
        self.host.command('VSVimMinimapToggle')
        self.wait(lambda: self.first_lines()[0]['text'] == 'current text' and self.snapshot().get('enabled') is True)
        self.assertTrue(self.snapshot()['enabled'])

    def test_statusline_spans_minimap_and_tracks_editor_state(self):
        self.launch(['grid-minimap-v1', 'grid-tabs-v1', 'grid-footer-v1'])

        def footer():
            return next((m for m in reversed(self.host.messages)
                         if m.get('type') == 'footer' and m.get('cols') == 120), None)

        self.host.send(dict(type='resize', width=800, height=480,
                            cols=100, rows=30, footer_cols=120))
        self.wait(lambda: footer() is not None)
        bar = footer()
        text = ''.join(cell[0] * (cell[2] if len(cell) > 2 else 1)
                       for cell in bar['cells'])
        self.assertEqual(len(text), 120)
        self.assertIn('NORMAL', text)
        self.assertTrue(text.endswith('text  '), text)
        self.assertEqual(bar['grid_cols'], 100)
        self.assertEqual(bar['grid_rows'], 30)
        self.assertEqual(len(bar['source']), 100)
        self.assertEqual(self.snapshot()['width'], 100)
        self.host.send(dict(type='input', text='j'))
        self.wait(lambda: 'Ln 2,' in ''.join(cell[0] for cell in footer()['cells']))
        self.host.command('set laststatus=2')
        self.wait(lambda: any(m.get('type') == 'footer' and m.get('visible') is False
                              for m in self.host.messages))

    def test_old_host_does_no_work_or_minimap_messages(self):
        self.launch(['grid-tabs-v1'])
        time.sleep(.2)
        self.assertEqual(self.snapshot()['jobs'], dict(source=0, git=0, cancel=0, stop=0))
        self.assertIsNone(self.latest('begin'))
        self.assertFalse(any(m.get('type') == 'footer' for m in self.host.messages))
        self.assertEqual(self.snapshot()['width'], 100)
        self.host.command('VSVimMinimapToggle | VSVimMinimapToggle')
        time.sleep(.2)
        self.assertTrue(self.snapshot()['enabled'])
        self.assertEqual(self.snapshot()['jobs']['source'], 0)

    def test_user_setting_disables_before_native_attachment(self):
        self.user('vim.g.vsvim_minimap=false\n')
        self.launch(['grid-minimap-v1'])
        time.sleep(.2)
        self.assertEqual(self.snapshot()['jobs']['source'], 0)
        self.assertEqual(self.snapshot()['jobs']['git'], 0)
        self.assertIsNone(self.latest('begin'))
        self.host.command('VSVimMinimapToggle')
        self.wait(lambda: self.latest('commit') is not None)

    def test_headless_and_terminal_ui_do_no_work(self):
        self.nvim = pynvim.attach('child', argv=['/usr/bin/env', *[f'{k}={v}' for k, v in self.env.items()],
                                              NVIM, '--embed', '--headless', '-u', str(self.init), str(self.file)])
        self.assertEqual(self.nvim.funcs.exists(':VSVimMinimapToggle'), 2)
        self.assertEqual(self.nvim.exec_lua('return jobs.source+jobs.git'), 0)
        self.nvim.ui_attach(100, 30, rgb=True)
        self.nvim.command('VSVimMinimapToggle | VSVimMinimapToggle')
        self.assertEqual(self.nvim.exec_lua('return jobs.source+jobs.git'), 0)
        self.assertEqual(self.nvim.current.window.width, 100)

    def test_unsupported_initial_buffer_does_no_jobs(self):
        self.user("vim.api.nvim_create_autocmd('BufReadPost',{once=true,callback=function() vim.bo.buftype='nofile' end})\n")
        self.launch(['grid-minimap-v1'])
        time.sleep(.2)
        self.assertEqual(self.snapshot()['jobs']['source'] + self.snapshot()['jobs']['git'], 0)
        self.assertIsNone(self.latest('begin'))


if __name__ == '__main__':
    unittest.main()
