vim.opt.rtp:prepend(vim.fn.getcwd())
vim.env.VSVIM_ROOT=vim.fn.getcwd()
if vim.env.VSVIM_WORKER_CASE=='preloaded' then require('vim.treesitter.query') end
local config=require('vsvim.minimap.query_config')
config.observe()
vim.o.termguicolors=true
vim.cmd('syntax enable | filetype plugin on')
vim.bo.filetype='lua'
vim.bo.syntax='lua'
if vim.env.VSVIM_WORKER_CASE=='preloaded' then assert(not config.safe());print('minimap worker preloaded-query fallback: PASS');return end
if vim.env.VSVIM_WORKER_CASE=='predicate' then
  vim.treesitter.query.add_predicate('vsvim-test?',function() return true end,{force=true})
  assert(not config.safe());print('minimap worker custom predicate fallback: PASS');return
end
assert(config.safe(),vim.inspect(config.status()))
local source=require('vsvim.minimap.source')
local direct=require('vsvim.minimap.source_main')
local worker=require('vsvim.minimap.worker')
local buffer=vim.api.nvim_get_current_buf()
local function extract(module,first,last,options)
  local done,rows,palette,range,message=false
  module.rows(buffer,first,last,function(r,p,err,meta) rows,palette,message,range,done=r,p,err,meta,true end,options)
  assert(vim.wait(15000,function() return done end,1),'worker timeout: '..vim.inspect(worker.status()))
  assert(rows,message)
  local canonical={}
  for i,row in ipairs(rows) do
    canonical[i]={text=row.text,spans={}}
    for _,span in ipairs(row.spans) do canonical[i].spans[#canonical[i].spans+1]={span[1],span[2],palette[span[3]+1]} end
  end
  return canonical,range
end
if vim.env.VSVIM_WORKER_CASE=='capture_bound' then
  vim.api.nvim_buf_set_lines(buffer,0,-1,false,{'local value=1'})
  vim.treesitter.query.set('lua','highlights',string.rep('((identifier) @constant)\n',2000))
  assert(config.safe())
  local result=extract(source,1,1,{full=true})
  assert(not config.safe())
  assert(vim.deep_equal(result,extract(direct,1,1)))
  assert(worker.status()==nil)
  print('minimap worker bounded capture fallback: PASS')
  return
end
local lines={}
for i=1,1000 do lines[i]='local value = "hé界" -- comment' end
lines[1]='--[[';lines[900]=']]'
vim.api.nvim_buf_set_lines(buffer,0,-1,false,lines)
local cache=extract(source,1,#lines,{full=true})
assert(vim.deep_equal(cache,extract(direct,1,#lines)))
source.commit(buffer)
print('minimap worker full source and trusted runtime readers: PASS')
local function edit(first,last,newlines,label)
  vim.api.nvim_buf_set_lines(buffer,first,last,false,newlines)
  local total=vim.api.nvim_buf_line_count(buffer)
  local patch,range=extract(source,first+1,total,{full=false})
  local updated={}
  for i=1,range.first-1 do updated[#updated+1]=cache[i] end
  for _,row in ipairs(patch) do updated[#updated+1]=row end
  local delta=#newlines-(last-first)
  for i=range.last-delta+1,#cache do updated[#updated+1]=cache[i] end
  local full=extract(direct,1,total)
  assert(vim.deep_equal(updated,full),label..': '..vim.inspect(range))
  cache=full;source.commit(buffer)
end
edit(0,1,{'local value = "hé界"'},'remove opener')
edit(0,1,{'--[['},'restore opener')
edit(899,900,{']] local extra="outside"'},'change closer')
edit(499,500,{'comment content changed'},'same-structure comment edit')
edit(10,10,{'comment inserted row'},'insert inside multiline capture')
edit(0,1,{'--[=['},'change delimiter')
print('minimap worker multiline incremental differential: 6 PASS')
vim.api.nvim_set_hl(0,'@string.lua',{fg='#c125ac'})
assert(vim.deep_equal(extract(source,1,vim.api.nvim_buf_line_count(buffer),{full=true}),extract(direct,1,vim.api.nvim_buf_line_count(buffer))))
vim.cmd('syntax match VSVimWorkerCustom /value/ | highlight VSVimWorkerCustom guifg=#ab3c21')
assert(vim.deep_equal(extract(source,1,vim.api.nvim_buf_line_count(buffer),{full=true}),extract(direct,1,vim.api.nvim_buf_line_count(buffer))))
print('minimap worker actual theme and custom syntax: PASS')
vim.api.nvim_buf_set_lines(buffer,0,-1,false,{'local foo = 1','local bar = 2','local tail = 3'})
vim.api.nvim_set_hl(0,'@variable.lua',{})
vim.cmd([[syntax match VSVimWorkerLookahead /foo = 1\nlocal bar/ | highlight VSVimWorkerLookahead guifg=#123abc]])
cache=extract(source,1,3,{full=true});source.commit(buffer)
vim.api.nvim_buf_set_lines(buffer,1,2,false,{'local baz = 2'})
local prior,prior_range=extract(source,2,3,{full=false})
assert(prior_range.first==1,'custom lookahead must reformat earlier rows')
assert(vim.deep_equal(prior,extract(direct,1,3)))
print('minimap worker custom syntax lookahead invalidation: PASS')
local default_query
for _,query in ipairs(config.snapshot().queries) do if query.lang=='lua' and query.group=='highlights' then default_query=query.text end end
assert(default_query)
vim.treesitter.query.set('lua','highlights','((identifier) @constant)')
assert(config.safe())
assert(vim.deep_equal(extract(source,1,3,{full=true}),extract(direct,1,3)))
vim.treesitter.query.set('lua','highlights',nil)
assert(vim.deep_equal(extract(source,1,3,{full=true}),extract(direct,1,3)))
vim.treesitter.query.set('lua','highlights',default_query)
print('minimap worker serializable query.set replay and removal: PASS')
vim.api.nvim_buf_set_lines(buffer,0,-1,false,{'local value = "'..string.rep('a',200000)..'"','bad '..string.char(255)..' text'})
assert(vim.deep_equal(extract(source,1,2,{full=true}),extract(direct,1,2)))
print('minimap worker large-line fragments and invalid UTF-8: PASS')
local original_display=vim.o.display
for _,display in ipairs({'lastline','lastline,uhex'}) do
  vim.o.display=display
  vim.api.nvim_buf_set_lines(buffer,0,-1,false,{'-- controls '..string.char(13,0,27,127)..'\t end'})
  local actual=extract(source,1,1,{full=true})
  assert(vim.deep_equal(actual,extract(direct,1,1)))
  assert(not actual[1].text:find('[\r\n\t%z]'))
end
vim.o.display=original_display
print('minimap worker CR/NUL/ESC/DEL display fidelity: PASS')
local stale=false
local cancel=source.rows(buffer,1,vim.api.nvim_buf_line_count(buffer),function() stale=true end,{full=true})
cancel();vim.wait(20)
assert(not stale)
assert(vim.deep_equal(extract(source,1,vim.api.nvim_buf_line_count(buffer),{full=true}),extract(direct,1,vim.api.nvim_buf_line_count(buffer))))
local pid=worker.status().pid
source.stop()
assert(worker.status()==nil)
assert(vim.wait(2000,function() return not vim.uv.kill(pid,0) end,1))
print('minimap worker cancellation and owned process shutdown: PASS')
local function interrupted_transfer(incremental)
  local root=vim.fn.tempname();vim.fn.mkdir(root,'p')
  local lines={};for i=1,300 do lines[i]='value_'..i..' = '..i end
  vim.fn.writefile(lines,root..'/fixture.lua')
  local function git(...)
    local result=vim.system({'git','-C',root,...},{text=true}):wait()
    assert(result.code==0,result.stderr);return vim.trim(result.stdout)
  end
  git('init','-q');git('add','fixture.lua')
  git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture')
  local head=git('rev-parse','HEAD')
  vim.api.nvim_buf_set_name(buffer,root..'/fixture.lua')
  vim.api.nvim_buf_set_lines(buffer,0,-1,false,lines)
  local latest
  local stop=worker.watch(buffer,function(value) latest=value end)
  if incremental then
    extract(source,1,300,{full=true});source.commit(buffer)
    local changed={};for i=1,200 do changed[i]=lines[i] end
    table.insert(changed,150,'pending_a = 1');table.insert(changed,151,'pending_b = 2')
    vim.api.nvim_buf_set_lines(buffer,0,200,false,changed)
  end
  local work=require('vsvim.minimap.work');local start=work.start
  work.start=function(valid,fn,done,buf)
    return start(valid,function(checkpoint)
      return fn(function() checkpoint();coroutine.yield() end)
    end,done,buf)
  end
  local notify=vim.rpcnotify
  local interrupted,channel,finished,message,cancel
  vim.rpcnotify=function(job,method,code,args)
    notify(job,method,code,args)
    if code:find('.replace',1,true) then
      channel=job
      if not interrupted then
        interrupted=true
        vim.schedule(function()
          cancel()
          vim.api.nvim_buf_set_lines(buffer,0,1,false,{'value_1 = 999'})
          vim.api.nvim_buf_set_lines(buffer,149,149,false,{'added_a = 1','added_b = 2'})
          worker.read(buffer,1,vim.api.nvim_buf_line_count(buffer),function(_,next_chunk) next_chunk() end,
            function() finished=true end,function(err) message=err;finished=true end,true)
        end)
      end
    end
  end
  cancel=worker.read(buffer,1,vim.api.nvim_buf_line_count(buffer),function(_,next_chunk) next_chunk() end,
    function() error('cancelled transfer completed') end,function(err) message=err;finished=true end,true)
  assert(vim.wait(5000,function() return finished end,1),'interrupted worker timeout')
  vim.rpcnotify=notify;work.start=start
  assert(interrupted and not message,message)
  assert(vim.deep_equal(vim.rpcrequest(channel,'nvim_buf_get_lines',0,0,-1,false),vim.api.nvim_buf_get_lines(buffer,0,-1,false)),
    'partial transfer must not duplicate or delete the mirror tail')
  local total=vim.api.nvim_buf_line_count(buffer)
  assert(vim.deep_equal(extract(source,1,total,{full=true}),extract(direct,1,total)))
  assert(vim.wait(3000,function()
    return latest and latest.head==head and #latest.changes==2
      and latest.changes[1].start==1 and latest.changes[1].kind=='modified'
      and latest.changes[2].start==150 and latest.changes[2].kind=='added'
  end,1),vim.inspect(latest))
  stop();source.stop();vim.fn.delete(root,'rf')
end
interrupted_transfer(false)
interrupted_transfer(true)
print('minimap worker delayed initial/incremental cancellation mirror, captures and Git: PASS')
local query=vim.treesitter.query.get('lua','highlights')
assert(not config.safe())
query.query:disable_capture('string')
assert(vim.deep_equal(extract(source,1,vim.api.nvim_buf_line_count(buffer),{full=true}),extract(direct,1,vim.api.nvim_buf_line_count(buffer))))
assert(worker.status()==nil)
vim.treesitter.query.set('lua','highlights','((identifier) @constant)')
assert(vim.deep_equal(extract(source,1,vim.api.nvim_buf_line_count(buffer),{full=true}),extract(direct,1,vim.api.nvim_buf_line_count(buffer))))
print('minimap worker external query mutation and query.set fallback: PASS')
