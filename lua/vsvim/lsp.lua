local M = {}
M.servers = { 'pyright', 'ruby_lsp', 'gopls', 'rust_analyzer', 'ts_ls', 'lua_ls' }
local generation = 0

function M.definition()
  generation = generation + 1
  local request = generation
  local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local function current()
    return request == generation and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_get_current_win() == win
      and vim.api.nvim_win_get_buf(win) == buf
      and vim.api.nvim_buf_get_changedtick(buf) == changedtick
      and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
  end
  vim.lsp.buf.definition({ on_list = function(result)
    if not current() then return end
    local items, seen = {}, {}
    for _, item in ipairs(result.items) do
      local file = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
      local key = (vim.uv.fs_realpath(file) or file) .. ':' .. item.lnum
      if not seen[key] then items[#items + 1] = item; seen[key] = true end
    end
    local function jump(item)
      if not item or not current() then return end
      local target = item.bufnr and item.bufnr > 0 and item.bufnr or vim.fn.bufadd(item.filename)
      local ok, err = pcall(function()
        vim.fn.bufload(target)
        vim.cmd("normal! m'")
        vim.bo[target].buflisted = true
        vim.api.nvim_win_set_buf(win, target)
        vim.api.nvim_win_set_cursor(win, { item.lnum, 0 })
        vim.cmd('normal! zv')
      end)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
    end
    if #items == 1 then jump(items[1])
    elseif #items > 1 then
      require('vsvim.definition_picker').open(items, jump)
    end
  end })
end

function M.mouse_definition()
  local mouse = vim.fn.getmousepos()
  if mouse.winid == 0 or mouse.line <= 0 or mouse.column <= 0
    or not vim.api.nvim_win_is_valid(mouse.winid) then return end
  local buf = vim.api.nvim_win_get_buf(mouse.winid)
  if vim.bo[buf].buftype ~= '' then return end
  vim.cmd.stopinsert()
  vim.api.nvim_set_current_win(mouse.winid)
  vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, mouse.column - 1 })
  M.definition()
end

function M.setup()
  require('vsvim.lsp.manager').setup()
  vim.keymap.set('n', 'gd', M.definition, { desc = 'Go to definition' })
  vim.keymap.set({ 'n', 'i' }, '<D-LeftMouse>', M.mouse_definition, { desc = 'Go to clicked definition' })
  for _, event in ipairs({ '<D-LeftRelease>', '<D-LeftDrag>' }) do
    vim.keymap.set({ 'n', 'i' }, event, '<Nop>')
  end
end
return M
