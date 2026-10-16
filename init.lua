local ok, err = pcall(function()
  local version = vim.version()
  if version.major == 0 and version.minor < 13 then
    error('VSVim requires Neovim 0.13 nightly; set VSVIM_NVIM to its executable')
  end
  if not (vim.ui and vim.ui.img) then
    error('VSVim requires a nightly build with vim.ui.img for SVGTree')
  end
  local root = assert(vim.env.VSVIM_ROOT, 'Start VSVim with bin/vsvim')
  vim.opt.runtimepath:prepend(root)
  require('vsvim').setup()
end)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end
