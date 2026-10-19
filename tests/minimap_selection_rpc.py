"""Real embedded UI selection checks: uv run --with pynvim python tests/minimap_selection_rpc.py."""
import os
from pathlib import Path
import time
import unittest
import pynvim

ROOT = Path(__file__).resolve().parents[1]
NVIM = os.environ.get('VSVIM_NVIM', '/Users/davidlee/.local/nvim-nightly/bin/nvim')


class SelectionTest(unittest.TestCase):
    def setUp(self):
        self.nvim = pynvim.attach('child', argv=[NVIM, '--clean', '--embed', '-n'])
        self.nvim.ui_attach(100, 30, rgb=True)
        self.nvim.exec_lua('vim.opt.rtp:prepend(...); vim.o.mouse="a"; vim.o.swapfile=false', str(ROOT))
        self.original = ['word first line'] + [f'row {i} word' for i in range(2, 1001)]
        self.nvim.current.buffer[:] = self.original
        self.nvim.exec_lua("_G.selection = require('vsvim.minimap.selection')")

    def tearDown(self):
        try:
            self.nvim.command('qa!')
        except (EOFError, OSError):
            pass
        self.nvim.close()

    def wait_for(self, condition):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(.01)
        self.fail('selection condition timed out')

    def browse(self):
        self.nvim.exec_lua("selection.browse(0, {action='scroll',topline=500})")
        self.assertGreaterEqual(self.nvim.funcs.line('w0'), 490)

    def send(self, keys):
        self.nvim.exec_lua("selection.before_input({type='input',key=...})", keys)
        self.nvim.input(keys)

    def test_double_click_matches_literal_whole_words(self):
        self.nvim.current.buffer[:] = ['word word WORD sword word_', '-- word', 'word', ''] + ['padding'] * 995 + ['word']
        self.nvim.api.input_mouse('left', 'press', '2', 0, 0, 1)
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.assertEqual(self.nvim.exec_lua("return vim.fn.getregion(vim.fn.getpos('v'),vim.fn.getpos('.'),{type='v'})"), ['word'])
        self.nvim.exec_lua('selection.state(0)')
        self.wait_for(lambda: self.nvim.exec_lua('return selection.state(0).occurrences') == [1, 2, 3, 1000])
        self.assertEqual(self.nvim.exec_lua('return selection.state(0).word'), 'word')
        self.nvim.command('redraw')
        self.assertNotEqual(self.nvim.funcs.screenattr(2, 4), self.nvim.funcs.screenattr(2, 1))
        self.assertNotEqual(self.nvim.funcs.screenattr(1, 1), self.nvim.funcs.screenattr(1, 6))
        self.assertEqual(self.nvim.funcs.getreg('/'), '')

    def test_reversed_line_block_select_and_exclusive_yanks(self):
        cases = [('gg03lv3h', 'inclusive', 'word', 'v'),
                 ('gg0Vj', 'inclusive', 'word first line\nrow 2 word\n', 'V'),
                 ('gg0<C-v>j3l', 'inclusive', 'word\nrow ', '\x164'),
                 ('gg0v4l', 'exclusive', 'word', 'v'),
                 ('gg0v3l<C-g>', 'inclusive', 'word', 'v')]
        for keys, option, text, kind in cases:
            with self.subTest(keys=keys):
                self.nvim.input('<Esc>')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.nvim.options['selection'] = option
                self.nvim.input(keys)
                self.wait_for(lambda: self.nvim.funcs.mode() in ('v', 'V', '\x16', 's'))
                before = self.nvim.exec_lua("return {vim.fn.getpos('v'),vim.fn.getpos('.'),vim.fn.mode()}")
                self.browse()
                self.nvim.exec_lua("selection.before_input({type='input',key='y'})")
                self.assertEqual(self.nvim.exec_lua("return {vim.fn.getpos('v'),vim.fn.getpos('.'),vim.fn.mode()}"), before)
                if before[2] == 's':
                    self.nvim.input('<C-g>')
                    self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.nvim.input('y')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.assertEqual(self.nvim.funcs.getreg('"'), text)
                self.assertEqual(self.nvim.funcs.getregtype('"'), kind)

    def test_preserved_highlight_keeps_partial_tabs_and_empty_lines(self):
        self.nvim.current.buffer[:3] = ['\tword', '\tword', '']
        self.nvim.options['virtualedit'] = 'all'
        self.nvim.input('gg0<C-v>j2l')
        self.wait_for(lambda: self.nvim.funcs.mode() == '\x16')
        self.browse()
        self.nvim.exec_lua("selection.browse(0,{action='scroll',topline=1})")
        self.nvim.command('redraw!')
        self.assertNotEqual(self.nvim.funcs.screenattr(1, 2), self.nvim.funcs.screenattr(1, 5))
        self.send('<Esc>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
        self.nvim.input('gg2jV')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'V')
        self.browse()
        self.nvim.exec_lua("selection.browse(0,{action='scroll',topline=3})")
        self.nvim.command('redraw!')
        self.assertNotEqual(self.nvim.funcs.screenattr(1, 1), self.nvim.funcs.screenattr(2, 1))

    def test_unicode_tabs_virtual_columns_and_all_select_modes(self):
        self.nvim.current.buffer[:2] = ['\t猫 café word', '\tx café word']
        self.nvim.options['virtualedit'] = 'all'
        cases = ['gg0v2l', 'gg0<C-v>j2l', 'gg09lv3h',
                 'gg0Vj<C-g>', 'gg0<C-v>j2l<C-g>', 'gg020lv3h', 'gg0<C-v>j$', 'gg03l<C-v>j0']
        for keys in cases:
            with self.subTest(keys=keys):
                self.nvim.input('<Esc>' + keys)
                self.wait_for(lambda: self.nvim.funcs.mode() in ('v', 'V', '\x16', 's', 'S', '\x13'))
                before = self.nvim.exec_lua("return {vim.fn.getpos('v'),vim.fn.getpos('.'),vim.fn.mode()}")
                if before[2] in ('s', 'S', '\x13'):
                    self.nvim.input('<C-g>')
                    self.wait_for(lambda: self.nvim.funcs.mode() in ('v', 'V', '\x16'))
                self.nvim.input('y')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                baseline = self.nvim.funcs.getreg('"', 1, 1)
                baseline_type = self.nvim.funcs.getregtype('"')
                self.nvim.input(keys)
                self.wait_for(lambda: self.nvim.funcs.mode() == before[2])
                self.browse()
                self.nvim.exec_lua("selection.before_input({type='input',key='y'})")
                self.assertEqual(self.nvim.exec_lua("return {vim.fn.getpos('v'),vim.fn.getpos('.'),vim.fn.mode()}"), before)
                if before[2] in ('s', 'S', '\x13'):
                    self.nvim.input('<C-g>')
                    self.wait_for(lambda: self.nvim.funcs.mode() in ('v', 'V', '\x16'))
                self.nvim.input('y')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.assertEqual(self.nvim.funcs.getreg('"', 1, 1), baseline)
                self.assertEqual(self.nvim.funcs.getregtype('"'), baseline_type)

    def test_browse_preserves_registers_search_and_undo(self):
        self.nvim.funcs.setreg('"', 'keep')
        self.nvim.funcs.setreg('/', 'search')
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        undo = self.nvim.funcs.undotree()
        search_options = [self.nvim.options[k] for k in ('ignorecase', 'smartcase', 'hlsearch')]
        self.browse()
        self.nvim.exec_lua("selection.browse(0,{action='reveal',line=800})")
        self.assertEqual(self.nvim.funcs.getreg('"'), 'keep')
        self.assertEqual(self.nvim.funcs.getreg('/'), 'search')
        self.assertEqual(self.nvim.funcs.undotree(), undo)
        self.assertEqual([self.nvim.options[k] for k in ('ignorecase', 'smartcase', 'hlsearch')], search_options)
        self.assertEqual(self.nvim.current.buffer[:], self.original)

    def test_delete_change_and_native_paste_restore_selection(self):
        for operation, expected in [('d', ' first line'), ('cNEW<Esc>', 'NEW first line')]:
            with self.subTest(operation=operation):
                self.nvim.current.buffer[:] = self.original
                self.nvim.input('gg0v3l')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.browse()
                self.send(operation)
                self.wait_for(lambda: self.nvim.current.buffer[0] == expected)
                self.assertEqual(self.nvim.current.buffer[499], self.original[499])
        self.nvim.current.buffer[:] = self.original
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.nvim.exec_lua("selection.before_input({type='paste'}); vim.api.nvim_paste('PASTE',true,-1)")
        self.assertEqual(self.nvim.current.buffer[0], 'PASTE first line')

    def test_command_shortcuts_use_restored_selection(self):
        self.nvim.exec_lua('''require('vsvim.editing').setup()
_G.clip = {{'replacement'},'v'}
vim.g.clipboard = {name='test',cache_enabled=0,
 copy={['+']=function(lines,kind) _G.clip={lines,kind} end,['*']=function() end},
 paste={['+']=function() return _G.clip end,['*']=function() return _G.clip end}}
''')
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.send('<D-c>')
        self.wait_for(lambda: self.nvim.exec_lua('return _G.clip[1]') == ['word'])
        self.browse()
        self.send('<D-x>')
        self.wait_for(lambda: self.nvim.current.buffer[0] == ' first line')
        self.nvim.input('gg0v5l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.nvim.exec_lua("_G.clip={{'replacement'},'v'}")
        self.browse()
        self.send('<D-v>')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'replacement line')
        for key in ('y', 'd', 'c'):
            self.assertEqual(self.nvim.funcs.maparg(key, 'n'), '')
            self.assertEqual(self.nvim.funcs.maparg(key, 'x'), '')

    def test_escape_click_and_external_edit_clear_preserved_selection(self):
        for event in [{'type': 'input', 'key': '<Esc>'}, {'type': 'mouse', 'action': 'press'}]:
            self.nvim.input('<Esc>gg0v3l')
            self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
            self.browse()
            self.nvim.exec_lua('selection.before_input(...)', event)
            self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))
            self.send('y')
            self.assertEqual(self.nvim.funcs.mode(), 'n')
        self.nvim.input('<Esc>gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.nvim.current.buffer[0] = 'changed externally'
        self.nvim.exec_lua("selection.before_input({type='input',key='y'})")
        self.assertEqual(self.nvim.funcs.mode(), 'n')
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))

    def test_provider_callbacks_and_stale_actions(self):
        self.nvim.exec_lua("_G.provider=require('vsvim.minimap').provider(); provider.next()")
        def ready():
            return self.nvim.exec_lua("for _=1,100 do provider.next() end; local t=provider.target(); return t and t.generation ~= nil and not t.busy")
        self.wait_for(ready)
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.nvim.exec_lua("local t=provider.target(); provider.dispatch({target=t.target,generation=t.generation+1,action='scroll',topline=500})")
        self.assertEqual(self.nvim.funcs.line('.'), 1)
        self.nvim.exec_lua("local t=provider.target(); provider.dispatch({target=t.target,generation=t.generation,action='scroll',topline=500})")
        self.assertGreaterEqual(self.nvim.funcs.line('w0'), 490)
        self.nvim.current.buffer[0] = 'external edit'
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))
        self.nvim.input('<Esc>gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.nvim.command('enew!')
        self.nvim.exec_lua("provider.before_input({type='input',key='y'})")
        self.assertEqual(self.nvim.funcs.mode(), 'n')
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))
        self.nvim.exec_lua('provider.stop()')

    def test_live_matching_tracks_keyword_rules_and_clears_on_mode_exit(self):
        self.nvim.current.buffer[:4] = ['word word-word', 'WORD word_', '-- word', 'word-word']
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.nvim.exec_lua('selection.state(0)')
        self.wait_for(lambda: self.nvim.exec_lua('return selection.state(0).occurrences') == [1, 3, 4] + list(range(5, 1001)))
        self.nvim.command('setlocal iskeyword+=-')
        self.wait_for(lambda: self.nvim.exec_lua('return selection.state(0).occurrences') == [1, 3] + list(range(5, 1001)))
        self.nvim.input('<Esc>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
        self.assertEqual(self.nvim.exec_lua('return selection.state(0).occurrences'), [])
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).word'))

    def test_select_typing_and_real_editor_click(self):
        self.nvim.input('gg0v3l<C-g>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 's')
        self.browse()
        self.send('typed')
        self.wait_for(lambda: self.nvim.current.buffer[0] == 'typed first line')
        self.send('<Esc>')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.nvim.exec_lua("selection.before_input({type='focus'}); selection.before_input({type='resize'}); selection.before_input({type='mouse',action='move'})")
        self.assertEqual(self.nvim.exec_lua('return selection.state(0).selection'), [1, 1])
        self.nvim.exec_lua("selection.before_input({type='mouse',action='press'})")
        self.nvim.api.input_mouse('left', 'press', '', 0, 1, 2)
        self.wait_for(lambda: self.nvim.funcs.line('.') >= 500)
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))

    def test_huge_selection_uses_no_persistent_extmarks_and_stop_clears(self):
        self.nvim.current.buffer[:] = ['text'] * 20000
        self.nvim.input('ggVG')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'V')
        self.browse()
        self.assertEqual(self.nvim.exec_lua('return selection.state(0).selection'), [1, 20000])
        ns = self.nvim.api.get_namespaces()['VSVimMinimapSelection']
        self.assertEqual(self.nvim.api.buf_get_extmarks(0, ns, 0, -1, {}), [])
        self.nvim.exec_lua("local p=require('vsvim.minimap').provider(); p.stop()")
        self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))

    def test_provider_stays_lazy_and_unsupported_buffers_do_no_selection_work(self):
        self.nvim.exec_lua("_G.provider=require('vsvim.minimap').provider()")
        self.assertIsNone(self.nvim.exec_lua('return provider.target()'))
        self.assertFalse(self.nvim.exec_lua("return pcall(vim.api.nvim_get_autocmds,{group='VSVimMinimapSelection'})"))
        self.nvim.command('setlocal buftype=nofile')
        self.nvim.exec_lua('provider.next()')
        self.assertIsNone(self.nvim.exec_lua('return provider.target()'))
        self.assertFalse(self.nvim.exec_lua("return pcall(vim.api.nvim_get_autocmds,{group='VSVimMinimapSelection'})"))
        self.assertIsNone(self.nvim.exec_lua('return selection.capture(0)'))
        self.nvim.exec_lua('provider.stop()')

    def start_provider(self):
        self.nvim.exec_lua("_G.provider=require('vsvim.minimap').provider(); provider.next()")
        def ready():
            return self.nvim.exec_lua("for _=1,100 do provider.next() end; local t=provider.target(); return t and t.generation ~= nil and not t.busy")
        self.wait_for(ready)

    def test_retained_target_survives_sidebar_focus_and_sidebar_keyboard(self):
        self.start_provider()
        target = self.nvim.exec_lua('return provider.target()')
        for floating in (True, False):
            with self.subTest(floating=floating):
                self.nvim.input('gg0v3l')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.browse()
                self.nvim.exec_lua('''local floating=...
local b=vim.api.nvim_create_buf(false,true)
vim.bo[b].buftype='nofile'
vim.api.nvim_buf_set_lines(b,0,-1,false,{'sidebar one','sidebar two'})
local config=floating and {relative='editor',row=2,col=2,width=30,height=5} or {split='right',width=30}
_G.sidebar=vim.api.nvim_open_win(b,true,config)
provider.next()''', floating)
                self.assertEqual(self.nvim.exec_lua('return provider.target().target'), target['target'])
                self.assertEqual(self.nvim.exec_lua('return selection.state(...).selection', target['window']), [1, 1])
                self.nvim.exec_lua("provider.before_input({type='input',key='j'}); vim.api.nvim_input('j')")
                self.wait_for(lambda: self.nvim.current.window.cursor[0] == 2)
                self.assertEqual(self.nvim.current.window.handle, self.nvim.exec_lua('return _G.sidebar'))
                self.assertEqual(self.nvim.funcs.mode(), 'n')
                self.nvim.exec_lua("provider.before_input({type='input',key='escape'}); vim.api.nvim_input('<Esc>')")
                self.assertEqual(self.nvim.exec_lua('return selection.state(...).selection', target['window']), [1, 1])
                self.nvim.api.set_current_win(target['window'])
                self.nvim.exec_lua("provider.before_input({type='input',key='y'}); vim.api.nvim_input('y')")
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.assertEqual(self.nvim.funcs.getreg('"'), 'word')
                self.assertEqual(self.nvim.current.buffer[:], self.original)
                self.nvim.exec_lua('vim.api.nvim_win_close(_G.sidebar,true)')

    def test_preserved_keyword_change_refreshes_matches_without_losing_region(self):
        self.start_provider()
        self.nvim.current.buffer[:3] = ['word word-word', 'word-word', '-- word']
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.nvim.command('setlocal iskeyword+=-')
        self.assertEqual(self.nvim.exec_lua('return selection.state(0).selection'), [1, 1])
        self.wait_for(lambda: self.nvim.exec_lua('return selection.state(0).occurrences') == [1, 3] + list(range(4, 1001)))
        self.send('y')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
        self.assertEqual(self.nvim.funcs.getreg('"'), 'word')

    def test_preserved_selection_option_changes_keep_original_selected_text(self):
        for original, changed, keys in [('inclusive', 'exclusive', 'gg0v3l'),
                                         ('exclusive', 'inclusive', 'gg0v4l'),
                                         ('exclusive', 'inclusive', 'gg04lv4h'),
                                         ('inclusive', 'exclusive', 'gg0<C-v>j3l'),
                                         ('inclusive', 'exclusive', 'gg0v3l<C-g>')]:
            with self.subTest(original=original, keys=keys):
                self.nvim.options['selection'] = original
                self.nvim.input(keys)
                self.wait_for(lambda: self.nvim.funcs.mode() in ('v', '\x16', 's'))
                if self.nvim.funcs.mode() == 's':
                    self.nvim.input('<C-g>')
                    self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.nvim.input('y')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                expected = [self.nvim.funcs.getreg('"'), self.nvim.funcs.getregtype('"')]
                self.nvim.input(keys)
                self.wait_for(lambda: self.nvim.funcs.mode() in ('v', '\x16', 's'))
                self.browse()
                self.nvim.options['selection'] = changed
                self.assertEqual(self.nvim.exec_lua('return selection.state(0).selection')[0], 1)
                self.nvim.exec_lua("selection.before_input({type='input',key='y'})")
                if self.nvim.funcs.mode() == 's':
                    self.nvim.input('<C-g>')
                    self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.nvim.input('y')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.assertEqual([self.nvim.funcs.getreg('"'), self.nvim.funcs.getregtype('"')], expected)
                self.assertEqual(self.nvim.options['selection'], changed)

    def test_raw_host_escape_names_clear_without_restoring(self):
        for raw in ('escape', 'ctrl-['):
            with self.subTest(raw=raw):
                self.nvim.input('gg0v3l')
                self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
                self.browse()
                self.nvim.exec_lua("selection.before_input({type='input',key=...}); vim.api.nvim_input('<Esc>')", raw)
                self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
                self.assertGreaterEqual(self.nvim.funcs.line('.'), 490)
                self.assertIsNone(self.nvim.exec_lua('return selection.state(0).selection'))

    def test_yank_restores_preserved_selection(self):
        self.nvim.input('gg0v3l')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
        self.browse()
        self.assertEqual(self.nvim.current.buffer[:], self.original)
        self.send('y')
        self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
        self.assertEqual(self.nvim.funcs.getreg('"'), 'word')

if __name__ == '__main__':
    unittest.main()
