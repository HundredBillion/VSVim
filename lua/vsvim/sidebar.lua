local M = {}
local generation = 0
local last_root

function M.explorer(root, opts)
  opts = opts or {}
  local editor = vim.api.nvim_get_current_win()
  generation = generation + 1
  local token = generation
  local tree = require('svgtree')
  root = root or tree.root() or last_root or require('scm.scope').current()
  root = vim.uv.fs_realpath(root) or root
  last_root = root
  require('vsvim.follow').remember_root(root)
  require('scm').handoff(function()
    if token ~= generation then return end
    if opts.open then tree.open(root) else tree.toggle(root) end
    if opts.focus == false and vim.api.nvim_win_is_valid(editor) then
      vim.api.nvim_set_current_win(editor)
    end
  end)
end

function M.scm()
  generation = generation + 1
  local tree = require('svgtree')
  last_root = tree.root() or require('scm.scope').current()
  if last_root then last_root = vim.uv.fs_realpath(last_root) or last_root end
  tree.close()
  require('scm').toggle()
end

function M.focus(side)
  return require('svgtree').focus(side) or require('scm').focus(side)
end

return M
