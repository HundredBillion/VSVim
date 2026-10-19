local M = {}
local source=require('vsvim.minimap.source')
local git=require('vsvim.minimap.git')
local provider={}
local live, active, bridge, group=false,nil,nil,nil
local sequence, incarnation, token=0,0,0
local queue, committed, dirty={},nil,nil
local cancel_source, stop_git
local overlays={selection=vim.NIL,occurrences={},word=vim.NIL}
local changes={}
local state_dirty=false
local warned={}
local blocked={}
local refresh, rebuild
local function changed()
  if bridge and bridge.changed then bridge.changed() end
end
local function clear_jobs()
  token=token+1
  if cancel_source then cancel_source(); cancel_source=nil end
  if stop_git then stop_git(); stop_git=nil end
end
local function warn(buffer, message)
  if warned[buffer] then return end
  warned[buffer]=true
  vim.schedule(function() vim.notify(message,vim.log.levels.WARN) end)
end
local function hide()
  clear_jobs()
  active,committed,dirty=nil,nil,nil
  changes={}; overlays={selection=vim.NIL,occurrences={},word=vim.NIL}
  queue={{type='minimap',kind='hide'}}
  state_dirty=false
  if provider.on_target then provider.on_target(nil) end
  changed()
end
local function supported(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative==''
    and vim.bo[vim.api.nvim_win_get_buf(win)].buftype==''
end
local function state()
  local total=#committed.rows
  local viewport
  vim.api.nvim_win_call(active.window,function()
    viewport={math.max(1,math.min(total,vim.fn.line('w0'))),math.max(1,math.min(total,vim.fn.line('w$')))}
  end)
  local valid_changes={}
  for _,item in ipairs(changes) do
    if item.start<=total and item['end']<=total then valid_changes[#valid_changes+1]=item end
  end
  return {type='minimap',kind='state',target=active.target,generation=committed.generation,
    viewport=viewport,selection=overlays.selection,occurrences=overlays.occurrences,
    word=overlays.word,changes=valid_changes}
end
local function remap(rows, palette, fixed)
  local result={}
  for _,row in ipairs(rows) do
    local spans={}
    for _,span in ipairs(row.spans) do
      local value=palette[span[3]+1]
      local index
      for i,c in ipairs(fixed) do if c==value then index=i-1; break end end
      if not index then return nil end
      spans[#spans+1]={span[1],span[2],index}
    end
    result[#result+1]={text=row.text,spans=spans}
  end
  return result
end
local function stage(rows,palette,start,delete,total,full)
  sequence=sequence+1
  local generation=sequence
  local all={}
  if not full then for i=1,start-1 do all[#all+1]=committed.rows[i] end end
  for _,row in ipairs(rows) do all[#all+1]=row end
  if not full then for i=start+delete,#committed.rows do all[#all+1]=committed.rows[i] end end
  local storage=0
  for _,row in ipairs(all) do storage=storage+#row.text+#row.spans*24 end
  if storage>64*1024*1024 then
    blocked[active.buffer]=vim.api.nvim_buf_get_changedtick(active.buffer)
    warn(active.buffer,'Minimap source exceeds 64 MiB'); hide(); return
  end
  local pending_hide=queue[1] and queue[1].kind=='hide' and queue[1] or nil
  queue={{type='minimap',kind='begin',target=active.target,generation=generation,
    base=full and vim.NIL or committed.generation,start=start,delete=full and 0 or delete,
    insert=#rows,total=total,palette=palette,background=source.background()}}
  if pending_hide then table.insert(queue,1,pending_hide) end
  local chunk,offset,bytes={},0,0
  local function flush()
    if #chunk==0 then return end
    queue[#queue+1]={type='minimap',kind='lines',target=active.target,generation=generation,offset=offset,lines=chunk}
    offset=offset+#chunk; chunk={}; bytes=0
  end
  for _,row in ipairs(rows) do
    local size=#vim.json.encode(row)+1
    if #chunk==256 or bytes+size>250*1024 then flush() end
    chunk[#chunk+1]=row; bytes=bytes+size
  end
  flush()
  queue[#queue+1]={type='minimap',kind='commit',target=active.target,generation=generation}
  active.pending=generation
  active.prepared={rows=all,palette=palette,generation=generation}
  state_dirty=true
  changed()
end
rebuild=function(full)
  if not active then return end
  token=token+1
  local current_token=token
  if cancel_source then cancel_source() end
  local pending_hide=queue[1] and queue[1].kind=='hide'
  queue=pending_hide and {queue[1]} or {}; active.pending=nil; active.prepared=nil
  local buffer=active.buffer
  local total=vim.api.nvim_buf_line_count(buffer)
  if total>1000000 then
    blocked[buffer]=vim.api.nvim_buf_get_changedtick(buffer)
    warn(buffer,'Minimap source exceeds 1,000,000 lines'); hide(); return
  end
  full=full or not committed
  local first=full and 1 or dirty and dirty.first+1 or 1
  cancel_source=source.rows(buffer,first,total,function(rows,palette,error_message)
    if current_token~=token or not active then return end
    cancel_source=nil
    if not rows then
      blocked[buffer]=vim.api.nvim_buf_get_changedtick(buffer)
      warn(buffer,error_message); hide(); return
    end
    if not full then
      local translated=remap(rows,palette,committed.palette)
      if palette[1]~=committed.palette[1] or not translated then rebuild(true); return end
      rows=translated; palette=committed.palette
      local delete=#committed.rows-first+1
      while #rows>0 and delete>0 and vim.deep_equal(rows[#rows],committed.rows[first+delete-1]) do
        rows[#rows]=nil; delete=delete-1
      end
      local skip=0
      while skip<#rows and skip<delete and vim.deep_equal(rows[skip+1],committed.rows[first+skip]) do skip=skip+1 end
      if skip>0 then
        local trimmed={}
        for i=skip+1,#rows do trimmed[#trimmed+1]=rows[i] end
        rows=trimmed; first=first+skip; delete=delete-skip
      end
      stage(rows,palette,first,delete,total,false)
    else stage(rows,palette,1,0,total,true) end
  end)
end
local function edited(first,last,newlast)
  if not active then return end
  if provider.on_edit then provider.on_edit() end
  overlays={selection=vim.NIL,occurrences={},word=vim.NIL}
  changes={}
  if dirty then
    local delta=dirty.newlast-dirty.last
    local oldfirst=first<=dirty.first and first or first>=dirty.newlast and first-delta or dirty.first
    local oldlast=last<=dirty.first and last or last>=dirty.newlast and last-delta or dirty.last
    dirty.first=math.min(dirty.first,oldfirst)
    dirty.last=math.max(dirty.last,oldlast)
    dirty.newlast=dirty.last+delta+newlast-last
  else dirty={first=first,last=last,newlast=newlast} end
  rebuild(false)
end
refresh=function()
  if not live then return end
  if vim.g.vsvim_minimap==false then if active then hide() end; return end
  local win=vim.api.nvim_get_current_win()
  if not supported(win) then
    if active and supported(active.window) and vim.api.nvim_win_get_buf(active.window)==active.buffer
      and vim.api.nvim_win_get_tabpage(active.window)==vim.api.nvim_get_current_tabpage() then return end
    if active then hide() end
    return
  end
  local buffer=vim.api.nvim_win_get_buf(win)
  if blocked[buffer]==vim.api.nvim_buf_get_changedtick(buffer) then return end
  if active and active.window==win and active.buffer==buffer then return end
  local replacing=active~=nil
  clear_jobs()
  incarnation=incarnation+1
  active={buffer=buffer,window=win,target='b'..buffer..':w'..win..':'..incarnation}
  local identity=active.target
  committed,dirty=nil,nil; queue=replacing and {{type='minimap',kind='hide'}} or {}; changes={}
  overlays={selection=vim.NIL,occurrences={},word=vim.NIL}
  if provider.on_target then provider.on_target(provider.target()) end
  vim.api.nvim_buf_attach(buffer,false,{
    on_lines=function(_,_,_,first,last,newlast)
      if live and blocked[buffer] then
        blocked[buffer]=nil; vim.schedule(refresh); changed(); return true
      end
      if not live or not active or active.target~=identity then return true end
      edited(first,last,newlast)
    end,
    on_detach=function() vim.schedule(function() if active and active.target==identity then hide(); refresh() end end) end,
  })
  stop_git=git.watch(buffer,function(value)
    if active and active.target==identity then changes=value.changes; state_dirty=true; changed() end
  end)
  rebuild(true)
end
local function start()
  live=true
  group=vim.api.nvim_create_augroup('VSVimMinimap',{clear=true})
  vim.api.nvim_create_autocmd({'WinEnter','BufEnter','WinClosed','BufWinEnter','BufWipeout','TabEnter'},
    {group=group,callback=function() vim.schedule(refresh) end})
  vim.api.nvim_create_autocmd({'CursorMoved','CursorMovedI','WinScrolled','ModeChanged'},
    {group=group,callback=function() state_dirty=true; changed() end})
  vim.api.nvim_create_autocmd({'ColorScheme','OptionSet'}, {group=group,callback=function(event)
    if event.event=='ColorScheme' then blocked={} end
    if event.event=='ColorScheme' or vim.tbl_contains({'tabstop','vartabstop','ambiwidth','emoji','syntax','filetype','background'},event.match) then
      if active then rebuild(true) end
    end
  end})
  refresh()
end
function provider.next()
  if not live then start(); return nil end
  refresh()
  local op=table.remove(queue,1)
  if op then
    if op.kind=='commit' and active then
      committed=active.prepared; active.prepared=nil; active.pending=nil; dirty=nil
    end
    return op
  end
  if active and committed and not cancel_source and state_dirty then
    state_dirty=false
    local value=state()
    if #value.changes>100000 or #value.occurrences>100000 or #vim.json.encode(value)>4*1024*1024 then
      warn(active.buffer,'Minimap overlays exceed state bounds'); hide(); return table.remove(queue,1)
    end
    return value
  end
end
function provider.target()
  if not active then return nil end
  return {buffer=active.buffer,window=active.window,target=active.target,
    generation=committed and committed.generation or nil,pending=active.pending,
    busy=cancel_source~=nil or active.pending~=nil,
    total=committed and #committed.rows or vim.api.nvim_buf_line_count(active.buffer)}
end
function provider.set_overlays(value)
  for _,key in ipairs({'selection','occurrences','word'}) do if value[key]~=nil then overlays[key]=value[key] end end
  state_dirty=true; changed()
end
local selection = require('vsvim.minimap.selection')
selection.attach(provider)
function provider.dispatch(event)
  local target = provider.target()
  if not target or target.busy or not target.generation or event.target ~= target.target
    or event.generation ~= target.generation then return end
  local row = event.action == 'reveal' and event.line or event.action == 'scroll' and event.topline
  if type(row) ~= 'number' or row ~= math.floor(row) or row < 1 or row > target.total then return end
  selection.browse(target.window, event)
  state_dirty=true; changed()
end
function provider.before_input(event) selection.before_input(event) end
function provider.stop()
  clear_jobs()
  live=false; active=nil; committed=nil; queue={}; dirty=nil; state_dirty=false
  if group then pcall(vim.api.nvim_del_augroup_by_id,group); group=nil end
  if provider.on_target then provider.on_target(nil) end
end
function M.provider() return provider end
function M.setup()
  if vim.g.vsvim_minimap==nil then vim.g.vsvim_minimap=true end
  local ok,native=pcall(require,'sprite.minimap')
  if ok and type(native.setup)=='function' then bridge=native end
  local function configure()
    if bridge then bridge.setup(vim.g.vsvim_minimap~=false and provider or nil)
    else provider.stop() end
  end
  vim.api.nvim_create_user_command('VSVimMinimapToggle',function()
    vim.g.vsvim_minimap=vim.g.vsvim_minimap==false
    configure()
  end,{desc='Toggle the native Sprite minimap',force=true,bar=true})
  configure()
end
return M
