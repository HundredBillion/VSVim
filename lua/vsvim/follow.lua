local follow = require('follow')
local M = setmetatable({}, {__index=follow})

function M.statusline()
  if vim.g.sprite_follow_native then
    local state = follow.status()
    if not state.enabled then return (' '):rep(13) end
    local label = ({waiting='WAITING',live='LIVE',location=state.activity=='read' and 'READING'
      or 'EDITING',saved='SAVED'})[state.capability]
      or 'FOLLOWING'
    return (' '):rep(13) .. '%#Comment#  ' .. label .. '  %#StatusLine#'
  end
  return follow.statusline()
end

function M.setup()
  local last_tree_root
  follow.setup({
    commands=false,
    root=function()
      local ok, tree = pcall(require, 'svgtree')
      local tree_root = ok and tree.root() or nil
      if tree_root then last_tree_root = tree_root end
      local project = vim.fs.root(vim.api.nvim_buf_get_name(0), '.git')
      return last_tree_root or project or vim.fn.getcwd()
    end,
    before_open=function(buf)
      local markdown = package.loaded['vsvim.markdown']
      if markdown and markdown.previewing(buf) then markdown.toggle(buf) end
    end,
    native_control=function() return vim.g.sprite_follow_native end,
  })
  _G.VSVimFollowClick = function(_, _, button) if button == 'l' then follow.toggle() end end
  vim.api.nvim_create_user_command('VSVimFollowToggle', follow.toggle, {force=true})
  vim.api.nvim_create_user_command('VSVimFollowOn', function() follow.set_enabled(true) end, {force=true})
  vim.api.nvim_create_user_command('VSVimFollowOff', function() follow.set_enabled(false) end, {force=true})
  vim.keymap.set('n', '<leader>af', follow.toggle, {desc='Follow coding activity'})
end

return M
