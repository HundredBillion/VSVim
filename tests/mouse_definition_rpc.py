"""uv run --with pynvim python tests/mouse_definition_rpc.py [--real]."""
from pathlib import Path
import os
import shutil
import sys
import tempfile
import time
import pynvim

root = Path(__file__).resolve().parents[1]
real = '--real' in sys.argv
with tempfile.TemporaryDirectory(prefix='vsvim-mouse-') as directory:
    fixture = Path(directory)
    (fixture / 'main.py').write_text('from helper import hello\nhello()\n')
    (fixture / 'helper.py').write_text('def hello():\n    return 42\n')
    (fixture / 'pyproject.toml').write_text('')
    args = [shutil.which(os.environ.get('VSVIM_NVIM', 'nvim-nightly')), '--embed', '-n']
    if real:
        os.environ['NVIM_APPNAME'] = 'vsvim'
        os.environ['VSVIM_ROOT'] = str(root)
        args += ['--cmd', 'let g:vsvim_auto_explorer = v:false', '-u', str(root / 'init.lua')]
    else:
        args += ['--clean']
    nvim = pynvim.attach('child', argv=args)
    try:
        nvim.ui_attach(80, 24, rgb=True)
        if real:
            nvim.command('edit ' + nvim.funcs.fnameescape(str(fixture / 'main.py')))
            for _ in range(300):
                if nvim.exec_lua('return #vim.lsp.get_clients({bufnr=0,method="textDocument/definition"})'):
                    break
                time.sleep(.05)
            else:
                raise AssertionError('Python server did not attach; run :VSVimInstallLsp first')
        else:
            nvim.exec_lua('''local root=...; vim.opt.rtp:prepend(root)
vim.o.mouse='a'; vim.o.signcolumn='no'; vim.o.number=false
vim.api.nvim_buf_set_lines(0,0,-1,false,{'aaaa first()', 'bbbb target()'})
local lsp=require('vsvim.lsp')
vim.keymap.set({'n','i'},'<D-LeftMouse>',lsp.mouse_definition)
vim.keymap.set({'n','i'},'<D-LeftRelease>','<Nop>')
vim.lsp.buf.definition=function() _G.clicked=vim.api.nvim_win_get_cursor(0) end
''', str(root))
        nvim.command('redraw')
        position = nvim.funcs.screenpos(nvim.current.window.handle, 2, 2 if real else 8)
        nvim.api.input_mouse('left', 'press', 'D', 0, position['row']-1, position['col']-1)
        for _ in range(300):
            passed = (nvim.current.buffer.name.endswith('/helper.py') if real
                      else nvim.exec_lua('return _G.clicked') == [2, 7])
            if passed:
                break
            time.sleep(.02)
        assert passed, 'Command-click did not resolve the clicked symbol'
        nvim.api.input_mouse('left', 'release', 'D', 0, position['row']-1, position['col']-1)
        if real:
            assert nvim.current.window.cursor == (1, 0), 'release changed the definition location'
        print('Command/Super mouse RPC passed' + (' with real Python LSP' if real else ''))
    finally:
        try:
            nvim.command('qa!')
        except EOFError:
            pass
        nvim.close()
