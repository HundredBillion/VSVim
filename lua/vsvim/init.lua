local M = {}

function M.setup()
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
    {
      'HundredBillion/sprite.nvim',
      commit = '05adda83c090da78f4faf30bdae3b678990d2b0e',
      lazy = false,
    },
    {
      'HundredBillion/scm.nvim',
      commit = '8aeb27e3e9b5edd824c0abe31e55f328c06ea5ef',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = { renderer = 'auto' },
    },
    {
      'HundredBillion/svgtree.nvim',
      commit = 'd33176b24600dd36521fe1137ff8e40e84b40f71',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = { native = { mappings = {
        ['<Space>e'] = 'close', ['<C-b>'] = 'close',
        ['<Space>gs'] = function() require('scm').toggle() end,
        ['<C-S-g>'] = function() require('scm').toggle() end,
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
  local function explorer()
    local root = tree.root() or require('scm.scope').current()
    scm.handoff(function() tree.toggle(root) end)
  end
  vim.keymap.set('n', '<leader>e', explorer, { desc = 'Explorer' })
  vim.keymap.set('n', '<C-b>', explorer, { desc = 'Explorer' })
  vim.keymap.set('n', '<leader>gs', scm.toggle, { desc = 'Source Control' })
  vim.keymap.set('n', '<C-S-g>', scm.toggle, { desc = 'Source Control' })
  require('vsvim.navigation').setup()
  require('vsvim.appearance').setup()
  local user = vim.fn.stdpath('config') .. '/user.lua'
  if vim.uv.fs_stat(user) then
    dofile(user)
  end
end

return M
