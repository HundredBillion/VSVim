local M = {}

local function escape(text)
  return text:gsub('%%', '%%%%'):gsub('[\r\n\t]', ' ')
end

function M.tabline()
  local parts = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft == 'svgtree' or ft == 'scm' then
      local width = vim.api.nvim_win_get_width(win)
      local label = ft == 'scm' and 'SOURCE CONTROL' or 'EXPLORER'
      parts[#parts + 1] = '%#TabLineFill# ' .. label .. string.rep(' ', math.max(0, width - #label))
      break
    end
  end
  for _, buffer in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if vim.bo[buffer.bufnr].buftype == '' then
      local active = buffer.bufnr == vim.api.nvim_get_current_buf()
      local name = vim.fn.fnamemodify(buffer.name, ':t')
      if name == '' then name = 'Untitled' end
      parts[#parts + 1] = (active and '%#TabLineSel#' or '%#TabLine#')
        .. '%' .. buffer.bufnr .. '@v:lua.VSVimSelectBuffer@  '
        .. escape(name) .. (buffer.changed == 1 and ' ● ' or '   ') .. '%T'
    end
  end
  return table.concat(parts) .. '%#TabLineFill#%='
end

function M.statusline()
  local mode = vim.fn.mode():sub(1, 1)
  local label = ({ n = 'NORMAL', i = 'INSERT', v = 'VISUAL', V = 'VISUAL',
    ['\22'] = 'VISUAL', c = 'COMMAND', R = 'REPLACE', t = 'TERMINAL' })[mode] or 'NORMAL'
  local filetype = vim.bo.filetype ~= '' and vim.bo.filetype or 'Plain Text'
  return '%#VSVimMode#  ' .. label .. '  %#StatusLine#  %f %m%r%='
    .. 'Ln %l, Col %c   Spaces: ' .. vim.bo.shiftwidth .. '   '
    .. escape(vim.bo.fileencoding ~= '' and vim.bo.fileencoding or vim.o.encoding)
    .. '   ' .. escape(filetype) .. '  '
end

function M.setup()
  vim.cmd('colorscheme vsvim-dark-modern')
  vim.opt.showtabline = 2
  vim.opt.laststatus = 3
  vim.opt.showmode = false
  vim.opt.cursorline = true
  vim.opt.signcolumn = 'yes'
  vim.opt.fillchars:append({ eob = ' ' })
  vim.opt.shortmess:append('I')
  vim.opt.splitright = true
  vim.opt.splitbelow = true
  vim.opt.tabline = "%!v:lua.require('vsvim.appearance').tabline()"
  vim.opt.statusline = "%!v:lua.require('vsvim.appearance').statusline()"
  _G.VSVimSelectBuffer = function(buffer, _, button)
    if button ~= 'l' or not vim.api.nvim_buf_is_valid(buffer) then return end
    if vim.bo.buftype == '' then
      vim.api.nvim_set_current_buf(buffer)
      return
    end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == '' then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_buf(win, buffer)
        return
      end
    end
  end
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
