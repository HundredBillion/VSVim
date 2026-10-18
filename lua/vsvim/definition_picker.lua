local M = {}
local active
local ns = vim.api.nvim_create_namespace('VSVimDefinitions')

function M.open(items, callback)
  if active then active() end
  local origin = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = { '' }
  for _, item in ipairs(items) do
    local path = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
    local signature = vim.trim(item.text or ''):gsub('%s+', ' ')
    lines[#lines + 1] = '   ' .. (signature ~= '' and signature or '(definition)')
    lines[#lines + 1] = '   ' .. vim.fn.fnamemodify(path, ':t') .. ':' .. item.lnum
  end
  lines[#lines + 1] = ''
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local content_width = 44
  for _, line in ipairs(lines) do content_width = math.max(content_width, vim.fn.strdisplaywidth(line) + 3) end
  local width = math.max(1, math.min(content_width, 110, vim.o.columns - 4))
  local height = math.max(1, math.min(12, #lines, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', row = math.max(0, math.floor((vim.o.lines - height) / 3)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width, height = height, style = 'minimal', border = 'rounded',
    title = ' Definitions ', title_pos = 'left',
    footer = ' Enter / click: open · Esc: cancel ', footer_pos = 'left',
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].scrolloff = 0
  local background = vim.api.nvim_get_hl(0, { name = 'NormalFloat', link = false }).bg
  vim.api.nvim_set_hl(0, 'VSVimDefinitionTitle', { fg = '#bcbec4', bg = background, bold = true })
  vim.api.nvim_set_hl(0, 'VSVimDefinitionHint', { fg = '#9da0a8', bg = background })
  vim.api.nvim_set_hl(0, 'VSVimDefinitionSelection', { bg = '#393b40' })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,CursorLine:VSVimDefinitionSelection,'
    .. 'FloatTitle:VSVimDefinitionTitle,FloatFooter:VSVimDefinitionHint'
  for i = 3, #lines - 1, 2 do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #lines[i], hl_group = 'Comment' })
  end
  for i = 2, #lines - 1, 2 do
    local first, last = lines[i]:find('[%w_]+%s*%(')
    if first then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, first - 1,
        { end_col = last - 1, hl_group = 'Function' })
    end
  end
  local closed, autocmd = false
  local function finish(item, restore)
    if closed then return end
    closed = true
    active = nil
    if autocmd then pcall(vim.api.nvim_del_autocmd, autocmd) end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if restore and vim.api.nvim_win_is_valid(origin) then vim.api.nvim_set_current_win(origin) end
    callback(item)
  end
  active = function() finish(nil, false) end
  autocmd = vim.api.nvim_create_autocmd('WinLeave', { buffer = buf, once = true, callback = function()
    vim.schedule(function() finish(nil, false) end)
  end })
  local function select(n)
    local index = math.max(1, math.min(#items, n))
    vim.api.nvim_win_set_cursor(win, { index * 2, 3 })
    vim.api.nvim_win_set_config(win, { title = (' Definitions · %d / %d '):format(index, #items) })
  end
  local function move(delta)
    select(math.max(1, math.min(#items, math.floor(vim.api.nvim_win_get_cursor(win)[1] / 2))) + delta)
  end
  local function map(keys, fn)
    vim.keymap.set('n', keys, fn, { buffer = buf, nowait = true, silent = true })
  end
  for _, key in ipairs({ 'j', '<Down>', '<Tab>' }) do map(key, function() move(1) end) end
  for _, key in ipairs({ 'k', '<Up>', '<S-Tab>' }) do map(key, function() move(-1) end) end
  map('<PageDown>', function() move(5) end)
  map('<PageUp>', function() move(-5) end)
  map('gg', function() select(1) end)
  map('G', function() select(#items) end)
  map('<CR>', function() finish(items[math.max(1, math.min(#items, math.floor(vim.api.nvim_win_get_cursor(win)[1] / 2)))], true) end)
  for _, key in ipairs({ '<Esc>', 'q', '<C-c>' }) do map(key, function() finish(nil, true) end) end
  map('<LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == win and mouse.line > 0 then
      if mouse.line > 1 and mouse.line < #lines then
        finish(items[math.floor(mouse.line / 2)], true)
      end
    else
      finish(nil, true)
      if mouse.winid ~= 0 and vim.api.nvim_win_is_valid(mouse.winid) then
        vim.api.nvim_set_current_win(mouse.winid)
      end
    end
  end)
  select(1)
end

return M
