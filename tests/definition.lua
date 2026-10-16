local lsp = require('vsvim.lsp')
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'one()', 'two()' })
vim.api.nvim_set_current_buf(source)
local path = vim.fn.tempname() .. '.py'
vim.fn.writefile({ '# definition', '    def hello():', '        pass' }, path)
path = vim.uv.fs_realpath(path)
local original, pending = vim.lsp.buf.definition
vim.lsp.buf.definition = function(opts) pending = opts.on_list end
lsp.definition()
pending({ items = { { filename = path, lnum = 2, col = 9 } } })
assert(vim.api.nvim_buf_get_name(0) == path)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), {2, 0}), 'jump starts at column zero')
vim.cmd('normal! ' .. vim.keycode('<C-o>'))
assert(vim.api.nvim_get_current_buf() == source, 'jump list returns to origin')
lsp.definition()
local stale = pending
vim.api.nvim_win_set_cursor(0, {2, 0})
stale({items={{filename=path,lnum=2}}})
assert(vim.api.nvim_get_current_buf() == source, 'moved cursor ignores delayed response')
lsp.definition()
local before_edit = pending
vim.api.nvim_buf_set_lines(source, 1, 2, false, {'new_symbol()'})
before_edit({items={{filename=path,lnum=2}}})
assert(vim.api.nvim_get_current_buf() == source, 'edited source ignores delayed response')
local old_select, choices, choose = vim.ui.select
vim.ui.select = function(items, _, cb) choices=items; choose=cb end
lsp.definition()
pending({items={{filename=path,lnum=2},{filename=path,lnum=2},{filename=path,lnum=3}}})
assert(#choices == 2, 'duplicate definitions removed')
choose(nil)
assert(vim.api.nvim_get_current_buf() == source, 'cancel stays in source')
lsp.definition()
pending({items={{filename=path,lnum=2},{filename=path,lnum=3}}})
choose(choices[2])
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), {3,0}))
vim.ui.select = old_select
vim.lsp.buf.definition = original
vim.fn.delete(path)
assert(vim.fn.maparg('<D-LeftMouse>', 'n') ~= '')
assert(vim.fn.maparg('<D-LeftRelease>', 'n') == '<Nop>')
print('VSVim definition navigation passed')
