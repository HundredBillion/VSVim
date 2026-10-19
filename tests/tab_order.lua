local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.runtimepath:prepend(root)
vim.o.columns = 300
vim.o.hidden = true
local tabs = require('vsvim.tabs')
local function buffer(name)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, '/tmp/vsvim-reorder-' .. name .. '.lua')
  return b
end
local a, b, c = buffer('a'), buffer('b'), buffer('c')
local tracked = { [a] = true, [b] = true, [c] = true }
local function order()
  local result = {}
  for _, item in ipairs(tabs.native_snapshot().items) do
    if tracked[item.buffer] then result[#result + 1] = item.buffer end
  end
  return result
end
vim.api.nvim_set_current_buf(b)
assert(tabs.reorder(c, a))
assert(vim.deep_equal(order(), { c, a, b }), 'dragging moves a tab before its target')
assert(vim.api.nvim_get_current_buf() == b, 'reordering preserves the active file')
local rendered = tabs.render()
assert(rendered:find('vsvim-reorder-c.lua', 1, true) < rendered:find('vsvim-reorder-a.lua', 1, true),
  'terminal and native tab rows share the same order')
assert(tabs.reorder(c, nil))
assert(vim.deep_equal(order(), { a, b, c }), 'dropping after the last tab appends it')
local d = buffer('d')
tracked[d] = true
assert(vim.deep_equal(order(), { a, b, c, d }), 'new files append without resetting the order')
vim.api.nvim_buf_delete(b, { force = true })
assert(vim.deep_equal(order(), { a, c, d }), 'closing a file preserves remaining order')
local previous = order()
assert(not tabs.reorder(c, c), 'dropping onto itself is a no-op')
assert(not tabs.reorder(b, a), 'closed source is rejected')
assert(not tabs.reorder(c, b), 'closed destination is rejected')
assert(vim.deep_equal(previous, order()), 'invalid moves preserve the order')
vim.api.nvim_buf_set_lines(c, 0, -1, false, { 'unsaved content' })
assert(tabs.reorder(c, a))
assert(vim.bo[c].modified and vim.api.nvim_buf_get_lines(c, 0, -1, false)[1] == 'unsaved content',
  'reordering preserves unsaved edits')
print('VSVim tab ordering passed')
