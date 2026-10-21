local follow = require('follow')
local M = setmetatable({}, {__index=follow})

function M.setup()
  follow.setup({
    commands=false,
    root=function()
      local ok, tree = pcall(require, 'svgtree')
      return ok and tree.root() or nil
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
