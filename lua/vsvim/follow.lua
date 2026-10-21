local follow = require('follow')
local M = setmetatable({}, {__index=follow})

function M.statusline()
  if vim.g.sprite_follow_native then return (' '):rep(13) end
  return follow.statusline()
end

function M.setup()
  follow.setup({
    commands=false,
    root=function()
      local ok, tree = pcall(require, 'svgtree')
      local tree_root = ok and tree.root() or nil
      local project = vim.fs.root(vim.api.nvim_buf_get_name(0), '.git')
      if not tree_root then return project end
      if vim.uv.fs_stat(tree_root .. '/.git') then return tree_root end
      if project and project:sub(1, #tree_root + 1) == tree_root .. '/' then
        return project
      end
      return tree_root
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
