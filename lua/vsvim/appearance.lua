local M = {}

local function escape(text)
  return text:gsub('%%', '%%%%'):gsub('[\r\n\t]', ' ')
end

function M.tabline() return require('vsvim.tabs').render() end

function M.statusline()
  if vim.bo.filetype == 'vsvim_welcome' then return '%#StatusLine#  VSVim%=%#Comment#Ready  ' end
  local mode = vim.fn.mode():sub(1, 1)
  local label = ({ n = 'NORMAL', i = 'INSERT', v = 'VISUAL', V = 'VISUAL',
    ['\22'] = 'VISUAL', c = 'COMMAND', R = 'REPLACE', t = 'TERMINAL' })[mode] or 'NORMAL'
  local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or 'Plain Text'
  return '%#VSVimMode#  ' .. label .. '  %#StatusLine# %m%r%='
    .. 'Ln %l, Col %c   Spaces: ' .. vim.bo.shiftwidth .. '   '
    .. escape(vim.bo.fileencoding ~= '' and vim.bo.fileencoding or vim.o.encoding)
    .. '   ' .. escape(filetype) .. '  '
end

function M.setup()
  vim.cmd('colorscheme vsvim-jb-dark')
  vim.opt.showtabline = 2
  vim.opt.laststatus = 3
  vim.opt.cmdheight = 0
  vim.opt.showmode = false
  vim.opt.cursorline = true
  vim.opt.wrap = false
  vim.opt.signcolumn = 'yes'
  vim.opt.fillchars:append({ eob = ' ' })
  vim.opt.shortmess:append('I')
  vim.opt.splitright = true
  vim.opt.splitbelow = true
  vim.opt.tabline = "%!v:lua.require('vsvim.appearance').tabline()"
  vim.opt.statusline = "%!v:lua.require('vsvim.appearance').statusline()"
  require('vsvim.tabs').setup()
  local group = vim.api.nvim_create_augroup('VSVimAppearance', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group, pattern = 'svgtree', callback = function()
      vim.wo.winhighlight = 'Normal:VSVimSidebar,CursorLine:VSVimSidebarSelection,EndOfBuffer:VSVimSidebar'
      vim.wo.number = false
      vim.wo.relativenumber = false
      vim.wo.signcolumn = 'no'
    end,
  })
  vim.api.nvim_create_autocmd('VimEnter', {
    group = group, once = true, callback = function()
      require('vsvim.welcome').open_on_startup()
      if vim.g.vsvim_auto_explorer == false or #vim.api.nvim_list_uis() == 0 then return end
      vim.schedule(function()
        local win = vim.api.nvim_get_current_win()
        require('svgtree').open(vim.fn.getcwd())
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
      end)
    end,
  })
end

return M
