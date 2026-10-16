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
      'HundredBillion/svgtree.nvim',
      commit = '13567cc93a71a49eedcf5b82b68fda93874b286e',
      lazy = false,
      dependencies = { 'HundredBillion/sprite.nvim' },
      opts = { native = { mappings = {
        ['<Space>e'] = 'close', ['<C-b>'] = 'close',
      } } },
    },
  }, {
    root = data .. '/lazy',
    lockfile = data .. '/lazy-lock.json',
    checker = { enabled = false },
    change_detection = { enabled = false },
  })
  vim.keymap.set('n', '<leader>e', '<cmd>SvgTreeToggle<cr>', { desc = 'Explorer' })
  vim.keymap.set('n', '<C-b>', '<cmd>SvgTreeToggle<cr>', { desc = 'Explorer' })
  local user = vim.fn.stdpath('config') .. '/user.lua'
  if vim.uv.fs_stat(user) then
    dofile(user)
  end
end

return M
