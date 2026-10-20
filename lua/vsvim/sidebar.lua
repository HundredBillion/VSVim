local M = {}
local generation = 0

function M.explorer(root, opts)
  opts = opts or {}
  local editor = vim.api.nvim_get_current_win()
  generation = generation + 1
  local token = generation
  local tree = require('svgtree')
  root = root or tree.root() or require('scm.scope').current()
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
  require('scm').toggle()
end

function M.focus(side)
  return require('svgtree').focus(side) or require('scm').focus(side)
end

return M
