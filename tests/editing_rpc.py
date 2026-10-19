"""Run with: uv run --with pynvim python tests/editing_rpc.py."""
import os
import signal
from pathlib import Path
import tempfile
import threading
import time
import unittest

import pynvim

ROOT = Path(__file__).resolve().parents[1]


class EditingTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='vsvim-editing-')
        self.file = Path(self.directory.name) / 'document.txt'
        self.file.write_text('original\nsecond line\n')
        self.start_editor()

    def start_editor(self, swap=False, open_file=True):
        self.nvim = pynvim.attach('child', argv=[
            '/usr/bin/env', f'XDG_STATE_HOME={self.directory.name}/state',
            f'XDG_CONFIG_HOME={self.directory.name}/config',
            str(ROOT / 'bin/vsvim'), '--embed', '--headless',
            *([] if swap else ['-n']),
            '--cmd', 'let g:vsvim_auto_explorer = v:false',
            *([str(self.file)] if open_file else []),
        ])
        self.nvim.ui_attach(100, 30, rgb=True)
        self.nvim.exec_lua('''
_G.test_clipboard = {{'external text'}, 'v'}
local function copy(lines, kind) _G.test_clipboard = {lines, kind} end
local function paste() return _G.test_clipboard end
vim.g.clipboard = {
  name = 'test clipboard', cache_enabled = 0,
  copy = {['+'] = copy, ['*'] = copy},
  paste = {['+'] = paste, ['*'] = paste},
}
''')

    def tearDown(self):
        try:
            self.nvim.input('<Esc><CR>')
            self.nvim.command('qa!')
        except (EOFError, OSError):
            pass
        self.nvim.close()
        self.directory.cleanup()

    def wait_for(self, condition, message):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.01)
        self.fail(message)

    def wait_for_prompt(self, expected='Save changes to'):
        seen = []
        def strings(value):
            if isinstance(value, str):
                return value
            if isinstance(value, (list, tuple)):
                return ''.join(strings(item) for item in value)
            return ''
        def notification(name, args):
            seen.append(strings(args))
            text = ''.join(seen)
            if expected in text or 'E37:' in text or 'E162:' in text or 'E32:' in text:
                self.nvim.stop_loop()
        timer = threading.Timer(5, lambda: self.nvim.async_call(self.nvim.stop_loop))
        timer.start()
        try:
            self.nvim.run_loop(None, notification)
        finally:
            timer.cancel()
        self.assertIn(expected, ''.join(seen))

    def test_quit_asks_to_save_and_cancel_preserves_edits(self):
        self.nvim.current.buffer[0] = 'unsaved edit'
        self.nvim.input(':qa<CR>')
        self.wait_for_prompt()
        self.nvim.input('c')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n', 'Cancel should return to editing')
        self.assertEqual(self.nvim.current.buffer[0], 'unsaved edit')
        self.assertEqual(self.file.read_text(), 'original\nsecond line\n')

    def test_copy_cut_and_paste_selection_use_system_clipboard(self):
        self.nvim.input('gg0v4l<D-c>')
        self.wait_for(lambda: self.nvim.exec_lua('return _G.test_clipboard[1]') == ['origi'],
                      'Cmd-C should copy the selection')
        self.nvim.input('<Esc>gg0v4l<D-x>')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'nal', 'Cmd-X should cut the selection')
        self.nvim.exec_lua("_G.test_clipboard = {{'replacement'}, 'v'}")
        self.nvim.input('gg0v2l<D-v>')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'replacement',
                      'Cmd-V should replace the selection')
        self.assertEqual(self.nvim.exec_lua('return _G.test_clipboard[1]'), ['replacement'])
        for key in ('u', 'y', 'p', 'd'):
            self.assertEqual(self.nvim.funcs.maparg(key, 'n'), '', 'default Vim keys stay available')

    def test_shortcuts_work_while_typing_and_select_all(self):
        self.nvim.input('A added<D-z>')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'original',
                      'Cmd-Z should undo typing')
        self.assertEqual(self.nvim.funcs.mode(), 'i', 'Undo should keep Insert mode')
        self.nvim.input('<D-c>')
        self.wait_for(lambda: self.nvim.exec_lua('return _G.test_clipboard[1][1]') == 'original',
                      'Copy with no selection should copy the current line')
        self.nvim.input('<D-x>')
        self.wait_for(lambda: self.nvim.current.buffer[:] == ['second line'],
                      'Cut with no selection should cut the current line')
        self.assertEqual(self.nvim.funcs.mode(), 'i')
        self.nvim.current.window.cursor = (1, 0)
        self.nvim.exec_lua("_G.test_clipboard = {{'prefix '}, 'v'}")
        self.nvim.input('<D-v>')
        self.wait_for(lambda: self.nvim.current.buffer[0].startswith('prefix '),
                      'Cmd-V should insert clipboard text while typing')
        self.nvim.input('<D-a>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'V', 'Cmd-A should select the whole file')
        self.nvim.input('<D-c>')
        self.wait_for(lambda: self.nvim.exec_lua('return _G.test_clipboard[1]')[:-1] == self.nvim.current.buffer[:],
                      'Copy after Select All should include the whole file')

    def test_save_while_typing_and_save_as_for_unnamed_file(self):
        self.nvim.input('A saved<D-s>')
        self.wait_for(lambda: self.file.read_text().startswith('original saved\n'),
                      'Cmd-S should save while typing')
        self.assertEqual(self.nvim.funcs.mode(), 'i')
        self.nvim.input('<Esc>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n', 'leave Insert mode')
        self.nvim.command('enew')
        self.nvim.current.buffer[:] = ['new document']
        target = Path(self.directory.name) / 'new document.txt'
        self.nvim.input('<D-s>')
        self.wait_for_prompt('Save as:')
        self.nvim.input(str(target) + '<CR>')
        self.wait_for(target.exists, 'Cmd-S should ask for a filename and save the unnamed file')
        self.assertEqual(target.read_text(), 'new document\n')
        self.assertEqual(Path(self.nvim.current.buffer.name), target.resolve())

    def test_saved_undo_history_survives_restart(self):
        self.nvim.current.buffer[0] = 'saved edit'
        self.nvim.command('write')
        try:
            self.nvim.command('quit')
        except EOFError:
            pass
        self.nvim.close()
        self.start_editor()
        self.nvim.input('u')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'original',
                      'Undo history should survive saving and restarting VSVim')

    def test_unsaved_edits_can_be_recovered_after_crash(self):
        try:
            self.nvim.command('quit')
        except EOFError:
            pass
        self.nvim.close()
        self.start_editor(swap=True)
        self.nvim.current.buffer[0] = 'recover this unsaved edit'
        self.nvim.command('preserve')
        self.assertTrue(self.nvim.funcs.swapname(self.nvim.current.buffer.number))
        os.kill(self.nvim.funcs.getpid(), signal.SIGKILL)
        try:
            self.nvim.eval('1')
        except EOFError:
            pass
        self.nvim.close()
        self.start_editor(swap=True, open_file=False)
        self.nvim.command('enew')
        self.nvim.command('silent recover ' + self.nvim.funcs.fnameescape(str(self.file)))
        self.assertEqual(self.nvim.current.buffer[0], 'recover this unsaved edit')
        self.assertTrue(self.nvim.current.buffer.options['modified'])
        self.assertEqual(self.file.read_text(), 'original\nsecond line\n')

    def test_save_and_discard_quit_choices(self):
        for answer, expected in [('y', 'saved at quit'), ('n', 'original')]:
            with self.subTest(answer=answer):
                self.nvim.current.buffer[0] = 'saved at quit'
                self.nvim.input(':qa<CR>')
                self.wait_for_prompt()
                self.nvim.input(answer)
                with self.assertRaises(EOFError):
                    self.nvim.eval('1')
                self.nvim.close()
                self.assertEqual(self.file.read_text().splitlines()[0], expected)
                self.file.write_text('original\nsecond line\n')
                self.start_editor()

    def test_tab_save_handles_unnamed_cancel_and_failed_write(self):
        self.nvim.command('enew')
        buffer = self.nvim.current.buffer.number
        self.nvim.current.buffer[:] = ['unfinished']
        self.nvim.exec_lua('''
vim.ui.select = function(_, _, callback) callback('Save and close') end
vim.ui.input = function(_, callback) callback(nil) end
require('vsvim.tabs').close(...)
''', buffer)
        self.assertTrue(self.nvim.api.buf_is_valid(buffer), 'Cancel Save As keeps the tab')
        self.assertTrue(self.nvim.api.get_option_value('modified', {'buf': buffer}))
        target = str(Path(self.directory.name) / 'missing parent/file.txt')
        self.nvim.exec_lua('''
local buffer, path = ...
vim.notify = function(message) _G.save_error = message end
vim.ui.input = function(_, callback) callback(path) end
require('vsvim.tabs').close(buffer)
''', buffer, target)
        self.assertTrue(self.nvim.api.buf_is_valid(buffer), 'A failed save keeps the tab')
        self.assertTrue(self.nvim.api.get_option_value('modified', {'buf': buffer}))
        self.assertIn('E212', self.nvim.exec_lua('return _G.save_error'))
        self.nvim.api.buf_set_name(buffer, '')
        target = Path(self.directory.name) / 'tab saved.txt'
        self.nvim.exec_lua('''
local buffer, path = ...
vim.ui.input = function(_, callback) callback(path) end
require('vsvim.tabs').close(buffer)
''', buffer, str(target))
        self.assertFalse(self.nvim.api.buf_is_valid(buffer))
        self.assertEqual(target.read_text(), 'unfinished\n')

if __name__ == '__main__':
    unittest.main()
