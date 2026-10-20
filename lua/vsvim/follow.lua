local M = {}
local uv = vim.uv
local state = {enabled=false, ready=false}
local generation, worker, root_timer, pending, reading = 0, nil, nil, nil, false
local root_override, last_root, expected, navigating = nil, nil, nil, false
local saves, save_order = {}, {}
local MAX_FILE = 1024 * 1024
local script = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/follow_worker.lua'
local function redraw()
  vim.cmd('redrawstatus')
end
local function root()
  local ok, tree = pcall(require, 'svgtree')
  local active = ok and tree.root()
  if active then last_root = active end
  local chosen = root_override or active or last_root or vim.fn.getcwd()
  return uv.fs_realpath(chosen)
end
local function position()
  local view = vim.fn.winsaveview()
  return {win=vim.api.nvim_get_current_win(), buf=vim.api.nvim_get_current_buf(),
    cursor=vim.api.nvim_win_get_cursor(0), tick=vim.api.nvim_buf_get_changedtick(0),
    view={view.topline, view.leftcol, view.topfill}}
end
local function ordinary(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ''
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
    and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= 'vsvim_welcome'
end
local function contains(path)
  return state.root and path:sub(1, #state.root + 1) == state.root .. '/'
end
function M.status() return vim.deepcopy(state) end
function M.native_snapshot()
  return {enabled=state.enabled, ready=state.ready, reason=state.reason or ''}
end
local function stop(reason)
  generation = generation + 1
  state.enabled, state.ready, state.reason = false, false, reason
  pending, reading, expected = nil, false, nil
  saves, save_order = {}, {}
  if worker then worker:kill(15); worker = nil end
  if root_timer then root_timer:stop(); root_timer:close(); root_timer = nil end
  redraw()
end
local function fail(reason)
  stop(reason)
  vim.notify('Follow: ' .. reason, vim.log.levels.WARN)
end
local function clean_target(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.bo[buf].modified then
    fail('External changes conflict with unsaved edits in ' .. vim.fn.fnamemodify(path, ':t'))
    return false
  end
  return true
end
local function navigate(change)
  if not state.enabled or vim.fn.mode() ~= 'n' or not clean_target(change.path) then return end
  local win = vim.api.nvim_get_current_win()
  if not ordinary(win) and vim.bo.filetype ~= 'vsvim_welcome' then
    win = nil
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if ordinary(candidate) then win = candidate; break end
    end
    if not win then return end
  end
  navigating = true
  local ok, err = pcall(function()
    local buf = vim.fn.bufadd(change.path)
    vim.fn.bufload(buf)
    if vim.bo[buf].modified then error('Target has unsaved changes') end
    local undoreload = vim.o.undoreload
    vim.o.undoreload = -1
    -- Reload even when a tool preserves timestamps, while retaining the complete undo history.
    local refreshed, reload_error = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd('silent keepalt edit') end)
    vim.o.undoreload = undoreload
    if not refreshed then error(reload_error) end
    if vim.bo[buf].modified then error('Target has unsaved changes') end
    local markdown = package.loaded['vsvim.markdown']
    if markdown and markdown.previewing(buf) then markdown.toggle(buf) end
    vim.api.nvim_win_set_buf(win, buf)
    local row = math.min(change.line or 1, vim.api.nvim_buf_line_count(buf))
    vim.api.nvim_win_set_cursor(win, {math.max(1,row), 0})
    vim.api.nvim_win_call(win, function() vim.cmd('normal! zz') end)
    expected = position()
  end)
  navigating = false
  if not ok then fail(tostring(err)) end
end
local function can_navigate()
  if not state.enabled then return false end
  local selected = root()
  if selected ~= state.root then M.set_enabled(true); return false end
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then stop(); return false end
  if expected and not navigating and not vim.deep_equal(position(), expected) then
    local current = position()
    if ordinary(current.win) and (current.win ~= expected.win or current.buf ~= expected.buf
      or not vim.deep_equal(current.cursor, expected.cursor)
      or not vim.deep_equal(current.view, expected.view)
      or current.tick ~= expected.tick) then stop(); return false end
    expected = current
  end
  return mode == 'n'
end
local function drain()
  if not state.enabled or reading or not pending or vim.fn.mode() ~= 'n' then return end
  local change, token = pending, generation
  pending, reading = nil, true
  uv.fs_open(change.path, 'r', 0, function(err, fd)
    if err then vim.schedule(function() if token == generation then reading=false end end); return end
    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or stat.type ~= 'file' or stat.size > MAX_FILE then
        uv.fs_close(fd)
        vim.schedule(function() if token == generation then reading=false end end)
        return
      end
      uv.fs_read(fd, stat.size + 1, 0, function(read_err, bytes)
        uv.fs_close(fd)
        vim.schedule(function()
          if token ~= generation then return end
          reading = false
          if read_err or not bytes or #bytes > MAX_FILE or bytes:find('\0',1,true) then return end
          if vim.fn.sha256(bytes) ~= change.hash or saves[change.path] == change.hash then return end
          if pending then return end
          if uv.fs_realpath(change.path) ~= change.path then return end
          if not can_navigate() then
            if token == generation and state.enabled and not pending then pending=change end
            return
          end
          navigate(change)
        end)
      end)
    end)
  end)
end
local function tick()
  if can_navigate() then drain() end
end
function M.remember_root(path) last_root = path end
function M.set_root(path)
  root_override = path
  if state.enabled then M.set_enabled(true) end
end
function M.set_enabled(value)
  stop()
  if not value then return end
  state.root = root()
  if not state.root then fail('Project directory is unavailable'); return end
  state.enabled, state.reason = true, nil
  expected = position()
  local token, buffer = generation, ''
  worker = vim.system({vim.v.progpath, '-l', script, state.root}, {
    stdout=function(err, data)
      if err then vim.schedule(function() if token == generation then fail(tostring(err)) end end); return end
      if not data then return end
      buffer = buffer .. data
      if #buffer > 1024*1024 then
        vim.schedule(function() if token == generation then fail('Invalid watcher output') end end)
        return
      end
      while true do
        local finish = buffer:find('\n', 1, true)
        if not finish then break end
        local line = buffer:sub(1,finish-1)
        buffer = buffer:sub(finish+1)
        vim.schedule(function()
          if token ~= generation then return end
          local ok, event = pcall(vim.json.decode, line)
          if not ok then fail('Invalid watcher output'); return end
          if event.type == 'ready' then state.ready=true; redraw()
          elseif event.type == 'error' then fail(event.message)
          elseif event.type == 'change' and contains(event.path) then pending=event end
        end)
      end
    end,
  }, function(result)
    vim.schedule(function()
      if token == generation and state.enabled then
        fail('File watcher exited: ' .. (result.stderr or tostring(result.code)))
      end
    end)
  end)
  root_timer = uv.new_timer()
  root_timer:start(100,100,vim.schedule_wrap(tick))
  redraw()
end
function M.toggle() M.set_enabled(not state.enabled) end
function M.statusline()
  if vim.g.sprite_follow_native then return '    ' end
  return '%@v:lua.VSVimFollowClick@%#' .. (state.enabled and 'DiagnosticInfo' or 'Comment')
    .. '#  ⊕ Follow ' .. (state.enabled and 'On' or 'Off') .. '  %T%#StatusLine#'
end
function M.setup()
  local group = vim.api.nvim_create_augroup('VSVimFollow', {clear=true})
  vim.api.nvim_create_autocmd('BufWritePost', {group=group, callback=function(event)
    if not state.enabled then return end
    local path = uv.fs_realpath(vim.api.nvim_buf_get_name(event.buf))
    if not path or not contains(path) then return end
    local stat = uv.fs_stat(path)
    if not stat or stat.size > MAX_FILE then return end
    local fd = uv.fs_open(path,'r',0)
    if not fd then return end
    local bytes = uv.fs_read(fd,stat.size,0)
    uv.fs_close(fd)
    if bytes then
      if not saves[path] then save_order[#save_order+1]=path end
      saves[path]=vim.fn.sha256(bytes)
      if #save_order>256 then saves[table.remove(save_order,1)]=nil end
    end
  end})
  vim.api.nvim_create_autocmd({'InsertEnter','TextChanged','TextChangedI'}, {group=group, callback=function()
    if state.enabled and not navigating and (vim.fn.mode():sub(1,1) == 'i'
      or not expected or vim.api.nvim_get_current_buf() ~= expected.buf
      or vim.api.nvim_buf_get_changedtick(0) ~= expected.tick) then stop() end
  end})
  vim.api.nvim_create_autocmd({'CursorMoved','WinScrolled','BufEnter','WinEnter'}, {group=group, callback=tick})
  vim.api.nvim_create_autocmd('VimLeavePre', {group=group, callback=function() stop() end})
  _G.VSVimFollowClick = function(_,_,button) if button == 'l' then M.toggle() end end
  vim.api.nvim_create_user_command('VSVimFollowToggle', M.toggle, {force=true})
  vim.api.nvim_create_user_command('VSVimFollowOn', function() M.set_enabled(true) end, {force=true})
  vim.api.nvim_create_user_command('VSVimFollowOff', function() M.set_enabled(false) end, {force=true})
  vim.keymap.set('n','<leader>af',M.toggle,{desc='Follow external file changes'})
end
return M
