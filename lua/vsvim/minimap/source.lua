local M = {}
local main=require('vsvim.minimap.source_main')
local config=require('vsvim.minimap.query_config')
local worker=require('vsvim.minimap.worker')
config.observe()
M.background=main.background
M.palette_index=main.palette_index
M.storage_bytes=main.storage_bytes
function M.rows(buffer,first,last,done,options)
  local function exact_main()
    local start=options and not options.full and 1 or first
    return main.rows(buffer,start,last,function(rows,palette,message)
      done(rows,palette,message,{first=start,last=last,total=vim.api.nvim_buf_line_count(buffer)})
    end)
  end
  if not config.safe() then return exact_main() end
  local cancelled,fell_back=false,false
  local unsubscribe
  local cancel_read,cancel_format
  local rows,palette={},{}
  local colors={}
  local function fallback(message)
    if cancelled or fell_back then return end
    fell_back=true
    if unsubscribe then unsubscribe() end
    local bounded=message and message:find('Minimap source exceeds',1,true)
    if not bounded and config.safe() then config.use_main('Worker extraction requires the exact editor path: '..tostring(message)) end
    worker.stop()
    if cancel_format then cancel_format() end
    if bounded then done(nil,nil,message) else cancel_read=exact_main() end
  end
  unsubscribe=config.on_unsafe(function() vim.schedule(function() fallback('fallback') end) end)
  cancel_read=worker.read(buffer,first,last,function(chunk,next_chunk)
    if cancelled then return end
    local highlights=chunk.highlights
    for row,captures in pairs(highlights) do
      if type(captures)=='table' then
        local count=#captures
        local next_index=1
        for _,cap in ipairs(captures) do
          local name=cap[4]
          if colors[name]==nil then colors[name]=main.color(name) or false end
          if colors[name] then
            cap[4]=colors[name]
            captures[next_index]=cap
            next_index=next_index+1
          end
        end
        for index=next_index,count do captures[index]=nil end
      else highlights[row]=nil end
    end
    cancel_format=main.rows(buffer,chunk.first,chunk.last,function(formatted,local_palette,message)
      if cancelled then return end
      if not formatted then fallback(message);return end
      require('vsvim.minimap.work').start(function() return not cancelled end,function(checkpoint)
        for _,row in ipairs(formatted) do
          for _,span in ipairs(row.spans) do span[3]=main.palette_index(palette,local_palette[span[3]+1]) end
          rows[#rows+1]=row
          checkpoint()
        end
        return true
      end,function() next_chunk() end)
    end,highlights)
    if #palette==0 then palette[1]=main.color('Normal') or '#bcbec4' end
  end,function(range)
    if unsubscribe then unsubscribe() end
    if not cancelled then done(rows,palette,nil,range) end
  end,fallback,not options or options.full)
  return function()
    cancelled=true
    if unsubscribe then unsubscribe() end
    if cancel_read then cancel_read() end
    if cancel_format then cancel_format() end
  end
end
function M.watch(buffer,callback)
  local stopped=false
  local stop
  local function fallback()
    if stopped then return end
    if stop then stop() end
    stop=require('vsvim.minimap.git').watch(buffer,callback)
  end
  local unsubscribe=config.on_unsafe(function() vim.schedule(fallback) end)
  if config.safe() then stop=worker.watch(buffer,callback) else fallback() end
  return function() stopped=true;unsubscribe();if stop then stop() end end
end
function M.stop() worker.stop() end
function M.commit(buffer) worker.commit(buffer) end
return M
