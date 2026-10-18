local names, installs = {}, 0
package.loaded['mason'] = {setup=function() end}
package.loaded['mason-lspconfig'] = {setup=function(opts) assert(#opts.ensure_installed==0) end}
package.loaded['mason-registry'] = {
  refresh=function(done) done(true) end,
  get_package=function(name)
    return {
      is_installed=function() return names[name] == 'installed' end,
      is_installing=function() return names[name] == 'pending' end,
      install=function() names[name]='pending'; installs=installs+1 end,
    }
  end,
}
assert(#vim.api.nvim_list_uis()==0)
require('vsvim.lsp').setup()
assert(vim.tbl_contains(require('vsvim.lsp').servers, 'lua_ls'))
assert(vim.lsp.config.lua_ls.settings.Lua.workspace.library[1] == vim.env.VIMRUNTIME .. '/lua')
assert(installs==0, 'headless startup does not download servers')
vim.api.nvim_exec_autocmds('UIEnter', {})
assert(vim.wait(1000,function() return installs==6 end), 'UI attachment installs all default servers')
assert(names['lua-language-server'] ~= nil, 'Lua server is included')
vim.cmd.VSVimInstallLsp()
vim.wait(20,function() return false end)
assert(installs==6, 'pending packages do not install twice')
for name in pairs(names) do names[name]='installed' end
vim.cmd.VSVimInstallLsp()
vim.wait(20,function() return false end)
assert(installs==6, 'installed packages are retained')
print('VSVim LSP installation lifecycle passed')
