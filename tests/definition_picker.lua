local picker = require('vsvim.definition_picker')
local origin = vim.api.nvim_get_current_win()
local items = {}
for i = 1, 15 do
  items[i] = { filename = '/private/long/package/path/builtins.pyi', lnum = i,
    text = ('def pow(base: int, exp: int, mod: int = %d) -> int: ...'):format(i) }
end
local chosen, calls = nil, 0
local function callback(item)
  calls = calls + 1
  chosen = item
  assert(vim.api.nvim_get_current_win() == origin, 'selection restores origin before callback')
end
local function key(lhs)
  local mapping = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(mapping.callback) == 'function', lhs)
  mapping.callback()
end
picker.open(items, callback)
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
assert(vim.api.nvim_win_get_height(win) == 10, 'fifteen overloads occupy only ten rows')
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[1]:find('def pow', 1, true))
assert(lines[2] == '    builtins.pyi:1', 'paths stay secondary and short')
assert(not vim.bo[buf].buflisted)
vim.api.nvim_win_set_cursor(win, { 9, 0 })
key('j')
assert(vim.api.nvim_win_get_cursor(win)[1] == 11, 'navigation follows actual cursor after scrolling')
key('G')
key('<CR>')
assert(chosen == items[15] and calls == 1, 'can select last overload')
assert(not vim.api.nvim_win_is_valid(win) and not vim.api.nvim_buf_is_valid(buf), 'selection cleans up UI')
picker.open(items, callback)
key('<Esc>')
assert(chosen == nil and calls == 2, 'cancel does not select')
local other = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
  { relative = 'editor', row = 1, col = 1, width = 10, height = 2 })
picker.open(items, function(item) assert(item == nil); calls = calls + 1 end)
win = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(other)
vim.wait(100, function() return not vim.api.nvim_win_is_valid(win) end)
assert(not vim.api.nvim_win_is_valid(win), 'leaving closes picker')
assert(vim.api.nvim_get_current_win() == other, 'leaving does not steal focus')
assert(calls == 3)
vim.api.nvim_win_close(other, true)
print('VSVim compact definition picker passed')
