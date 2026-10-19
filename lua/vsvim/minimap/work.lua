local M = {}
function M.start(valid, work, done, buffer)
  local deadline
  local function checkpoint()
    if vim.uv.hrtime() >= deadline then coroutine.yield() end
  end
  local thread=coroutine.create(function() return work(checkpoint) end)
  local function batch()
    if not valid() then return end
    deadline=vim.uv.hrtime()+2000000
    local ok, result, extra, message
    local function resume() ok,result,extra,message=coroutine.resume(thread) end
    if buffer then vim.api.nvim_buf_call(buffer,resume) else resume() end
    if not ok then done(nil,nil,tostring(result))
    elseif coroutine.status(thread)=='dead' then vim.schedule(function()
      if valid() then done(result,extra,message) end
    end)
    else vim.schedule(batch) end
  end
  vim.schedule(batch)
end
return M
