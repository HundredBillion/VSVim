"""Optional RPC integration check: uv run --with pynvim python tests/mouse_definition_rpc.py."""
from pathlib import Path
import time
import os
import shutil
import pynvim

root = Path(__file__).resolve().parents[1]
nvim = pynvim.attach('child', argv=[shutil.which(os.environ.get('VSVIM_NVIM', 'nvim-nightly')), '--embed', '--clean'])
try:
    nvim.ui_attach(80, 24, rgb=True)
    nvim.exec_lua('''local root=...; vim.opt.rtp:prepend(root)
vim.o.mouse='a'; vim.o.signcolumn='no'; vim.o.number=false
vim.api.nvim_buf_set_lines(0,0,-1,false,{'aaaa first()', 'bbbb target()'})
local lsp=require('vsvim.lsp')
vim.keymap.set({'n','i'},'<D-LeftMouse>',lsp.mouse_definition)
vim.keymap.set({'n','i'},'<D-LeftRelease>','<Nop>')
vim.lsp.buf.definition=function() _G.clicked=vim.api.nvim_win_get_cursor(0) end
''', str(root))
    nvim.api.input_mouse('left', 'press', 'D', 0, 1, 7)
    for _ in range(100):
        pos = nvim.exec_lua('return _G.clicked')
        if pos is not None:
            break
        time.sleep(.01)
    assert pos == [2, 7], pos
    nvim.api.input_mouse('left', 'release', 'D', 0, 1, 7)
    print('Command/Super mouse RPC selects clicked symbol: passed')
finally:
    try:
        nvim.command('qa!')
    except EOFError:
        pass
    nvim.close()
