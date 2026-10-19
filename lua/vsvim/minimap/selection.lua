local M = {}
local current, preserved, notify, owner, group
local occurrences, matches, word, signature = {}, {}, nil, nil
local epoch = 0
local ns = vim.api.nvim_create_namespace('VSVimMinimapSelection')
local update, activate, refresh_matches
local selection_option_to_restore, setting_selection_option
local function publish()
  local rows = current and current.segments or {}
  local value = {selection=#rows > 0 and {rows[1][1][2], rows[#rows][2][2]} or vim.NIL,
    occurrences=occurrences, word=word or vim.NIL}
  if notify then notify(value) end
  vim.cmd.redraw({bang=true})
  return value
end
local visual = {v='v', V='V', ['\22']='\22', s='v', S='V', ['\19']='\22'}
local function set_selection_option(value)
  setting_selection_option = true
  vim.o.selection = value
  setting_selection_option = false
end
local function release_selection_option()
  if not selection_option_to_restore then return end
  local value = selection_option_to_restore
  selection_option_to_restore = nil
  set_selection_option(value)
end
local function window(win)
  return win == 0 and vim.api.nvim_get_current_win() or win
end
local function valid(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ''
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ''
end
function M.capture(win)
  win = window(win)
  if not valid(win) then return end
  return vim.api.nvim_win_call(win, function()
    local mode = vim.fn.mode()
    if not visual[mode] then return end
    local anchor, cursor = vim.fn.getpos('v'), vim.fn.getpos('.')
    local opts = {type=visual[mode], exclusive=vim.o.selection == 'exclusive', eol=true}
    local segments = vim.fn.getregionpos(anchor, cursor, opts)
    return {buffer=vim.api.nvim_win_get_buf(win), window=win,
      changedtick=vim.api.nvim_buf_get_changedtick(0), anchor=anchor, cursor=cursor,
      mode=mode, segments=segments, exclusive=opts.exclusive, selection_option=vim.o.selection,
      curswant=vim.fn.winsaveview().curswant}
  end)
end
function M.clear()
  epoch = epoch + 1
  current, preserved, signature, word = nil, nil, nil, nil
  occurrences, matches = {}, {}
  if notify then notify({selection=vim.NIL, occurrences={}, word=vim.NIL}) end
  vim.schedule(function() vim.cmd.redraw({bang=true}) end)
end
local function scan(saved, selected)
  local id, row, offset = epoch, 1, 0
  local pattern = '\\C\\V\\<' .. vim.fn.escape(selected, '\\') .. '\\>'
  local total = vim.api.nvim_buf_line_count(saved.buffer)
  local function batch()
    if id ~= epoch or not valid(saved.window) or vim.api.nvim_win_get_buf(saved.window) ~= saved.buffer
      or vim.api.nvim_buf_get_changedtick(saved.buffer) ~= saved.changedtick then return end
    local started, count = vim.uv.hrtime(), 0
    vim.api.nvim_win_call(saved.window, function()
      while row <= total and count < 256 and vim.uv.hrtime() - started < 4000000 do
        local line = vim.api.nvim_buf_get_lines(saved.buffer, row-1, row, false)[1]
        local found = vim.fn.matchstrpos(line, pattern, offset)
        if found[2] < 0 then row, offset, count = row+1, 0, count+1
        else
          if not matches[row] then matches[row] = {}; occurrences[#occurrences+1] = row end
          matches[row][#matches[row]+1] = {found[2], found[3]}
          offset = found[3]
          -- Let the source owner enforce the wire bound instead of truncating matches.
          if #occurrences > 100000 then row = total+1; break end
        end
      end
    end)
    publish()
    if row <= total then vim.schedule(batch) end
  end
  vim.schedule(batch)
end
refresh_matches = function()
  epoch = epoch + 1
  occurrences, matches, word = {}, {}, nil
  local saved = current
  if not saved then publish(); return end
  if visual[saved.mode] == 'v' and #saved.segments == 1
    and saved.segments[1][2][3] - saved.segments[1][1][3] <= 1024 then
    vim.api.nvim_win_call(saved.window, function()
      local texts = vim.fn.getregion(saved.anchor, saved.cursor,
        {type='v', exclusive=saved.exclusive})
      local text = texts[1]
      if text and #text <= 1024 and text ~= '' and vim.fn.matchstr(text, '^\\k\\+$') == text then
        word = text
        scan(saved, text)
      end
    end)
  end
  publish()
end
update = function(win)
  if not valid(win) or current and (vim.api.nvim_win_get_buf(win) ~= current.buffer
    or vim.api.nvim_buf_get_changedtick(current.buffer) ~= current.changedtick) then M.clear(); return end
  if win ~= vim.api.nvim_get_current_win() or preserved then return end
  if not visual[vim.fn.mode()] then release_selection_option() end
  local mode = vim.fn.mode()
  local key = visual[mode] and vim.inspect({win, vim.fn.getpos('v'), vim.fn.getpos('.'), mode,
    vim.api.nvim_buf_get_changedtick(0), vim.o.selection, vim.bo.iskeyword}) or nil
  if key == signature then return end
  M.clear()
  signature = key
  if not key then return end
  current = M.capture(win)
  if not current then return end
  refresh_matches()
end
activate = function(win)
  if owner == win and group then return end
  if group then vim.api.nvim_del_augroup_by_id(group) end
  owner = win
  group = vim.api.nvim_create_augroup('VSVimMinimapSelection', {clear=true})
  vim.api.nvim_create_autocmd('ModeChanged', {group=group, callback=function()
    -- A mapping can start another selection before scheduled callbacks run.
    if not visual[vim.v.event.new_mode:sub(1,1)] then release_selection_option() end
  end})
  vim.api.nvim_create_autocmd({'CursorMoved','CursorMovedI','ModeChanged'}, {
    group=group, callback=function() vim.schedule(function()
      if owner then update(owner) end
    end) end})
  vim.api.nvim_create_autocmd({'TextChanged','TextChangedI','BufEnter','WinEnter','WinClosed','BufWipeout'}, {
    group=group, callback=function()
      if not valid(win)
        or current and (vim.api.nvim_win_get_buf(win) ~= current.buffer
        or vim.api.nvim_buf_get_changedtick(current.buffer) ~= current.changedtick) then M.clear() end
    end})
  vim.api.nvim_create_autocmd('ColorScheme', {group=group, callback=function()
    vim.api.nvim_set_hl(0, 'VSVimMinimapOccurrence', {bg='#505050', default=true})
    publish()
  end})
  vim.api.nvim_create_autocmd('OptionSet', {group=group, pattern={'iskeyword','selection'},
    callback=function(event)
      if setting_selection_option then return end
      if event.match == 'selection' then selection_option_to_restore = nil end
      if preserved then
        if event.match == 'iskeyword' and vim.api.nvim_get_current_buf() == current.buffer then refresh_matches() end
      else update(win) end
    end})
end
function M.state(win)
  win = window(win)
  if not valid(win) then return {selection=vim.NIL, occurrences={}, word=vim.NIL} end
  activate(win)
  update(win)
  local rows = current and current.segments or {}
  return {selection=#rows > 0 and {rows[1][1][2], rows[#rows][2][2]} or vim.NIL,
    occurrences=occurrences, word=word or vim.NIL}
end
function M.browse(win, action)
  win = window(win)
  if not valid(win) then return end
  activate(win)
  update(win)
  if not preserved then
    current = M.capture(win)
    preserved = current ~= nil
  end
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_call(win, function()
    if visual[vim.fn.mode()] then vim.cmd('normal! ' .. string.char(27)) end
    local total = vim.api.nvim_buf_line_count(0)
    local row = math.max(1, math.min(total, action.line or action.topline))
    vim.api.nvim_win_set_cursor(win, {row, 0})
    if action.action == 'reveal' then vim.cmd('normal! zz')
    else
      local view = vim.fn.winsaveview()
      view.topline, view.topfill, view.skipcol = row, 0, 0
      vim.fn.winrestview(view)
    end
  end)
end
function M.before_input(event)
  if not preserved or not current or vim.api.nvim_get_current_win() ~= current.window then return end
  local key = (event.key or event.keys or ''):lower()
  local escape = key == 'escape' or key == 'ctrl-[' or key:match('^<esc>')
    or key:match('^<c%-%[>') or key:sub(1,1) == '\27'
  if (event.type == 'mouse' and event.action == 'press'
    and (event.button == 'left' or event.button == 'right' or event.button == 'middle'))
    or (event.type == 'input' and escape) then
    M.clear(); return
  end
  if event.type ~= 'input' and event.type ~= 'paste' then return end
  local saved = current
  if not saved or not valid(saved.window) or vim.api.nvim_win_get_buf(saved.window) ~= saved.buffer
    or vim.api.nvim_buf_get_changedtick(saved.buffer) ~= saved.changedtick then M.clear(); return end
  -- Restore native mode before the bridge queues the original keyboard or paste input.
  preserved = nil
  if vim.o.selection ~= saved.selection_option then
    -- Keep captured endpoint semantics until native Visual/Select editing finishes.
    selection_option_to_restore = vim.o.selection
    set_selection_option(saved.selection_option)
  end
  vim.api.nvim_set_current_win(saved.window)
  vim.fn.setpos('.', saved.anchor)
  vim.cmd('normal! ' .. visual[saved.mode])
  vim.fn.setpos('.', saved.cursor)
  local view = vim.fn.winsaveview()
  view.curswant = saved.curswant
  vim.fn.winrestview(view)
  if saved.mode == 's' or saved.mode == 'S' or saved.mode == '\19' then vim.cmd('normal! \7') end
end
local function decorate(buffer, row, first, last, highlight, priority)
  vim.api.nvim_buf_set_extmark(buffer, ns, row, first,
    {end_row=row, end_col=last, hl_group=highlight, priority=priority, ephemeral=true})
end
vim.api.nvim_set_decoration_provider(ns, {
  on_win=function(_, win, buffer)
    return current ~= nil and current.window == win and current.buffer == buffer
      and vim.api.nvim_buf_get_changedtick(buffer) == current.changedtick
  end,
  on_line=function(_, _, buffer, row)
    for _, span in ipairs(matches[row+1] or {}) do
      decorate(buffer, row, span[1], span[2], 'VSVimMinimapOccurrence', 150)
    end
    if not preserved then return end
    local firstrow = current.segments[1] and current.segments[1][1][2]
    local segment = firstrow and current.segments[row+2-firstrow]
    if not segment then return end
    local line = vim.api.nvim_buf_get_lines(buffer, row, row+1, false)[1]
    local first, last = segment[1][3]-1, segment[2][3]-1
    local startoff, endoff = segment[1][4], segment[2][4]
    local function character(col)
      return vim.fn.strcharpart(line:sub(col+1),0,1)
    end
    local function partial(col, from, untilcell)
      local startcell = vim.fn.strdisplaywidth(line:sub(1,col))
      local width = col < #line and vim.fn.strdisplaywidth(character(col),startcell) or 0
      local finish = untilcell > 0 and untilcell or width
      local limit = vim.api.nvim_win_get_width(current.window)
      from, finish = math.min(from,limit), math.min(finish,limit)
      if finish <= from then return end
      vim.api.nvim_buf_set_extmark(buffer, ns, row, col, {
        virt_text={{string.rep(' ',from),'Normal'},{string.rep(' ',finish-from),'Visual'}},
        virt_text_pos='overlay', hl_mode='replace', priority=200, ephemeral=true})
    end
    local finish = last < #line and last + #character(last) or #line
    local partial_only = startoff > 0 and first == last
    if startoff > 0 then
      partial(first, startoff, first == last and endoff or 0)
      first = first + #character(first)
    end
    if endoff > 0 then
      if first <= last and not partial_only then partial(last, 0, endoff) end
      finish = last
    end
    if first < finish then decorate(buffer, row, first, finish, 'Visual', 200) end
    if visual[current.mode] == 'V' or (#line == 0 and first == 0 and endoff == 0) then
      vim.api.nvim_buf_set_extmark(buffer, ns, row, math.min(first,#line), {
        end_row=row+1, end_col=0, hl_group='Visual', hl_eol=true, priority=200, ephemeral=true})
    end
  end,
})
vim.api.nvim_set_hl(0, 'VSVimMinimapOccurrence', {bg='#505050', default=true})
function M.attach(provider)
  notify = provider.set_overlays
  local on_target, on_edit = provider.on_target, provider.on_edit
  provider.on_target = function(target)
    if on_target then on_target(target) end
    release_selection_option()
    M.clear()
    if group then vim.api.nvim_del_augroup_by_id(group); group=nil end
    owner = nil
    if target then activate(target.window); update(target.window) end
  end
  provider.on_edit = function()
    if on_edit then on_edit() end
    M.clear()
  end
end
return M
