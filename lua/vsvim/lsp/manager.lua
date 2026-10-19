local M = {}
local entries, roots = {}, {}
local languages = { ruby = 'ruby_lsp', python = 'pyright', javascript = 'ts_ls', javascriptreact = 'ts_ls',
  typescript = 'ts_ls', typescriptreact = 'ts_ls', rust = 'rust_analyzer', go = 'gopls', gomod = 'gopls', gowork = 'gopls', lua = 'lua_ls' }
local markers = {
  ruby_lsp = { 'Gemfile', '.ruby-version', '.tool-versions', '.git' },
  pyright = { 'pyproject.toml', 'pyrightconfig.json', '.python-version', '.git' },
  ts_ls = { 'package.json', 'tsconfig.json', 'jsconfig.json', '.git' },
  rust_analyzer = { 'Cargo.toml', 'rust-project.json', '.git' },
  gopls = { 'go.work', 'go.mod', '.git' }, lua_ls = { '.luarc.json', '.luarc.jsonc', 'init.lua', '.git' },
}
local function context(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return end
  local name = vim.api.nvim_buf_get_name(buf)
  local server = languages[vim.bo[buf].filetype]
  if not server or name == '' then return end
  local config = vim.deepcopy(vim.lsp.config[server] or {})
  local explicit = vim.lsp.config._configs or {}
  config._explicit = vim.tbl_deep_extend('force', {}, explicit['*'] or {}, explicit[server] or {})
  local root = type(config.root_dir) == 'string' and config.root_dir or vim.fs.root(name, markers[server]) or vim.fs.dirname(name)
  if server == 'gopls' and not config._explicit.root_dir then root = vim.fs.root(name, 'go.work') or root end
  local custom_root = type(config._explicit.root_dir) == 'function' and config._explicit.root_dir or nil
  local cached = roots[buf]
  if custom_root and cached and cached.fn == custom_root and cached.name == name and cached.filetype == vim.bo[buf].filetype then
    root = cached.root or root
  else cached = nil end
  return { root = root, server = server, bufnr = buf, config = config, root_function = custom_root,
    root_request = cached }, name
end
local function log(e, message)
  e.reason = message
  vim.fn.mkdir(vim.fs.dirname(e.log), 'p')
  pcall(vim.fn.writefile, { os.date('!%FT%TZ') .. ' ' .. tostring(message) }, e.log, 'a')
end
function M.status()
  local result = {}
  for key, e in pairs(entries) do
    result[key] = { root = e.root, language = e.language, server = e.server, state = e.state,
      runtime = e.runtime, reason = e.reason, log = e.log, attempts = e.attempts }
  end
  return result
end
function M.ensure(buf, force, root_result)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local ctx, name = context(buf)
  if not ctx then return end
  if force and ctx.root_request and ctx.root_request.error and ctx.root_request ~= root_result then
    roots[buf] = nil
    ctx.root_request = nil
  end
  if ctx.root_function and not ctx.root_request then
    local request = { fn = ctx.root_function, name = name, filetype = vim.bo[buf].filetype }
    roots[buf] = request
    local function resolved(root)
      vim.schedule(function()
        if roots[buf] ~= request or request.error or request.root or not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_name(buf) ~= name then return end
        if type(root) ~= 'string' or root == '' then return end
        request.root = root
        M.ensure(buf, force, request)
      end)
    end
    local ok, returned = pcall(ctx.root_function, buf, resolved)
    if not ok then request.error = tostring(returned); M.ensure(buf, force, request)
    elseif type(returned) == 'string' then resolved(returned) end
    vim.defer_fn(function()
      if roots[buf] == request and not request.root and not request.error then
        request.error = 'Explicit project root resolution timed out'; M.ensure(buf, force, request)
      end
    end, vim.g.vsvim_lsp_root_timeout or 5000)
    return
  end
  if ctx.root_request and not ctx.root_request.root and not ctx.root_request.error then return end
  local environment = require('vsvim.lsp.environment')
  local identity = environment.fingerprint(ctx.root, ctx.server) .. vim.inspect(ctx.config)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.config._vsvim_environment and client.config._vsvim_environment ~= identity then vim.lsp.buf_detach_client(buf, client.id) end
  end
  local key = ctx.root .. ':' .. ctx.server
  local e = entries[key]
  if not force and #vim.api.nvim_list_uis() == 0 and not (e and e.headless) then return end
  if not e or e.identity ~= identity or (force and e.state == 'unavailable') then
    if e and e.client then local c = vim.lsp.get_client_by_id(e.client); if c then c:stop(true) end end
    e = { root = ctx.root, language = vim.bo[buf].filetype, server = ctx.server, identity = identity,
      attempts = 0, headless = force or (e and e.headless), generation = (e and e.generation or 0) + 1, buffers = {},
      log = vim.fn.stdpath('state') .. '/lsp/' .. vim.fn.sha256(key):sub(1, 16) .. '.log' }
    entries[key] = e
  end
  e.buffers[buf] = name
  if ctx.root_request and ctx.root_request.error then e.state = 'unavailable'; log(e, ctx.root_request.error); return end
  local function valid(b)
    local now, filename = context(b)
    return entries[key] == e and now and filename == e.buffers[b] and now.root == e.root and now.server == ctx.server
      and environment.fingerprint(now.root, now.server) .. vim.inspect(now.config) == identity
  end
  local function live_buffer()
    if valid(buf) then return buf end
    for b in pairs(e.buffers) do if valid(b) then return b end end
  end
  local function attach(client)
    for b in pairs(e.buffers) do if valid(b) then vim.lsp.buf_attach_client(b, client) end end
  end
  if e.state == 'ready' then attach(e.client); return end
  if e.state == 'resolving' or e.state == 'installing' or e.state == 'starting' or e.attempts >= 2 then return end
  e.attempts = e.attempts + 1
  e.state = 'resolving'
  e.client = nil
  local attempt = {}
  e.attempt = attempt
  local function owned() return entries[key] == e and e.attempt == attempt end
  local function active() return owned() and not attempt.failed and not attempt.exited end
  local finished = false
  local function fail(reason, recover)
    if not owned() or attempt.failed then return end
    attempt.failed = true
    finished = true
    e.state = 'unavailable'; log(e, reason)
    if recover and e.attempts < 2 then vim.defer_fn(function()
      if not owned() or not attempt.failed then return end
      local target = live_buffer()
      if target then M.ensure(target, false) end
    end, 500) end
  end
  ctx.report = function(state) if active() and not finished then e.state = state end end
  vim.defer_fn(function()
    if not finished and active() then fail('Environment resolution timed out', false) end
  end, vim.g.vsvim_lsp_resolve_timeout or 180000)
  environment.resolve(ctx, function(plan, err)
    if finished or not active() then return end
    finished = true
    if not vim.uv.fs_stat(ctx.root) then fail('Project directory no longer exists', false); return end
    local target = live_buffer()
    if not target then fail('No supported buffers remain in this project', false); return end
    if not plan then fail(err or 'Environment unavailable', false); return end
    e.runtime = plan.runtime; e.server = plan.server or ctx.server; e.state = 'starting'
    local config = vim.tbl_deep_extend('force', ctx.config, plan.config or {})
    config._explicit = nil; config.name = e.server; config.root_dir = ctx.root
    config._vsvim_environment = identity
    local original_init, original_exit, original_error = config.on_init, config.on_exit, config.on_error
    config.on_init = function(client, result)
      if not active() or (e.client and e.client ~= client.id) then client:stop(true); return end
      local live = false
      for b in pairs(e.buffers) do if valid(b) then live = true; break end end
      if not live then fail('No supported buffers remain in this project', false); client:stop(true); return end
      e.state = 'ready'; e.reason = nil; e.client = client.id; attach(client.id)
      if original_init then for _, cb in ipairs(type(original_init) == 'table' and original_init or { original_init }) do cb(client, result) end end
    end
    local exit_status
    config.on_exit = function(code, signal, id)
      if not owned() or attempt.failed or (e.client and e.client ~= id) then return end
      if exit_status then code, signal = exit_status[1], exit_status[2] end
      if original_exit then for _, cb in ipairs(type(original_exit) == 'table' and original_exit or { original_exit }) do pcall(cb, code, signal, id) end end
    end
    config.on_error = function(code, message)
      if not active() then return end
      log(e, 'LSP error ' .. code .. ': ' .. vim.inspect(message))
      if original_error then pcall(original_error, code, message) end
    end
    local command = config.cmd
    config.cmd = function(dispatchers, resolved)
      local exit = dispatchers.on_exit
      dispatchers.on_exit = function(code, signal)
        if active() then
          attempt.exited = true
          exit_status = { code, signal }
          vim.schedule(function() fail('Server exited code=' .. code .. ' signal=' .. signal, true) end)
        end
        -- Neovim otherwise emits a second generic startup warning after our project log records the true exit.
        exit(0, 0)
      end
      local ok, transport = pcall(function()
        if type(command) == 'function' then return command(dispatchers, resolved) end
        return vim.lsp.rpc.start(command, dispatchers, { cwd = config.cmd_cwd or ctx.root, env = config.cmd_env })
      end)
      if not ok then log(e, tostring(transport)); error(transport) end
      return transport
    end
    local ok, id = pcall(vim.lsp.start, config, { bufnr = target, attach = false, silent = true,
      reuse_client = function(client) return client.id == e.client and client.config.root_dir == e.root end })
    if not ok or not id then fail('Server start failed: ' .. tostring(e.reason or id), true); return end
    e.client = id
    vim.defer_fn(function()
      if active() and e.client == id and e.state == 'starting' then
        fail('Server initialization timed out', true)
        local client = vim.lsp.get_client_by_id(id); if client then client:stop(true) end
      end
    end, vim.g.vsvim_lsp_start_timeout or 30000)
  end)
end
function M.setup()
  local ok, mason = pcall(require, 'mason'); if ok then mason.setup({ PATH = 'skip' }) end
  local loaded, integration = pcall(require, 'mason-lspconfig')
  if loaded then integration.setup({ ensure_installed = {}, automatic_enable = false }) end
  vim.api.nvim_create_user_command('VSVimLspStatus', function()
    local lines = { 'VSVim language servers', '' }
    for _, e in pairs(M.status()) do
      vim.list_extend(lines, { e.root .. ' [' .. e.server .. '] ' .. e.state,
        'Runtime: ' .. tostring(e.runtime), 'Reason: ' .. tostring(e.reason), 'Log: ' .. e.log, '' })
    end
    local b = vim.api.nvim_create_buf(false, true); vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(b); vim.bo[b].modifiable = false
  end, {})
  vim.api.nvim_create_user_command('VSVimInstallLsp', function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_is_loaded(b) then M.ensure(b, true) end end
  end, {})
  local group = vim.api.nvim_create_augroup('VSVimLsp', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter', 'BufWritePost' }, { group = group,
    callback = function(ev) vim.schedule(function() M.ensure(ev.buf, false) end) end })
  vim.api.nvim_create_autocmd('UIEnter', { group = group, callback = function()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do M.ensure(b, false) end
  end })
end
return M
