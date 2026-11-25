-- Run with: nvim-nightly --headless -u NONE -l tests/tab_close.lua
-- Closing a modified tab asks to save it, unless Neovim is already asking
-- something: a native tab click arrives over RPC even while a prompt such as
-- the one `:qa` opens is waiting, and a second prompt would stack on it.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.runtimepath:prepend(root)
vim.o.hidden = true
local tabs = require('vsvim.tabs')

local b = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b, '/tmp/vsvim-close-a.lua')
vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'unsaved' })
assert(vim.bo[b].modified)

local asked = 0
vim.ui.select = function(_, _, on_choice) asked = asked + 1; on_choice(nil) end
local real_mode = vim.api.nvim_get_mode
local function in_mode(mode, fn)
  vim.api.nvim_get_mode = function() return { mode = mode, blocking = false } end
  local ok, err = pcall(fn)
  vim.api.nvim_get_mode = real_mode
  assert(ok, err)
end

in_mode('n', function() tabs.close(b) end)
assert(asked == 1, 'closing a modified tab asks to save it')
for _, mode in ipairs({ 'c', 'cv', 'r', 'r?', 'rm' }) do
  in_mode(mode, function() tabs.close(b) end)
end
assert(asked == 1, 'no second prompt opens while Neovim is already asking')
assert(vim.api.nvim_buf_is_valid(b) and vim.bo[b].modified, 'the file and its edits stay open')
in_mode('i', function() tabs.close(b) end)
assert(asked == 2, 'a tab clicked while typing still asks')
print('VSVim tab close passed')
