package.loaded.mason = { setup = function() end }
package.loaded['mason-lspconfig'] = { setup = function(opts) assert(opts.automatic_enable == false) end }
require('vsvim.lsp').setup()
assert(#vim.api.nvim_list_uis() == 0)
assert(vim.fn.exists(':VSVimLspStatus') == 2, 'status command exists')
assert(next(require('vsvim.lsp.manager').status()) == nil)
vim.api.nvim_exec_autocmds('UIEnter', {})
assert(next(require('vsvim.lsp.manager').status()) == nil, 'empty UI installs nothing')
print('LSP setup passed')
