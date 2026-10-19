vim.opt.rtp:prepend(vim.fn.getcwd())
local source=require('vsvim.minimap.source')
local a=vim.api.nvim_get_current_buf()
local b=vim.api.nvim_create_buf(true,false)
local spans={}
for i=0,255 do spans[#spans+1]={i,i+1,i%2} end
local row={text=string.rep('x',512),spans=spans}
local count=math.floor(64*1024*1024/source.storage_bytes(row.text,#row.spans))
local lines={};for i=1,count do lines[i]='x' end
vim.api.nvim_buf_set_lines(a,0,-1,false,lines)
vim.api.nvim_buf_set_lines(b,0,-1,false,{'blocked','second row'})
local warnings={}
vim.notify=function(message) warnings[#warnings+1]=message end
source.watch=function() return function() end end
source.rows=function(buffer,first,last,done)
  local cancelled=false
  vim.schedule(function()
    if cancelled then return end
    if buffer==b then done(nil,nil,'controlled source bound failure');return end
    local rows={};for i=first,last do rows[#rows+1]=row end
    done(rows,{'#111111','#222222'},nil,{first=first,last=last,total=vim.api.nvim_buf_line_count(buffer)})
  end)
  return function() cancelled=true end
end
local provider=require('vsvim.minimap').provider()
local function next_kind(kind)
  local found
  assert(vim.wait(10000,function()
    local op=provider.next()
    if op and op.kind==kind then found=op;return true end
  end,1),'waiting for '..kind)
  return found
end
next_kind('commit')
local initial=provider.target()
assert(initial.total==count)
vim.api.nvim_buf_set_lines(a,count,count,false,{'x'})
next_kind('hide')
assert(provider.target()==nil,'final splice must include retained row storage')
assert(vim.wait(1000,function() return #warnings==1 end,1))
for _=1,5 do provider.next();vim.api.nvim_exec_autocmds('BufEnter',{buffer=a}) end
vim.wait(20)
assert(#warnings==1,'bound warning occurs once per unchanged buffer')
print('minimap canonical full/splice storage boundary and warning: PASS')
-- Changing A clears its block; B remains blocked across later focus changes.
vim.api.nvim_buf_set_lines(a,0,-1,false,{'a','second row'})
next_kind('commit')
vim.api.nvim_set_current_buf(b)
next_kind('hide')
assert(vim.wait(1000,function() provider.next();return provider.target()==nil end,1))
assert(vim.wait(1000,function() return #warnings==2 end,1))
vim.api.nvim_set_current_buf(a)
next_kind('commit')
local target=provider.target()
provider.set_overlays({selection={1,2},word='a',occurrences={1}})
vim.api.nvim_set_current_buf(b)
next_kind('hide')
assert(provider.target()==nil,'blocked ordinary buffer cannot retain another file map')
local before=vim.api.nvim_win_get_cursor(0)
provider.dispatch({target=target.target,generation=target.generation,action='reveal',line=2})
assert(vim.deep_equal(before,vim.api.nvim_win_get_cursor(0)),'stale navigation is ignored')
for _=1,5 do assert(provider.next()==nil) end
assert(#warnings==2,'revisiting an unchanged blocked buffer does not retry or warn')
provider.stop()
print('minimap A/blocked B/A/blocked B hides source, overlays and stale actions: PASS')
