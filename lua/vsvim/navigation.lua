local M = {}
function M.setup()
  for key, direction in pairs({['<C-h>']='h', ['<C-l>']='l'}) do
    vim.keymap.set('n', key, function()
      local before=vim.api.nvim_get_current_win()
      vim.cmd('wincmd ' .. direction)
      if vim.api.nvim_get_current_win() ~= before then return end
      local side=direction=='h' and 'left' or 'right'
      if require('svgtree').focus(side) then return end
      require('scm').focus(side)
    end, {desc=direction=='h' and 'Focus left' or 'Focus right'})
  end
end
return M
