local M = {}

function M.save(buffer, on_saved)
  buffer = buffer or vim.api.nvim_get_current_buf()
  local function write(path)
    if not vim.api.nvim_buf_is_valid(buffer) then return end
    local ok, err = pcall(vim.api.nvim_buf_call, buffer, function()
      vim.cmd.write({ args = path and { path } or {} })
    end)
    if not ok then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    elseif not vim.bo[buffer].modified and on_saved then
      on_saved()
    end
  end
  if vim.api.nvim_buf_get_name(buffer) ~= '' then
    write()
  else
    vim.ui.input({ prompt = 'Save as: ', completion = 'file' }, function(path)
      if path and path ~= '' then write(path) end
    end)
  end
end

function M.setup()
  vim.keymap.set('n', '<D-z>', 'u', { desc = 'Undo' })
  vim.keymap.set('i', '<D-z>', '<C-G>u<C-O>u', { desc = 'Undo' })
  vim.keymap.set('x', '<D-z>', '<Esc>u', { desc = 'Undo' })
  vim.keymap.set('n', '<D-c>', '"+yy', { desc = 'Copy line' })
  vim.keymap.set('i', '<D-c>', '<C-O>"+yy', { desc = 'Copy line' })
  vim.keymap.set('n', '<D-x>', '"+dd', { desc = 'Cut line' })
  vim.keymap.set('i', '<D-x>', '<C-G>u<C-O>"+dd', { desc = 'Cut line' })
  vim.keymap.set('x', '<D-c>', '"+ygv', { desc = 'Copy selection' })
  vim.keymap.set('x', '<D-x>', '"+d', { desc = 'Cut selection' })
  vim.keymap.set({ 'n', 'i', 'x' }, '<D-v>', function()
    local text = vim.fn.getreg('+')
    if text ~= '' then vim.api.nvim_paste(text, true, -1) end
  end, { desc = 'Paste from clipboard' })
  vim.keymap.set({ 'n', 'i', 'x' }, '<D-a>', '<Esc>ggVG', { desc = 'Select all' })
  vim.keymap.set({ 'n', 'i', 'x' }, '<D-s>', function() M.save() end, { desc = 'Save file' })
end

return M
