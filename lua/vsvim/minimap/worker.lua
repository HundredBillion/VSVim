local M = {}
local current, serial= nil,0
local function send(owner, code, args)
  if current==owner and owner.job then vim.rpcnotify(owner.job,'nvim_exec_lua',code,args) end
end
function M.stop()
  local old=current
  current=nil
  if old and old.group then pcall(vim.api.nvim_del_augroup_by_id,old.group) end
  if old and old.job then vim.fn.jobstop(old.job) end
end
local function merge(dirty,first,last,newlast)
  if not dirty then return {first=first,last=last,newlast=newlast} end
  local delta=dirty.newlast-dirty.last
  local oldfirst=first<=dirty.first and first or first>=dirty.newlast and first-delta or dirty.first
  local oldlast=last<=dirty.first and last or last>=dirty.newlast and last-delta or dirty.last
  dirty.first=math.min(dirty.first,oldfirst);dirty.last=math.max(dirty.last,oldlast)
  dirty.newlast=dirty.last+delta+newlast-last
  return dirty
end
local function ensure(buffer)
  if current and current.buffer==buffer then return current end
  M.stop();serial=serial+1
  local owner={buffer=buffer,id=serial,request=0,dirty={first=0,last=1,newlast=vim.api.nvim_buf_line_count(buffer)}}
  current=owner
  local root=assert(vim.env.VSVIM_ROOT or vim.api.nvim_get_runtime_file('lua/vsvim/minimap/worker.lua',false)[1]:gsub('/lua/vsvim/minimap/worker.lua$',''))
  owner.job=vim.fn.jobstart({vim.v.progpath,'--embed','--headless','--noplugin','-u','NONE','--cmd','set noswapfile noundofile shadafile=NONE',
    '--cmd','lua vim.opt.rtp:prepend('..vim.inspect(root)..')'},{rpc=true,on_exit=function()
      if current==owner then owner.job=nil;if owner.on_error then owner.on_error('Minimap worker exited') end end
    end})
  if owner.job<=0 then current=nil;error('Could not start minimap worker') end
  send(owner,"require('vsvim.minimap.worker').boot(...)",{owner.id,vim.o.runtimepath})
  owner.group=vim.api.nvim_create_augroup('VSVimMinimapWorker'..owner.id,{clear=true})
  local function metadata()
    if current==owner then send(owner,"require('vsvim.minimap.worker').metadata(...)",
      {vim.api.nvim_buf_get_name(buffer),vim.bo[buffer].endofline,vim.bo[buffer].fileformat}) end
  end
  vim.api.nvim_create_autocmd({'BufWritePost','BufFilePost'},{group=owner.group,callback=function(event)
    if event.buf==buffer then metadata() end
  end})
  vim.api.nvim_create_autocmd('OptionSet',{group=owner.group,pattern={'endofline','fileformat'},callback=function()
    if vim.api.nvim_get_current_buf()==buffer then metadata() end
  end})
  vim.api.nvim_buf_attach(buffer,false,{on_lines=function(_,_,_,first,last,newlast)
    if current~=owner then return true end
    owner.dirty=merge(owner.dirty,first,last,newlast)
  end,on_detach=function() if current==owner then M.stop() end end})
  return owner
end
function M.read(buffer,first,last,on_chunk,done,on_error,full)
  local owner=ensure(buffer)
  owner.request=owner.request+1
  local request=owner.request
  owner.on_chunk,owner.done,owner.on_error=on_chunk,done,on_error
  local tick=vim.api.nvim_buf_get_changedtick(buffer)
  local function valid() return current==owner and request==owner.request and vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_buf_get_changedtick(buffer)==tick end
  require('vsvim.minimap.work').start(valid,function(checkpoint)
    local dirty=owner.dirty
    if dirty then
      local first_chunk=true
      local chunk,bytes,chunk_row={},0,dirty.first
      local function flush()
        if #chunk==0 then return end
        send(owner,"require('vsvim.minimap.worker').replace(...)",{chunk_row,first_chunk and dirty.last or chunk_row,chunk})
        first_chunk=false;chunk_row=chunk_row+#chunk;chunk={};bytes=0
      end
      local total_bytes=0
      local block=dirty.first
      while block<dirty.newlast do
        local finish=math.min(dirty.newlast,block+64)
        local offset=vim.api.nvim_buf_get_offset(buffer,block)
        while finish>block+1 and vim.api.nvim_buf_get_offset(buffer,finish)-offset>64*1024 do
          finish=block+math.floor((finish-block)/2)
        end
        local lines=vim.api.nvim_buf_get_lines(buffer,block,finish,false)
        for index,line in ipairs(lines) do
        local row=block+index-1
        total_bytes=total_bytes+#line
        if total_bytes>64*1024*1024 then error('Minimap source exceeds 64 MiB') end
        if #line>128*1024 then
          flush()
          send(owner,"require('vsvim.minimap.worker').start_line(...)",{row,first_chunk and dirty.last or row})
          for offset=1,#line,128*1024 do
            send(owner,"require('vsvim.minimap.worker').line_part(...)",{line:sub(offset,offset+128*1024-1)})
            checkpoint()
          end
          send(owner,"require('vsvim.minimap.worker').end_line()",{})
          first_chunk=false;chunk_row=row+1
        else
          if #chunk==64 or bytes+#line+8>128*1024 then flush() end
          chunk[#chunk+1]=line;bytes=bytes+#line+8
        end
        checkpoint()
        end
        block=finish
      end
      flush()
      if first_chunk then send(owner,"require('vsvim.minimap.worker').replace(...)",{dirty.first,dirty.last,{}}) end
      owner.dirty=nil
    end
    local syntax_signature
    vim.api.nvim_buf_call(buffer,function() syntax_signature=vim.fn.execute('silent syntax list')..vim.fn.execute('silent syntax sync') end)
    if #syntax_signature>64*1024 then owner.on_error('fallback');return true end
    send(owner,"require('vsvim.minimap.worker').prepare(...)",{request,first,last,full,
      require('vsvim.minimap.query_config').snapshot(),vim.bo[buffer].filetype,vim.api.nvim_buf_get_name(buffer),vim.bo[buffer].endofline,vim.treesitter.language.get_lang(vim.bo[buffer].filetype),vim.bo[buffer].syntax,syntax_signature,vim.bo[buffer].fileformat})
    return true
  end,function(result,_,message) if not result and owner.on_error then owner.on_error(message) end end)
  return function() if current==owner and owner.request==request then owner.request=owner.request+1 end end
end
function M.next(id,request)
  if current and current.id==id and current.request==request then
    send(current,"require('vsvim.minimap.worker').advance(...)",{request})
  end
end
function M.receive(id,request,kind,value)
  local owner=current
  if not owner or owner.id~=id then return end
  if kind=='git' then if owner.git then owner.git(value) end;return end
  if owner.request~=request then return end
  if not require('vsvim.minimap.query_config').safe() then
    if owner.on_error then owner.on_error('fallback') end
    return
  end
  if kind=='chunk' then
    local ok,message=pcall(owner.on_chunk,value,function() M.next(id,request) end)
    if not ok then owner.on_error(tostring(message)) end
  elseif kind=='done' then owner.done(value)
  elseif kind=='error' then owner.on_error(value) end
end
function M.commit(buffer)
  if current and current.buffer==buffer then send(current,"require('vsvim.minimap.worker').ack()",{}) end
end
function M.watch(buffer,callback)
  local owner=ensure(buffer)
  owner.git=callback
  return function() if current==owner then owner.git=nil end end
end
function M.status() return current and {pid=vim.fn.jobpid(current.job),buffer=current.buffer,request=current.request,dirty=current.dirty} or nil end

local server
local function reply(request,kind,value)
  vim.rpcnotify(1,'nvim_exec_lua',"require('vsvim.minimap.worker').receive(...)",{server.id,request,kind,value})
end
function M.boot(id,runtimepath)
  vim.o.swapfile=false;vim.o.undofile=false;vim.o.shadafile='NONE'
  vim.o.runtimepath=runtimepath
  server={id=id,request=0,affected_first=1,affected_last=1,bytes=0}
end
function M.replace(first,last,lines)
  local bytes=server.bytes
  for _,line in ipairs(vim.api.nvim_buf_get_lines(0,first,last,false)) do bytes=bytes-#line end
  for _,line in ipairs(lines) do bytes=bytes+#line end
  if bytes>64*1024*1024 then server.bound_error='Minimap source exceeds 64 MiB';return end
  server.bytes=bytes
  local delta=#lines-(last-first)
  if server.affected_last and first<server.affected_last then server.affected_last=math.max(first+1,server.affected_last+delta) end
  server.affected_first=math.min(server.affected_first or first+1,first+1)
  server.affected_last=math.max(server.affected_last or 1,first+#lines)
  vim.api.nvim_buf_set_lines(0,first,last,false,lines)
end
function M.metadata(filename,endofline,fileformat)
  vim.bo.endofline=endofline
  vim.bo.fileformat=fileformat
  if vim.api.nvim_buf_get_name(0)~=filename then vim.api.nvim_buf_set_name(0,filename) end
  vim.api.nvim_exec_autocmds('BufWritePost',{buffer=vim.api.nvim_get_current_buf()})
end
function M.start_line(first,last) server.parts={};server.part_first=first;server.part_last=last end
function M.line_part(part) server.parts[#server.parts+1]=part end
function M.end_line()
  local line=table.concat(server.parts);server.parts=nil
  M.replace(server.part_first,server.part_last,{line})
end
function M.ack() server.affected_first=nil;server.affected_last=nil end
function M.prepare(request,first,last,full,queries,filetype,filename,endofline,language,syntax,syntax_signature,fileformat)
  server.request=request
  if server.bound_error then reply(request,'error',server.bound_error);return end
  for _,registration in ipairs(queries.languages) do vim.treesitter.language.register(registration.lang,registration.filetypes) end
  for _,query in ipairs(queries.queries) do
    local text=query.raw and query.text or '\n'..query.text
    server.queries=server.queries or {}
    local key=query.lang..':'..query.group
    if server.queries[key]~=text then vim.treesitter.query.set(query.lang,query.group,text);server.queries[key]=text end
  end
  if vim.bo.filetype~=filetype then vim.bo.filetype=filetype end
  if vim.api.nvim_buf_get_name(0)~=filename then vim.api.nvim_buf_set_name(0,filename) end
  if server.syntax~=syntax then vim.cmd('syntax enable');vim.bo.syntax=syntax;server.syntax=syntax end
  local function normalize(value) return value:gsub('links to [^\n]+',''):gsub('%s+',' ') end
  local standard_syntax=vim.fn.execute('silent syntax list')..vim.fn.execute('silent syntax sync')
  local conservative=normalize(standard_syntax)~=normalize(syntax_signature)
  vim.bo.endofline=endofline
  vim.bo.fileformat=fileformat
  local ok,parser=pcall(vim.treesitter.get_parser,0,language)
  if ok and parser then
    if server.parser~=parser then
      server.parser=parser
      parser:register_cbs({on_changedtree=function(ranges)
        for _,r in ipairs(ranges) do
          server.affected_first=math.min(server.affected_first or r[1]+1,r[1]+1)
          server.affected_last=math.max(server.affected_last or r[4]+1,r[4]+1)
        end
      end},true)
    end
    parser:parse()
    parser:for_each_tree(function(tree) if tree:root():has_error() then conservative=true end end)
  else parser=nil;conservative=true end
  if not server.stop_git then
    server.stop_git=require('vsvim.minimap.git').watch(vim.api.nvim_get_current_buf(),function(value) reply(0,'git',value) end)
  end
  local begin=(full or conservative) and 1 or math.min(first,server.affected_first or first)
  local finish=(full or conservative) and last or math.min(last,math.max(first,server.affected_last or first))
  server.range={first=begin,last=finish,total=vim.api.nvim_buf_line_count(0)}
  server.row=begin
  server.cursors={}
  if parser then parser:for_each_tree(function(tree,langtree)
    local lang=langtree:lang()
    local query=vim.treesitter.query.get(lang,'highlights')
    if query then server.cursors[#server.cursors+1]={iter=query:iter_captures(tree:root(),0,begin-1,finish),query=query,lang=lang,active={}} end
  end) end
  M.advance(request)
end
function M.advance(request)
  if server.request~=request then return end
  local begin=server.row
  local finish=math.min(server.range.last,begin+127)
  if begin>finish then reply(request,'done',server.range);return end
  local result={}
  local capture_bytes=0
  for _,cursor in ipairs(server.cursors) do
    local active={}
    local function append(cap)
      for row=math.max(begin,cap.sr+1),math.min(finish,cap.er+1) do
        capture_bytes=capture_bytes+#cap.name+64
        if capture_bytes>128*1024 then return false end
        result[row]=result[row] or {}
        result[row][#result[row]+1]={row==cap.sr+1 and cap.sc or 0,row==cap.er+1 and cap.ec or math.huge,cap.priority,cap.name}
      end
      if cap.er+1>finish then active[#active+1]=cap end
      return true
    end
    for _,cap in ipairs(cursor.active) do if not append(cap) then reply(request,'error','fallback');return end end
    while true do
      local cap=cursor.pending
      if not cap then
        local id,node,metadata=cursor.iter()
        if not id then break end
        local range=vim.treesitter.get_range(node,0,metadata[id])
        cap={sr=range[1],sc=range[2],er=range[4],ec=range[5],
          priority=tonumber((metadata[id] or {}).priority or metadata.priority) or 100,
          name='@'..cursor.query.captures[id]..'.'..cursor.lang}
      end
      cursor.pending=nil
      if cap.sr+1>finish then cursor.pending=cap;break end
      if not append(cap) then reply(request,'error','fallback');return end
    end
    cursor.active=active
  end
  server.row=finish+1
  reply(request,'chunk',{first=begin,last=finish,highlights=result})
end
local prepare=M.prepare
function M.prepare(...)
  local ok,message=pcall(prepare,...)
  if not ok then reply(server.request,'error',tostring(message)) end
end
local advance=M.advance
function M.advance(...)
  local ok,message=pcall(advance,...)
  if not ok then reply(server.request,'error',tostring(message)) end
end
return M
