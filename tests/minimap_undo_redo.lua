vim.opt.rtp:prepend(vim.fn.getcwd())
vim.env.VSVIM_ROOT=vim.fn.getcwd()
if vim.env.VSVIM_UNDO_CASE=='preloaded' then require('vim.treesitter.query') end
local config=require('vsvim.minimap.query_config');config.observe()
vim.o.termguicolors=true
vim.cmd('syntax enable | filetype plugin on')
local root=vim.fn.tempname()
vim.fn.mkdir(root,'p')
local path=root..'/fixture.lua'
local baseline={'local value = 1','return value'}
vim.fn.writefile(baseline,path)
local function git(args)
 local command={'git','-C',root};vim.list_extend(command,args)
 local result=vim.system(command,{text=true}):wait();assert(result.code==0,result.stderr)
end
git({'init','-q'});git({'add','fixture.lua'})
git({'-c','user.name=VSVim Test','-c','user.email=test@example.invalid','commit','-qm','HEAD baseline'})
vim.cmd.edit(vim.fn.fnameescape(path))
local attached_tick
local attach=vim.api.nvim_buf_attach
vim.api.nvim_buf_attach=function(buffer,send,options)
 if options.on_changedtick then attached_tick=options.on_changedtick end
 return attach(buffer,send,options)
end
local source=require('vsvim.minimap.source')
local rows=source.rows
local reads=0
source.rows=function(...) reads=reads+1;return rows(...) end
local notify=vim.rpcnotify
local worker_channel
vim.rpcnotify=function(channel,method,code,args)
 if method=='nvim_exec_lua' and type(code)=='string' and code:find('vsvim.minimap.worker',1,true) then worker_channel=channel end
 return notify(channel,method,code,args)
end
local provider=require('vsvim.minimap').provider()
local committed,staging,latest={},nil,nil
local function pull()
 local op=provider.next()
 if not op then return end
 if op.kind=='begin' then staging={begin=op,rows={}};latest=nil
 elseif op.kind=='lines' then for _,row in ipairs(op.lines) do staging.rows[#staging.rows+1]=row end
 elseif op.kind=='commit' then
  local result={};local b=staging.begin
  if b.base~=vim.NIL then for i=1,b.start-1 do result[#result+1]=committed[i] end end
  for _,row in ipairs(staging.rows) do result[#result+1]=row end
  if b.base~=vim.NIL then for i=b.start+b.delete,#committed do result[#result+1]=committed[i] end end
  committed=result;staging=nil
 elseif op.kind=='state' then latest=op end
end
local function expect(text,modified)
 assert(vim.wait(10000,function()
  pull()
  if staging or not latest or not committed[1] or committed[1].text~=text then return false end
  if not modified then return #latest.changes==0 end
  return #latest.changes==1 and latest.changes[1].start==1 and latest.changes[1]['end']==1 and latest.changes[1].kind=='modified'
 end,1),vim.inspect({text=text,rows=committed,state=latest}))
 if config.safe() then
  assert(worker_channel)
  assert(vim.deep_equal(vim.rpcrequest(worker_channel,'nvim_buf_get_lines',0,0,-1,false),vim.api.nvim_buf_get_lines(0,0,-1,false)),
   'worker mirror matches main across final-tick-only notifications')
 end
end
local ok,err=xpcall(function()
 expect(baseline[1],false)
 assert(config.safe()==(vim.env.VSVIM_UNDO_CASE~='preloaded'))
 local status=require('vsvim.minimap.worker').status()
 assert((status~=nil)==config.safe(),'exercise actual worker and exact-main configurations')
 local before=reads
 assert(attached_tick);attached_tick()
 vim.wait(20);assert(reads==before and not provider.target().busy,'idle committed tick does no extraction')
 vim.cmd('normal! ggA -- undo/redo probe')
 local changed=baseline[1]..' -- undo/redo probe'
 expect(changed,true)
 vim.cmd.write()
 expect(changed,true)
 assert(vim.deep_equal(vim.fn.readfile(path),{changed,baseline[2]}))
 vim.cmd.undo()
 expect(baseline[1],false)
 vim.cmd.redo()
 expect(changed,true)
 print('minimap actual provider edit/save/undo/redo source+HEAD bands, idle tick ('..(config.safe() and 'worker' or 'exact main')..'): PASS')
end,debug.traceback)
provider.stop()
vim.api.nvim_buf_attach=attach
source.rows=rows
vim.rpcnotify=notify
vim.api.nvim_buf_delete(0,{force=true})
vim.fn.delete(root,'rf')
assert(ok,err)
