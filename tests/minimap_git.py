import pathlib
import subprocess
import tempfile
import unittest
import pynvim

ROOT = str(pathlib.Path(__file__).resolve().parents[1])
NVIM = '/Users/davidlee/.local/nvim-nightly/bin/nvim'

class MinimapGit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self.tmp.name)
        self.git('init', '-q')
        self.file = self.repo / 'file.txt'
        self.file.write_text('one\ntwo\nthree\n')
        self.git('add', '.')
        self.commit()
        self.nvim = pynvim.attach('child', argv=[NVIM, '--clean', '--embed', '--headless'])
        self.nvim.exec_lua('vim.opt.runtimepath:prepend(...)', ROOT)
        self.nvim.command('edit ' + self.nvim.funcs.fnameescape(str(self.file)))
        self.nvim.exec_lua("_G.result=nil; _G.stop=require('vsvim.minimap.git').watch(0,function(r) _G.result=r end)")
        self.wait()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.STDOUT).decode()

    def commit(self):
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')

    def wait(self, expected=None):
        expression = '_G.result ~= nil' if expected is None else 'vim.deep_equal(_G.result and _G.result.changes, ...)'
        ok = self.nvim.exec_lua('local expected=...; return vim.wait(5000,function() return ' + expression.replace('...', 'expected') + ' end,20)', expected)
        self.assertTrue(ok, self.nvim.exec_lua('return _G.result'))
        return self.nvim.exec_lua('return _G.result.changes')

    def refresh(self):
        self.nvim.exec_lua("vim.api.nvim_exec_autocmds('FocusGained',{})")

    def tearDown(self):
        if hasattr(self, 'nvim'):
            try:
                self.nvim.exec_lua('if _G.stop then _G.stop() end')
                self.nvim.command('qa!')
            except (EOFError, OSError):
                pass
            self.nvim.close()
        self.tmp.cleanup()

    def test_head_baseline_survives_save_stage(self):
        self.nvim.current.buffer[1] = 'TWO'
        groups = [{'start': 2, 'end': 2, 'kind': 'modified'}]
        self.wait(groups)
        self.nvim.command('write')
        self.wait(groups)
        self.git('add', '.')
        self.refresh()
        self.wait(groups)
        self.commit()
        self.refresh()
        self.wait([])

    def test_deletion_boundaries(self):
        for lines, boundary in [(['two', 'three'], 1), (['one', 'two'], 2), ([''], 1)]:
            self.nvim.current.buffer[:] = lines
            self.wait([{'start': boundary, 'end': boundary, 'kind': 'deleted'}])

    def test_untracked_unicode_and_shell_metacharacters(self):
        name = str(self.repo / '新 $(touch nope); file.txt')
        self.nvim.command('file ' + self.nvim.funcs.fnameescape(name))
        self.refresh()
        self.wait([{'start': 1, 'end': 3, 'kind': 'added'}])
        self.assertFalse((self.repo / 'nope').exists())

    def test_non_git_and_cancel(self):
        with tempfile.TemporaryDirectory() as other:
            self.nvim.exec_lua('_G.stop(); _G.result=nil')
            self.nvim.command('edit! ' + self.nvim.funcs.fnameescape(str(pathlib.Path(other) / 'plain')))
            self.nvim.exec_lua("_G.stop=require('vsvim.minimap.git').watch(0,function(r) _G.result=r end)")
            self.wait([])
            self.assertTrue(self.nvim.exec_lua('return _G.result.error ~= nil'))
            self.nvim.exec_lua('_G.stop(); _G.result=nil')
            self.refresh()
            self.nvim.exec_lua('vim.wait(100)')
            self.assertIsNone(self.nvim.exec_lua('return _G.result'))

    def test_head_refresh_without_editor_event(self):
        self.nvim.current.buffer[1] = 'TWO'
        self.wait([{'start': 2, 'end': 2, 'kind': 'modified'}])
        self.file.write_text('one\nTWO\nthree\n')
        self.git('add', '.')
        self.commit()
        self.wait([])

    def test_worktree_git_directory(self):
        linked = self.repo / 'linked'
        self.git('worktree', 'add', '-qb', 'linked-branch', str(linked))
        self.nvim.exec_lua('_G.stop(); _G.result=nil')
        self.nvim.command('edit! ' + self.nvim.funcs.fnameescape(str(linked / 'file.txt')))
        self.nvim.exec_lua("_G.stop=require('vsvim.minimap.git').watch(0,function(r) _G.result=r end)")
        self.wait([])
        self.nvim.current.buffer[1] = 'TWO'
        self.wait([{'start': 2, 'end': 2, 'kind': 'modified'}])
        (linked / 'file.txt').write_text('one\nTWO\nthree\n')
        subprocess.check_call(['git', '-C', str(linked), 'add', '.'])
        subprocess.check_call(['git', '-C', str(linked), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'worktree'])
        self.git('pack-refs', '--all')
        self.wait([])

    def test_switch_during_read(self):
        self.nvim.exec_lua("_G.stop(); _G.result=nil; local cancel=require('vsvim.minimap.git').watch(0,function(r) _G.result=r end); cancel(); vim.cmd('enew'); vim.wait(150)")
        self.assertIsNone(self.nvim.exec_lua('return _G.result'))

if __name__ == '__main__':
    unittest.main()
