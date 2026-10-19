local M = {}
local pending = {}
function M.run(argv, opts, done)
  opts = vim.tbl_extend('force', { text = true, timeout = vim.g.vsvim_lsp_process_timeout or 15000 }, opts or {})
  local ok, proc = pcall(vim.system, argv, opts, vim.schedule_wrap(function(result)
    done(result.code == 0 and result.stdout or nil,
      result.code ~= 0 and ('exit=' .. result.code .. ' signal=' .. result.signal .. ': ' .. (result.stderr or '')) or nil)
  end))
  if not ok then vim.schedule(function() done(nil, tostring(proc)) end) end
end
function M.once(key, work, done)
  if pending[key] then table.insert(pending[key], done); return end
  pending[key] = { done }
  work(function(result, err)
    local waiters = pending[key]; pending[key] = nil
    for _, callback in ipairs(waiters) do callback(result, err) end
  end)
end
return M
