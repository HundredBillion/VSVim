vim.schedule(function()
  local ok, err = pcall(function()
    assert(vim.bo.filetype == 'vsvim_welcome', vim.bo.filetype)
    assert(vim.bo.buftype == 'nofile' and not vim.bo.modified)
    assert(not vim.wo.number)
    local buf = vim.api.nvim_get_current_buf()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert(text:find('V S V I M', 1, true))
    assert(not text:find('Netrw', 1, true))
    vim.o.columns = 24
    vim.api.nvim_exec_autocmds('VimResized', {})
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      assert(vim.fn.strdisplaywidth(line) <= 24)
    end
    vim.cmd('enew')
    assert(vim.wo.number and vim.wo.cursorline)
    assert(vim.bo.buftype == '' and vim.bo.modifiable)
    assert(not vim.api.nvim_buf_is_valid(buf))
  end)
  if not ok then
    vim.api.nvim_err_writeln(tostring(err))
    vim.cmd('cquit 1')
  else
    print('Welcome startup, resize, and file handoff passed')
    vim.cmd('qa!')
  end
end)
