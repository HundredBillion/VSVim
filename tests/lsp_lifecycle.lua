local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p'); root = vim.uv.fs_realpath(root)
vim.env.XDG_STATE_HOME = root .. '/state'
package.loaded.mason = { setup = function() end }
package.loaded['mason-lspconfig'] = { setup = function() end }
local global_methods = { 'window/showMessage', 'window/showMessageRequest' }
local original_handlers, global_messages = {}, 0
local function global_handler() global_messages = global_messages + 1; return vim.NIL end
for _, method in ipairs(global_methods) do
  original_handlers[method] = vim.lsp.handlers[method]
  vim.lsp.handlers[method] = global_handler
end
local manager = require('vsvim.lsp.manager')
local env = require('vsvim.lsp.environment')
local pending, resolutions = {}, 0
local original = env.resolve
env.resolve = function(ctx, done) resolutions = resolutions + 1; pending[#pending + 1] = { ctx = ctx, done = done } end
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
vim.g.vsvim_lsp_start_timeout = 100
manager.setup()
local function buffer(project, name)
  local dir = root .. '/' .. project; vim.fn.mkdir(dir, 'p')
  if not vim.uv.fs_stat(dir .. '/.luarc.json') then vim.fn.writefile({ '{}' }, dir .. '/.luarc.json') end
  local b = vim.fn.bufadd(dir .. '/' .. name); vim.fn.bufload(b); vim.bo[b].filetype = 'lua'
  return b, dir
end
local function status(dir)
  return assert(manager.status()[dir .. ':lua_ls'])
end
local a, dir = buffer('one', 'a.lua')
manager.ensure(a, true); manager.ensure(a, true)
assert(resolutions == 1, 'duplicate opens share resolution')
local b = buffer('one', 'b.lua'); manager.ensure(b, true)
assert(resolutions == 1)
local c, other = buffer('two', 'c.lua'); manager.ensure(c, true)
assert(resolutions == 2, 'independent projects resolve independently')
local stale = table.remove(pending, 1)
vim.api.nvim_buf_set_name(a, other .. '/moved.lua')
stale.done({ runtime = 'stale', config = { cmd = { '/bin/cat' } } })
assert(status(dir).state == 'starting', 'a valid waiting sibling starts even when the original buffer was renamed')
assert(#vim.lsp.get_clients({ bufnr = a }) == 0, 'renamed buffer is not attached to the old project')
vim.api.nvim_buf_set_name(a, dir .. '/a.lua')
vim.fn.writefile({ '{"runtime.version":"Lua 5.4"}' }, dir .. '/.luarc.json')
manager.ensure(a, true)
assert(resolutions == 3, 'changed configuration gets a fresh generation')
local changed = table.remove(pending)
changed.done(nil, 'fixture incompatible runtime')
assert(status(dir).state == 'unavailable' and status(dir).reason:find('incompatible'))
manager.ensure(a, true)
assert(resolutions == 4, 'explicit retry resets failure budget')
local retry = table.remove(pending)
retry.done({ runtime = 'missing binary', config = { cmd = { '/definitely/not/a/server' } } })
assert(vim.wait(3000, function() return resolutions == 5 end), 'startup failure permits one recovery')
local recovery = table.remove(pending)
recovery.done({ runtime = 'missing binary', config = { cmd = { '/definitely/not/a/server' } } })
assert(status(dir).attempts == 2)
manager.ensure(a, false)
assert(resolutions == 5, 'unchanged failures stop at two automatic attempts')
assert(#notifications == 0, vim.inspect(notifications))
local dead, deleted = buffer('deleted', 'd.lua')
manager.ensure(dead, true)
local gone = table.remove(pending)
vim.fn.delete(deleted, 'rf')
env.resolve = original
gone.done({ runtime = 'deleted', config = { cmd = { '/bin/cat' } } })
assert(status(deleted).state == 'unavailable', 'deleted directories fail quietly')
assert(#notifications == 0)

local script = root .. '/server.py'
vim.fn.writefile(vim.split([[
import json, sys, time, os
if len(sys.argv) > 2:
    with open(sys.argv[2], "w") as f: f.write(os.getcwd())
mode = sys.argv[1]
if mode == 'crash': sys.exit(23)
if mode == 'hang': time.sleep(30); sys.exit(0)
while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line: sys.exit(0)
        if line == b'\r\n': break
        key, value = line.decode().split(':', 1)
        headers[key.lower()] = value.strip()
    data = json.loads(sys.stdin.buffer.read(int(headers['content-length'])))
    if data.get('method') == 'initialize':
        for method in ('window/showMessage', 'window/showMessageRequest'):
            message = {'jsonrpc': '2.0', 'method': method, 'params': {'type': 1, 'message': 'fixture managed startup failure'}}
            if method.endswith('Request'): message['id'] = 'fixture-request'
            payload = json.dumps(message).encode()
            sys.stdout.buffer.write(('Content-Length: %d\r\n\r\n' % len(payload)).encode() + payload)
            sys.stdout.buffer.flush()
        time.sleep(0.15)
        response = json.dumps({'jsonrpc': '2.0', 'id': data['id'], 'result': {'capabilities': {}}}).encode()
        sys.stdout.buffer.write(('Content-Length: %d\r\n\r\n' % len(response)).encode() + response)
        sys.stdout.buffer.flush()
]], '\n', { plain = true }), script)
local modes, explicit_messages = {}, 0
env.resolve = function(ctx, done)
  resolutions = resolutions + 1
  local handlers
  if modes[ctx.root] == 'explicit' then
    handlers = {}
    for _, method in ipairs({'window/showMessage', 'window/showMessageRequest'}) do
      handlers[method] = function() explicit_messages = explicit_messages + 1; return vim.NIL end
    end
  end
  done({ runtime = 'fixture', config = { handlers = handlers, cmd = { '/usr/bin/python3', script, modes[ctx.root] or 'ready', root .. '/cwd-' .. vim.fn.sha256(ctx.root):sub(1, 8) } } })
end
vim.g.vsvim_lsp_start_timeout = 1000
local before_setup, before_dir = buffer('global-before-setup', 'main.lua')
manager.ensure(before_setup, true)
assert(vim.wait(4000, function() return status(before_dir).state == 'ready' end))
assert(global_messages == 2, 'both global handlers installed before setup must retain precedence')
for _, method in ipairs(global_methods) do vim.lsp.handlers[method] = original_handlers[method] end
local first, ready_dir = buffer('ready', 'first.lua')
local second = buffer('ready', 'second.lua')
manager.ensure(first, true); manager.ensure(second, true)
assert(vim.wait(4000, function() return status(ready_dir).state == 'ready' end), vim.inspect(status(ready_dir)))
assert(#notifications == 0, 'managed protocol messages must remain quiet: ' .. vim.inspect(notifications))
assert(table.concat(vim.fn.readfile(status(ready_dir).log), '\n'):find('fixture managed startup failure', 1, true))
local clients = vim.lsp.get_clients({ bufnr = first })
assert(#clients == 1 and #vim.lsp.get_clients({ bufnr = second }) == 1, 'both project buffers attach')
assert(clients[1].id == vim.lsp.get_clients({ bufnr = second })[1].id, 'matching project reuses client')
assert(clients[1].config.handlers['textDocument/publishDiagnostics'] == nil, 'source diagnostics retain their normal handler')
local explicit_buf, explicit_dir = buffer('explicit-messages', 'main.lua')
modes[explicit_dir] = 'explicit'; manager.ensure(explicit_buf, true)
assert(vim.wait(4000, function() return status(explicit_dir).state == 'ready' end))
assert(explicit_messages == 2, 'explicit protocol handlers must retain precedence')
for _, method in ipairs(global_methods) do vim.lsp.handlers[method] = global_handler end
for _, method in ipairs(global_methods) do
  local selected = clients[1]:_resolve_handler(method)
  assert(selected(nil, {message='late override', type=1}, {client_id=clients[1].id}) == vim.NIL)
end
assert(global_messages == 4, 'both global overrides installed after attachment must be honored')
local after_setup, after_dir = buffer('global-after-setup', 'main.lua')
manager.ensure(after_setup, true)
assert(vim.wait(4000, function() return status(after_dir).state == 'ready' end))
assert(global_messages == 6, 'new clients honor both global handlers installed after setup')
local explicit_client = vim.lsp.get_clients({bufnr=explicit_buf})[1]
for _, method in ipairs(global_methods) do
  explicit_client:_resolve_handler(method)(nil, {message='client precedence', type=1}, {client_id=explicit_client.id})
end
assert(explicit_messages == 4 and global_messages == 6, 'per-client handlers win over explicit global handlers')
for _, method in ipairs(global_methods) do vim.lsp.handlers[method] = original_handlers[method] end

local old, stale_dir = buffer('stale-init', 'old.lua')
manager.ensure(old, true)
vim.api.nvim_buf_set_name(old, ready_dir .. '/renamed.lua')
vim.wait(700, function() return false end)
for _, client in ipairs(vim.lsp.get_clients({ bufnr = old })) do
  assert(client.config.root_dir ~= stale_dir, 'in-flight initialization cannot attach the old project to a renamed buffer')
end
local crash, crash_dir = buffer('crash', 'c.lua'); modes[crash_dir] = 'crash'
manager.ensure(crash, true)
assert(vim.wait(4000, function() return status(crash_dir).attempts == 2 and status(crash_dir).state == 'unavailable' end))
assert(status(crash_dir).reason:find('code=23', 1, true), 'true server exit code is inspectable')
local log = table.concat(vim.fn.readfile(status(crash_dir).log), '\n')
assert(log:find('code=23', 1, true))
vim.g.vsvim_lsp_start_timeout = 50
local hang, hang_dir = buffer('hang', 'h.lua'); modes[hang_dir] = 'hang'
manager.ensure(hang, true)
assert(vim.wait(4000, function() return status(hang_dir).attempts == 2 and status(hang_dir).state == 'unavailable' end))
assert(status(hang_dir).reason:find('timed out') or status(hang_dir).reason:find('signal=15'))
assert(#notifications == 0, 'managed failures never notify: ' .. vim.inspect(notifications))
vim.notify('unrelated editor warning')
assert(#notifications == 1, 'unrelated warnings remain available')
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(buf):sub(1, #root) == root then vim.api.nvim_buf_delete(buf, {force=true}) end
end
for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end

vim.g.vsvim_lsp_start_timeout = 1000
local custom = root .. '/custom-root'; vim.fn.mkdir(custom, 'p')
local callback_ran = false
vim.lsp.config('lua_ls', { root_dir = function(_, done)
  vim.defer_fn(function() callback_ran = true; done(custom) end, 10)
end, cmd_cwd = root })
local custom_buffer = buffer('explicit-root', 'root.lua')
manager.ensure(custom_buffer, true)
assert(not callback_ran, 'explicit root callback remains asynchronous')
assert(vim.wait(4000, function() return manager.status()[custom .. ':lua_ls'] and status(custom).state == 'ready' end))
local custom_client = vim.lsp.get_clients({ bufnr = custom_buffer })[1]
assert(custom_client.config.root_dir == custom, 'explicit root function wins marker inference')
assert(vim.fn.readfile(root .. '/cwd-' .. vim.fn.sha256(custom):sub(1, 8))[1] == root, 'explicit server cwd is preserved')
vim.api.nvim_buf_delete(custom_buffer, {force=true})
custom_client:stop(true)

vim.lsp.config._configs.lua_ls = {}
local real_start, real_rpc = vim.lsp.start, vim.lsp.rpc.start
local real_client, real_attach = vim.lsp.get_client_by_id, vim.lsp.buf_attach_client
local started, attached = {}, {}
vim.lsp.rpc.start = function(_, dispatchers) started[#started].dispatchers = dispatchers; return {} end
vim.lsp.start = function(config)
  local record = { id = 9000 + #started, config = config }
  started[#started + 1] = record
  record.client = { id = record.id, config = config, stop = function() record.stopped = true end }
  config.cmd({ on_exit = function(code, signal) config.on_exit(code, signal, record.id) end }, config)
  return record.id
end
vim.lsp.get_client_by_id = function(id)
  for _, record in ipairs(started) do if record.id == id then return record.client end end
  return real_client(id)
end
vim.lsp.buf_attach_client = function(buf, id) attached[#attached + 1] = { buf, id }; return true end
local reported = {}
env.resolve = function(ctx, done)
  reported[#reported + 1] = ctx.report
  done({ runtime = 'controlled', config = { cmd = { '/fixture/server' } } })
end
vim.g.vsvim_lsp_start_timeout = 1100
local attempt_buf, attempt_dir = buffer('attempt-isolation', 'a.lua')
manager.ensure(attempt_buf, true)
local first_attempt = started[1]
first_attempt.dispatchers.on_exit(23, 0)
assert(vim.wait(900, function() return #started == 2 end), 'one recovery starts')
local recovery_attempt = started[2]
vim.wait(650, function() return false end)
assert(status(attempt_dir).state == 'starting', 'old initialization deadline cannot fail the recovery attempt')
first_attempt.config.on_init(first_attempt.client, {})
first_attempt.config.on_error(9, 'late first error')
first_attempt.dispatchers.on_exit(99, 0)
reported[1]('installing')
vim.wait(20, function() return false end)
assert(status(attempt_dir).state == 'starting' and #attached == 0, 'stale init/error/exit/report cannot alter recovery or attach')
recovery_attempt.config.on_init(recovery_attempt.client, {})
assert(status(attempt_dir).state == 'ready' and #attached == 1 and attached[1][2] == recovery_attempt.id)
local late_report
vim.g.vsvim_lsp_resolve_timeout = 30
env.resolve = function(ctx) late_report = ctx.report end
local stalled, stalled_dir = buffer('resolution-timeout', 'a.lua')
manager.ensure(stalled, true)
assert(vim.wait(1000, function() return status(stalled_dir).state == 'unavailable' end))
late_report('installing')
assert(status(stalled_dir).state == 'unavailable', 'timed-out resolution reports cannot revive setup')

vim.g.vsvim_lsp_resolve_timeout = 1000
vim.g.vsvim_lsp_root_timeout = 30
local root_calls = 0
local root_retry_dir = root .. '/root-retry'; vim.fn.mkdir(root_retry_dir, 'p')
env.resolve = function(_, done) done({ runtime = 'root retry', config = { cmd = { '/fixture/server' } } }) end
vim.lsp.config('lua_ls', { root_dir = function(_, done)
  root_calls = root_calls + 1
  if root_calls == 1 then error('transient root failure') end
  done(root_retry_dir)
end })
local throw_buf = buffer('throw-root', 'a.lua')
manager.ensure(throw_buf, true)
manager.ensure(throw_buf, true)
assert(vim.wait(1000, function() return root_calls == 2 and manager.status()[root_retry_dir .. ':lua_ls'] ~= nil end), 'explicit retry reruns a throwing root resolver')
local stale_root_done, second_root_done
root_calls = 0
local timeout_dir = root .. '/root-timeout-retry'; vim.fn.mkdir(timeout_dir, 'p')
vim.lsp.config('lua_ls', { root_dir = function(_, done)
  root_calls = root_calls + 1
  if root_calls == 1 then stale_root_done = done else second_root_done = done end
end })
local root_timeout_buf, inferred_dir = buffer('timeout-root', 'a.lua')
manager.ensure(root_timeout_buf, true)
manager.ensure(root_timeout_buf, true)
assert(root_calls == 1, 'genuinely pending root requests remain shared')
assert(vim.wait(1000, function() return manager.status()[inferred_dir .. ':lua_ls'] and status(inferred_dir).state == 'unavailable' end))
manager.ensure(root_timeout_buf, true)
assert(root_calls == 2, 'explicit retry reruns a timed-out root resolver')
stale_root_done(root .. '/stale-root-must-not-start')
second_root_done(timeout_dir)
assert(vim.wait(1000, function() return manager.status()[timeout_dir .. ':lua_ls'] ~= nil end))
assert(manager.status()[root .. '/stale-root-must-not-start:lua_ls'] == nil, 'old root completions cannot replace the retried request')
vim.lsp.start, vim.lsp.rpc.start = real_start, real_rpc
vim.lsp.get_client_by_id, vim.lsp.buf_attach_client = real_client, real_attach
print('LSP lifecycle passed: deduplication, generations, stale buffers, crash recovery, startup timeout, quiet logs, explicit root/cwd, attempt isolation, root retries')
vim.fn.delete(root, 'rf')
