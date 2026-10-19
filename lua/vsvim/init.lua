local M = {}

function M.setup()
  require('vsvim.minimap.query_config').observe()
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1
  vim.g.mapleader = ' '
  vim.g.maplocalleader = '\\'
  vim.opt.number = true
  vim.opt.termguicolors = true
  vim.opt.mouse = 'a'
  vim.opt.expandtab = true
  vim.opt.shiftwidth = 2
  vim.opt.tabstop = 2
  vim.opt.ignorecase = true
  vim.opt.smartcase = true
  vim.opt.confirm = true
  vim.opt.hidden = true
  vim.opt.swapfile = true
  vim.opt.updatetime = 1000
  vim.opt.undofile = true
  local data = vim.fn.stdpath('data')
  local manager = data .. '/lazy/lazy.nvim'
  if not vim.uv.fs_stat(manager) then
    vim.fn.mkdir(data .. '/lazy', 'p')
    local pending = manager .. '.install-' .. vim.fn.getpid()
    local function run(args)
      local ok, result = pcall(function()
        return vim.system(args, { text = true }):wait()
      end)
      if not ok or result.code ~= 0 then
        vim.fn.delete(pending, 'rf')
        error('VSVim plugin bootstrap failed: ' .. (ok and (result.stderr or '') or tostring(result)))
      end
    end
    run({ 'git', 'clone', '--filter=blob:none',
      'https://github.com/folke/lazy.nvim.git', pending })
    run({ 'git', '-C', pending, 'checkout', '--detach',
      '85c7ff3711b730b4030d03144f6db6375044ae82' })
    local ok, err = vim.uv.fs_rename(pending, manager)
    if not ok then
      vim.fn.delete(pending, 'rf')
      if not vim.uv.fs_stat(manager .. '/lua/lazy/init.lua') then
        error('VSVim plugin bootstrap failed: ' .. tostring(err))
      end
    end
  end
  vim.opt.runtimepath:prepend(manager)
  require('lazy').setup({
    { 'folke/lazy.nvim', commit = '85c7ff3711b730b4030d03144f6db6375044ae82' },
    { 'neovim/nvim-lspconfig', commit = '45a3a444b710511c39abca3b60bb6e23a21e3de5', lazy = false },
    { 'mason-org/mason.nvim', commit = '2a6940af80375532e5e9e7c1f2fc6319a1b7a69d', lazy = false },
    { 'mason-org/mason-lspconfig.nvim', commit = '00b5473cca4db5b410ff4bae724e3b6e21f2687f', lazy = false,
      dependencies = { 'mason.nvim', 'nvim-lspconfig' } },
    {
      'HundredBillion/sprite.nvim',
      commit = '21c96d6e15cfea741eba145284461b7256d7d159',
      lazy = false,
    },
    {
      'HundredBillion/scm.nvim',
      commit = 'c6946caa84c49054f37bf9097b7f59bcadf2bfa7',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = {
        renderer = 'auto',
        on_explorer = function(root) require('vsvim.sidebar').explorer(root) end,
        native = { colors = require('vsvim.theme').native_colors },
      },
    },
    {
      'HundredBillion/svgtree.nvim',
      commit = 'b1781a04d6147292ccd240cac8b73f6b31c679e3',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = { native = { colors = require('vsvim.theme').native_colors, mappings = {
        ['<Space>e'] = function() require('vsvim.sidebar').explorer() end,
        ['<C-b>'] = function() require('vsvim.sidebar').explorer() end,
        ['<Space>gs'] = function() require('vsvim.sidebar').scm() end,
        ['<C-S-g>'] = function() require('vsvim.sidebar').scm() end,
      } } },
    },
  }, {
    root = data .. '/lazy',
    lockfile = data .. '/lazy-lock.json',
    checker = { enabled = false },
    change_detection = { enabled = false },
    performance = { rtp = { paths = { vim.env.VSVIM_ROOT } } },
  })
  local sprite_ok, sprite = pcall(require, 'sprite')
  local tree_ok, tree = pcall(require, 'svgtree')
  local scm_ok, scm = pcall(require, 'scm')
  if not sprite_ok or type(sprite.available) ~= 'function'
    or not tree_ok or type(tree.toggle) ~= 'function'
    or vim.fn.exists(':SvgTreeToggle') ~= 2
    or not scm_ok or type(scm.handoff) ~= 'function'
    or vim.fn.exists(':ScmToggle') ~= 2 then
    error('VSVim required plugins unavailable; check the plugin installation errors and retry')
  end
  local sidebar = require('vsvim.sidebar')
  vim.keymap.set('n', '<leader>e', sidebar.explorer, { desc = 'Explorer' })
  vim.keymap.set('n', '<C-b>', sidebar.explorer, { desc = 'Explorer' })
  vim.keymap.set('n', '<leader>gs', sidebar.scm, { desc = 'Source Control' })
  vim.keymap.set('n', '<C-S-g>', sidebar.scm, { desc = 'Source Control' })
  require('vsvim.lsp').setup()
  require('vsvim.navigation').setup()
  require('vsvim.editing').setup()
  require('vsvim.appearance').setup()
  local user = vim.fn.stdpath('config') .. '/user.lua'
  if vim.uv.fs_stat(user) then
    dofile(user)
  end
  require('vsvim.minimap').setup()
end

return M
