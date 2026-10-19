local root=assert(vim.env.VSVIM_ROOT)
vim.opt.rtp:prepend(root)
require('vsvim.minimap.query_config').observe()
_G.minimap_metrics={source={},callbacks={},ops={},started=vim.uv.hrtime()}
local function now()
  local sec,usec=vim.uv.gettimeofday()
  return sec*1e9+usec*1000
end
local schedule=vim.schedule
vim.schedule=function(fn)
  local info=debug.getinfo(fn,'Sl')
  local key=info.short_src..':'..info.linedefined
  schedule(function()
    local before=vim.uv.hrtime();fn()
    local elapsed=(vim.uv.hrtime()-before)/1e6
    local m=minimap_metrics.callbacks[key] or {count=0,max_ms=0,total_ms=0}
    minimap_metrics.callbacks[key]=m
    m.count=m.count+1;m.max_ms=math.max(m.max_ms,elapsed);m.total_ms=m.total_ms+elapsed
  end)
end
local source=require('vsvim.minimap.source')
local rows=source.rows
source.rows=function(buffer,first,last,done,options)
  local started=vim.uv.hrtime()
  local record={first=first,last=last,unix_ns=now()}
  minimap_metrics.source[#minimap_metrics.source+1]=record
  return rows(buffer,first,last,function(...)
    record.ms=(vim.uv.hrtime()-started)/1e6
    record.range=select(4,...)
    done(...)
  end,options)
end
local provider=require('vsvim.minimap').provider()
local next_op=provider.next
provider.next=function(...)
  local start=vim.uv.hrtime()
  local op=next_op(...)
  local ms=(vim.uv.hrtime()-start)/1e6
  minimap_metrics.provider_max_ms=math.max(minimap_metrics.provider_max_ms or 0,ms)
  if op then
    minimap_metrics.ops[#minimap_metrics.ops+1]={kind=op.kind,generation=op.generation,unix_ns=now(),bytes=#vim.json.encode(op),rows=op.lines and #op.lines or 0}
  end
  return op
end

local worker=require('vsvim.minimap.worker')
local receive=worker.receive
worker.receive=function(...)
  local started=vim.uv.hrtime()
  receive(...)
  minimap_metrics.receive_max_ms=math.max(minimap_metrics.receive_max_ms or 0,(vim.uv.hrtime()-started)/1e6)
end
local resume=coroutine.resume
coroutine.resume=function(thread,...)
  local start=vim.uv.hrtime()
  local result={resume(thread,...)}
  local elapsed=(vim.uv.hrtime()-start)/1e6
  if elapsed>3 then
    local trace=debug.traceback(thread)
    if trace:find('/vsvim/minimap',1,true) then
      minimap_metrics.slow_slices=minimap_metrics.slow_slices or {}
      minimap_metrics.slow_slices[#minimap_metrics.slow_slices+1]={ms=elapsed,trace=trace}
    end
  end
  return unpack(result)
end
local dispatch=provider.dispatch
provider.dispatch=function(event)
  minimap_metrics.actions=minimap_metrics.actions or {}
  local started=now()
  dispatch(event)
  minimap_metrics.actions[#minimap_metrics.actions+1]={unix_ns=started,done_ns=now(),event=event}
end
