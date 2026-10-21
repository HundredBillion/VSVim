local app = vim.env.VSVIM_APP_SOURCE
  or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(app)
vim.opt.runtimepath:prepend(assert(vim.env.VSVIM_FOLLOW_SOURCE))
vim.g.mapleader = ' '

local tree_root = assert(vim.env.VSVIM_FOLLOW_TEST_TREE)
if tree_root == 'none' then tree_root = nil end
local project_root = assert(vim.env.VSVIM_FOLLOW_TEST_PROJECT)
package.loaded.svgtree = {root = function() return tree_root end}
vim.cmd.edit(project_root .. '/README.md')

local follow = require('vsvim.follow')
follow.setup()
assert(vim.fn.maparg(' af', 'n') ~= '', 'Space a f is mapped')
vim.api.nvim_feedkeys(' af', 'xt', false)
assert(vim.wait(5000, function()
  local state = follow.status()
  return state.ready or not state.enabled and state.reason ~= nil
end), 'Follow did not respond to Space a f')
local state = follow.status()
assert(state.enabled and state.ready and state.root == project_root,
  'Space a f did not activate Follow for the open project: ' .. vim.inspect(state))
follow.set_enabled(false)
print('Follow scope shortcut passed')
vim.cmd.qa({bang=true})
