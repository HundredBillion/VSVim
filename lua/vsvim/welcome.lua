local M = {}
local ns = vim.api.nvim_create_namespace('VSVimWelcome')

function M.open_on_startup()
  local args = vim.fn.argv()
  if #args > 1 or (#args == 1 and vim.fn.isdirectory(args[1]) ~= 1) then return end
  local old = vim.api.nvim_get_current_buf()
  if vim.bo[old].modified or vim.bo[old].buftype ~= '' then return end
  if #args == 0 and vim.api.nvim_buf_get_name(old) ~= '' then return end
  if #args == 1 then vim.api.nvim_set_current_dir(vim.fn.fnamemodify(args[1], ':p')) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'vsvim_welcome'
  vim.bo[buf].swapfile = false
  local window = vim.api.nvim_get_current_win()
  local saved = {}
  for _, option in ipairs({ 'number', 'relativenumber', 'signcolumn', 'cursorline', 'colorcolumn', 'list' }) do
    saved[option] = vim.wo[window][option]
  end
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = 'no'
  vim.wo.cursorline = false
  vim.wo.colorcolumn = ''
  vim.wo.list = false
  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local win = vim.fn.bufwinid(buf)
    if win == -1 then return end
    local width = vim.api.nvim_win_get_width(win)
    local height = vim.api.nvim_win_get_height(win)
    local project = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
    if project == '' then project = '/' end
    local rows = {
      { 'V S V I M', 'Function' },
      { 'A quiet place to read code.', 'Comment' },
      { '', 'Normal' },
      { project, 'Title' },
      { '', 'Normal' },
      { 'Space e     Explorer', 'Normal' },
      { 'Space g s   Source control', 'Normal' },
      { ':enew       New buffer', 'Comment' },
      { ':q          Close', 'Comment' },
    }
    local top = math.max(0, math.floor((height - #rows) / 3))
    local lines = {}
    for _ = 1, top do lines[#lines + 1] = '' end
    for _, row in ipairs(rows) do
      local text = vim.fn.strcharpart(row[1], 0, math.max(0, width - 2))
      lines[#lines + 1] = string.rep(' ', math.max(0, math.floor((width - vim.fn.strdisplaywidth(text)) / 2))) .. text
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, row in ipairs(rows) do
      vim.api.nvim_buf_set_extmark(buf, ns, top + i - 1, 0, { end_col = #lines[top + i], hl_group = row[2] })
    end
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end
  local group = vim.api.nvim_create_augroup('VSVimWelcome', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized', 'ColorScheme', 'DirChanged' }, {
    group = group, callback = render,
  })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    group = group, buffer = buf, once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(window) then
        for option, value in pairs(saved) do vim.wo[window][option] = value end
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group, buffer = buf, once = true,
    callback = function() vim.api.nvim_del_augroup_by_id(group) end,
  })
  render()
  if vim.api.nvim_buf_is_valid(old) then vim.api.nvim_buf_delete(old, { force = false }) end
end

return M
