assert(vim.g.colors_name == 'vsvim-jb-dark')
assert(vim.api.nvim_get_hl(0, { name = 'Normal' }).bg == 0x1e1f22)
assert(vim.api.nvim_get_hl(0, { name = 'TabLineFill' }).bg == 0x1e1f22)
assert(vim.api.nvim_get_hl(0, { name = 'String' }).fg == 0x6aab73)
assert(vim.api.nvim_get_hl(0, { name = 'Keyword' }).fg == 0xcf8e6d)
assert(vim.api.nvim_get_hl(0, { name = 'Function' }).fg == 0x56a8f5)
assert(vim.api.nvim_get_hl(0, { name = 'ScmBackground' }).bg == 0x2b2d30)
assert(not vim.wo.wrap, 'code lines do not soft-wrap by default')
assert(vim.o.showtabline == 2 and vim.o.laststatus == 3)
local first = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(first, '/tmp/100% done.lua')
vim.api.nvim_set_current_buf(first)
local rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
assert(rendered:find('100%% done.lua'), rendered)
local second = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(second, '/tmp/second.lua')
_G.VSVimSelectBuffer(second, 1, 'l', '')
assert(vim.api.nvim_get_current_buf() == second)
vim.cmd('vsplit')
vim.cmd('wincmd l')
local focused = vim.api.nvim_get_current_win()
_G.VSVimSelectBuffer(first, 1, 'l', '')
assert(vim.api.nvim_get_current_win() == focused, 'tab clicks must preserve the focused editor split')
assert(vim.api.nvim_get_current_buf() == first)
vim.cmd('colorscheme vsvim-jb-dark')
assert(vim.api.nvim_get_hl(0, { name = 'Normal' }).bg == 0x1e1f22)
local tabs=require('vsvim.tabs')
local dirty=vim.api.nvim_create_buf(true,false)
vim.api.nvim_buf_set_name(dirty,'/tmp/tab-close-test.lua')
vim.api.nvim_set_current_buf(dirty)
vim.api.nvim_buf_set_lines(dirty,0,-1,false,{'unsaved'})
local select=vim.ui.select
vim.ui.select=function(_,_,callback) callback('Cancel') end
tabs.close(dirty)
assert(vim.api.nvim_buf_is_valid(dirty) and vim.bo[dirty].modified, 'cancel preserves modified file')
vim.ui.select=function(_,_,callback) callback('Discard changes') end
local window_count=#vim.api.nvim_list_wins()
local hidden=vim.o.hidden
vim.o.hidden=false
tabs.close(dirty)
assert(not vim.api.nvim_buf_is_valid(dirty), 'explicit discard closes tab even with nohidden')
vim.o.hidden=hidden
assert(#vim.api.nvim_list_wins()==window_count, 'closing tab preserves splits')
vim.ui.select=select
local saved_columns=vim.o.columns
vim.o.columns=60
for i=1,12 do
  local b=vim.api.nvim_create_buf(true,false)
  vim.api.nvim_buf_set_name(b,'/tmp/overflow-'..i..'.lua')
  vim.api.nvim_set_current_buf(b)
end
local narrow=vim.api.nvim_eval_statusline(vim.o.tabline,{use_tabline=true}).str
assert(narrow:find('overflow%-12.lua'), 'active tab remains visible during overflow')
assert(narrow:find('×',1,true), 'file tabs have close buttons')
vim.o.columns=saved_columns
print('VSVim appearance passed')
