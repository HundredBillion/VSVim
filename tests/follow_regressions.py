"""Verify Follow reloads saves, preserves undo, and resumes after browsing."""
import os
from pathlib import Path
import tempfile
import time
import unittest

import pynvim

ROOT = Path(__file__).resolve().parents[1]
NVIM = os.environ.get('VSVIM_NVIM', str(Path.home() / '.local/nvim-nightly/bin/nvim'))


class FollowRegressions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='follow-regression-')
        self.root = Path(self.temp.name).resolve()
        self.file = self.root / 'main.lua'
        self.editor = pynvim.attach('child', argv=[NVIM, '--embed', '--headless', '-u', 'NONE'])
        self.editor.exec_lua('vim.opt.runtimepath:prepend(...); if vim.env.VSVIM_FOLLOW_SOURCE then vim.opt.runtimepath:prepend(vim.env.VSVIM_FOLLOW_SOURCE) end; require("vsvim.follow").setup()', str(ROOT))
        self.editor.command('cd ' + self.editor.funcs.fnameescape(str(self.root)))

    def wait(self, predicate):
        deadline = time.monotonic()+5
        while time.monotonic()<deadline:
            if predicate():
                return
            time.sleep(.02)
        self.fail('condition timed out')

    def open_follow(self):
        self.editor.command('edit ' + self.editor.funcs.fnameescape(str(self.file)))
        self.editor.command('VSVimFollowOn')
        self.wait(lambda:self.editor.exec_lua('return require("vsvim.follow").status().ready'))

    def test_timestamp_preserving_rewrite_reloads_text(self):
        self.file.write_text('original\n')
        self.open_follow()
        stat = self.file.stat()
        self.file.write_text('external\n')
        os.utime(self.file, ns=(stat.st_atime_ns,stat.st_mtime_ns))
        self.wait(lambda:self.editor.current.buffer[0]=='external')

    def test_external_reload_keeps_long_buffer_undo(self):
        self.file.write_text(''.join(f'line {i}\n' for i in range(10001)))
        self.editor.command('edit ' + self.editor.funcs.fnameescape(str(self.file)))
        self.editor.current.buffer[0] = 'saved developer edit'
        self.editor.command('write')
        old_sequence = self.editor.funcs.undotree()['seq_cur']
        self.editor.command('VSVimFollowOn')
        self.wait(lambda:self.editor.exec_lua('return require("vsvim.follow").status().ready'))
        text = self.file.read_text().replace('line 10000\n','external\n')
        self.file.write_text(text)
        self.wait(lambda:self.editor.current.buffer[-1]=='external')
        self.assertEqual(self.editor.options['undoreload'],10000)
        self.assertTrue(self.editor.funcs.undotree()['entries'])
        self.editor.command('VSVimFollowOff')
        self.editor.command('undo')
        self.assertEqual(self.editor.current.buffer[-1],'line 10000')
        self.editor.command('undo')
        self.assertEqual(self.editor.current.buffer[0],'line 0')
        self.assertGreater(old_sequence,0)

    def test_scrolling_without_cursor_movement_keeps_follow(self):
        self.file.write_text(''.join(f'line {i}\n' for i in range(200)))
        self.open_follow()
        self.editor.command('VSVimFollowOff')
        self.editor.current.window.cursor=(50,0)
        self.editor.command('normal! zz')
        cursor = self.editor.current.window.cursor
        self.editor.command('VSVimFollowOn')
        self.wait(lambda:self.editor.exec_lua('return require("vsvim.follow").status().ready'))
        self.editor.command('normal! ' + chr(5))
        self.assertEqual(self.editor.current.window.cursor,cursor)
        self.assertTrue(self.editor.exec_lua('return require("vsvim.follow").status().enabled'))
        self.file.write_text(self.file.read_text().replace('line 199\n','external\n'))
        self.wait(lambda:self.editor.current.buffer[-1]=='external')
        self.assertTrue(self.editor.exec_lua('return require("vsvim.follow").status().enabled'))

    def inject_at_read_completion(self, action):
        self.editor.exec_lua("""
            local original = vim.uv.fs_read
            local action = ...
            vim.uv.fs_read = function(fd, size, offset, callback)
              if type(callback) ~= 'function' then return original(fd,size,offset,callback) end
              return original(fd,size,offset,function(err,bytes)
                vim.uv.fs_read = original
                vim.schedule(function()
                  assert(loadstring(action))()
                  callback(err,bytes)
                end)
              end)
            end
        """,action)

    def test_root_change_during_read_rejects_old_root_edit(self):
        new_root = self.root / 'new-project'
        new_root.mkdir()
        self.file.write_text('original\n')
        self.editor.exec_lua("""
            vim.g.follow_test_root = ...
            package.loaded.svgtree = {root=function() return vim.g.follow_test_root end}
        """,str(self.root))
        self.open_follow()
        self.inject_at_read_completion('vim.g.follow_test_root = ' + repr(str(new_root)))
        self.file.write_text('external\n')
        self.wait(lambda:self.editor.exec_lua('return require("vsvim.follow").status().root')==str(new_root))
        self.assertEqual(self.editor.current.buffer[0],'original')

    def test_manual_navigation_during_read_resumes_at_update(self):
        self.file.write_text(''.join(f'line {i}\n' for i in range(200)))
        self.open_follow()
        self.inject_at_read_completion('vim.api.nvim_win_set_cursor(0,{50,0})')
        self.file.write_text(self.file.read_text().replace('line 199\n','external\n'))
        self.wait(lambda:self.editor.current.buffer[-1]=='external')
        self.assertTrue(self.editor.exec_lua('return require("vsvim.follow").status().enabled'))
        self.assertEqual(self.editor.current.window.cursor,(1,0))

    def test_command_entry_during_read_defers_instead_of_losing_change(self):
        self.file.write_text('original\n')
        self.open_follow()
        self.editor.exec_lua("""
            local original = vim.uv.fs_read
            vim.uv.fs_read = function(fd,size,offset,callback)
              if type(callback) ~= 'function' then return original(fd,size,offset,callback) end
              return original(fd,size,offset,function(err,bytes)
                vim.uv.fs_read = original
                vim.schedule(function() _G.follow_release=function() callback(err,bytes) end end)
              end)
            end
        """)
        self.file.write_text('external\n')
        self.wait(lambda:self.editor.exec_lua('return _G.follow_release ~= nil'))
        self.editor.input(':')
        self.wait(lambda:self.editor.api.get_mode()['mode']=='c')
        self.editor.exec_lua('_G.follow_release()')
        time.sleep(.15)
        self.assertEqual(self.editor.current.buffer[0],'original')
        self.editor.input('\x1b')
        self.wait(lambda:self.editor.current.buffer[0]=='external')
        self.assertTrue(self.editor.exec_lua('return require("vsvim.follow").status().enabled'))

    def test_follow_from_wipe_on_hide_sidebar_preserves_sidebar_and_focus(self):
        self.file.write_text('main editor\n')
        target = self.root / 'other.lua'
        target.write_text('first\noriginal\n')
        self.editor.command('edit ' + self.editor.funcs.fnameescape(str(self.file)))
        self.editor.command('badd ' + self.editor.funcs.fnameescape(str(target)))
        editor_window = self.editor.current.window.handle
        sidebar = self.editor.exec_lua("""
            vim.cmd('topleft vsplit')
            local win = vim.api.nvim_get_current_win()
            local buf = vim.api.nvim_create_buf(false,true)
            vim.api.nvim_win_set_buf(win,buf)
            vim.bo[buf].buftype='nofile'
            vim.bo[buf].bufhidden='wipe'
            vim.bo[buf].filetype='svgtree'
            vim.api.nvim_buf_set_lines(buf,0,-1,false,{'SVGTree project files'})
            return {win=win,buf=buf}
        """)
        self.editor.command('VSVimFollowOn')
        self.wait(lambda:self.editor.exec_lua('return require("vsvim.follow").status().ready'))
        target.write_text('first\nexternal\n')
        self.wait(lambda:self.editor.api.win_get_buf(editor_window).name==str(target))
        self.assertTrue(self.editor.api.buf_is_valid(sidebar['buf']))
        self.assertEqual(self.editor.api.win_get_buf(sidebar['win']).number,sidebar['buf'])
        self.assertEqual(self.editor.api.buf_get_lines(sidebar['buf'],0,-1,False),['SVGTree project files'])
        self.assertEqual(self.editor.current.window.handle,sidebar['win'])
        self.assertTrue(self.editor.exec_lua('return require("vsvim.follow").status().enabled'))

    def tearDown(self):
        try:
            self.editor.command('qa!')
        except (EOFError,OSError):
            pass
        self.editor.close()
        self.temp.cleanup()


if __name__=='__main__':
    unittest.main()
