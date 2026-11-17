-- Opening a folder shows the welcome page, not Neovim's built-in directory
-- listing. Run from the checkout root with a folder argument:
--   ./bin/vsvim --headless . -S tests/welcome_directory.lua
vim.schedule(function()
  local ok, err = pcall(function()
    local args = vim.fn.argv()
    assert(#args == 1 and vim.fn.isdirectory(args[1]) == 1, 'run with one folder argument')
    assert(vim.bo.filetype == 'vsvim_welcome', vim.bo.filetype)
    assert(vim.bo.buftype == 'nofile' and not vim.bo.modified)
    assert(vim.b.nvim_dir == nil)
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert(text:find('V S V I M', 1, true))
    assert(vim.uv.fs_realpath(vim.fn.getcwd()) == vim.uv.fs_realpath(args[1]))
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      assert(vim.bo[buf].filetype ~= 'directory', vim.api.nvim_buf_get_name(buf))
    end
  end)
  if not ok then
    vim.api.nvim_err_writeln(tostring(err))
    vim.cmd('cquit 1')
  else
    print('Welcome page shown when opening a folder')
    vim.cmd('qa!')
  end
end)
