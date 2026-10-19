local M = {}
local process = require('vsvim.lsp.process')
local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, '\n') or ''
end
local function exists(path) return vim.uv.fs_stat(path) ~= nil end
local function executable(path) return path and path ~= '' and vim.fn.executable(path) == 1 end
local function version(value)
  local a, b, c = (value or ''):match('(%d+)%.(%d+)%.?(%d*)')
  return a and { tonumber(a), tonumber(b), tonumber(c) or 0 } or nil
end
local function at_least(actual, minimum)
  local a, b = version(actual), version(minimum)
  if not a or not b then return false end
  for i = 1, 3 do if a[i] ~= b[i] then return a[i] > b[i] end end
  return true
end
local function selected(root, file, tool)
  local value = vim.trim(read(root .. '/' .. file))
  if value ~= '' then return value end
  return read(root .. '/.tool-versions'):match(tool .. '%s+([^%s]+)')
end
local function managed() return vim.fn.stdpath('data') .. '/lsp-environments' end
local function env_for(bin, extras)
  return vim.tbl_extend('force', { PATH = vim.fs.dirname(bin) .. ':' .. (vim.env.PATH or '') }, extras or {})
end
local function installed_go_policy(policy)
  if policy == 'auto' then return 'path' end
  if policy == 'local' or policy == 'path' then return policy end
  return policy:gsub('%+auto$', ''):gsub('%+path$', '') .. '+path'
end
local function config(plan, ctx)
  plan.config = vim.tbl_deep_extend('force', plan.config or {}, ctx.config._explicit or {})
  if ctx.server == 'gopls' then
    plan.config.cmd_env = plan.config.cmd_env or {}
    plan.config.cmd_env.GOTOOLCHAIN = installed_go_policy(plan.config.cmd_env.GOTOOLCHAIN or vim.env.GOTOOLCHAIN or 'auto')
  end
  return plan
end
function M.fingerprint(root, server)
  local parts = { root, server }
  for _, key in ipairs({ 'PATH', 'RBENV_VERSION', 'PYENV_VERSION', 'VIRTUAL_ENV', 'RUSTUP_TOOLCHAIN', 'GOTOOLCHAIN', 'NVM_BIN' }) do
    table.insert(parts, key .. '=' .. (vim.env[key] or ''))
  end
  for _, file in ipairs({ '.ruby-version', '.python-version', '.node-version', '.nvmrc', '.tool-versions',
    'Gemfile', 'Gemfile.lock', 'pyproject.toml', 'pyrightconfig.json', 'package.json', 'tsconfig.json', 'jsconfig.json',
    'rust-toolchain', 'rust-toolchain.toml', 'Cargo.toml', 'go.mod', 'go.work', '.luarc.json', '.luarc.jsonc' }) do
    local stat = vim.uv.fs_stat(root .. '/' .. file)
    table.insert(parts, file .. ':' .. vim.inspect(stat and { stat.mtime, stat.ctime, stat.size } or false))
  end
  for _, path in ipairs({ root .. '/.venv/bin/python', root .. '/venv/bin/python', root .. '/node_modules/typescript/lib/tsserver.js',
    (vim.env.HOME or '') .. '/.rbenv/versions', (vim.env.HOME or '') .. '/.pyenv/versions', (vim.env.HOME or '') .. '/.nvm/versions/node' }) do
    local stat = vim.uv.fs_stat(path)
    table.insert(parts, path .. ':' .. vim.inspect(stat and {stat.mtime, stat.size} or false))
  end
  for _, tool in ipairs({ 'ruby', 'python3', 'node', 'rustup', 'go', 'gopls', 'lua-language-server' }) do
    local path = vim.fn.exepath(tool)
    local stat = path ~= '' and vim.uv.fs_stat(path) or nil
    table.insert(parts, tool .. ':' .. path .. ':' .. vim.inspect(stat and { stat.mtime, stat.size } or false))
  end
  return vim.fn.sha256(table.concat(parts, '\n'))
end
local function runtime(ctx, tool, wanted, candidates, done)
  local i = 0
  local function next_candidate()
    i = i + 1
    local bin = candidates[i]
    if not bin then done(nil, 'No installed ' .. tool .. ' satisfies ' .. (wanted or 'runtime requirement')); return end
    if not executable(bin) then next_candidate(); return end
    process.run({ bin, '--version' }, { cwd = ctx.root, env = env_for(bin) }, function(output)
      local actual = output and output:match('%d+%.%d+%.?%d*')
      local match = not wanted or actual == wanted or actual and actual:sub(1, #wanted + 1) == wanted .. '.'
      if not actual or not match or (tool == 'Ruby' and not wanted and not at_least(actual, '2.7')) then next_candidate(); return end
      local probe = tool == 'Ruby' and { bin, '-rrbconfig', '-e', 'puts RbConfig.ruby' }
        or { bin, '-c', 'import sys; print(sys.executable)' }
      process.run(probe, { cwd = ctx.root, env = env_for(bin) }, function(output, err)
        local resolved = output and vim.trim(output)
        if executable(resolved) then done(resolved, actual)
        else done(nil, 'Cannot bind selected ' .. tool .. ' executable: ' .. tostring(err or output)) end
      end)
    end)
  end
  next_candidate()
end
local function ruby(ctx, done)
  local wanted = vim.env.RBENV_VERSION or selected(ctx.root, '.ruby-version', 'ruby')
    or read(ctx.root .. '/Gemfile'):match("ruby%s+['\"]([%d%.]+)['\"]")
  if wanted then wanted = wanted:gsub('^ruby%-', '') end
  local home = vim.env.RBENV_ROOT or (vim.env.HOME .. '/.rbenv')
  local bins = {}
  if wanted then table.insert(bins, home .. '/versions/' .. wanted .. '/bin/ruby') end
  table.insert(bins, vim.fn.exepath('ruby'))
  if not wanted then
    for _, candidate in ipairs(vim.fn.glob(home .. '/versions/*/bin/ruby', false, true)) do table.insert(bins, candidate) end
    for _, candidate in ipairs({ '/opt/homebrew/opt/ruby/bin/ruby', '/usr/local/opt/ruby/bin/ruby' }) do table.insert(bins, candidate) end
  end
  runtime(ctx, 'Ruby', wanted, bins, function(bin, actual)
    if not bin then done(nil, actual); return end
    local legacy = not at_least(actual, '3.0')
    if legacy and not at_least(actual, '2.7') then done(nil, 'Ruby ' .. actual .. ' is unsupported'); return end
    local server, release = legacy and 'solargraph' or 'ruby-lsp', legacy and '0.52.0' or '0.26.11'
    local dir = managed() .. '/ruby-' .. actual .. '-' .. server .. '-' .. release
    local gemfile = dir .. '/Gemfile'
    local env = env_for(bin, { BUNDLE_GEMFILE = gemfile, BUNDLE_PATH = dir .. '/bundle', BUNDLE_APP_CONFIG = dir .. '/config',
      RUBYOPT = '', RUBYLIB = '' })
    local prefix = {}
    for key in pairs(vim.fn.environ()) do
      if (key:match('^BUNDLE_') or key:match('^GEM_')) and env[key] == nil then
        if #prefix == 0 then prefix = { '/usr/bin/env' } end
        vim.list_extend(prefix, { '-u', key })
      end
    end
    local function command_for(args) return vim.list_extend(vim.deepcopy(prefix), vim.list_extend({ bin, '-S', 'bundle' }, args)) end
    local command = command_for({ 'exec', server })
    if legacy then table.insert(command, 'stdio') end
    local function ready() done(config({ server = legacy and 'solargraph' or 'ruby_lsp', runtime = 'Ruby ' .. actual .. ' (' .. bin .. ')',
      config = { cmd = command, cmd_env = env } }, ctx)) end
    ctx.report('installing')
    process.once(dir, function(finish)
      vim.fn.mkdir(dir, 'p')
      if not exists(gemfile) then vim.fn.writefile({ "source 'https://rubygems.org'", "gem '" .. server .. "', '= " .. release .. "'" }, gemfile) end
      process.run(command_for({ 'check' }), { cwd = dir, env = env }, function(output)
        if output then finish(true); return end
        process.run(command_for({ 'install', '--jobs', '2', '--retry', '0' }),
          { cwd = dir, env = env, timeout = vim.g.vsvim_lsp_install_timeout or 120000 }, function(installed, err) finish(installed ~= nil, err) end)
      end)
    end, function(ok, err) if ok then ready() else done(nil, 'Ruby tooling installation: ' .. tostring(err)) end end)
  end)
end
local function node(ctx, minimum, done)
  local bins = { vim.fn.exepath('node') }
  for _, bin in ipairs(vim.fn.glob((vim.env.NVM_DIR or (vim.env.HOME .. '/.nvm')) .. '/versions/node/*/bin/node', false, true)) do table.insert(bins, bin) end
  local i = 0
  local function probe()
    i = i + 1
    local bin = bins[i]
    if not bin then done(nil, 'No installed Node >= ' .. minimum .. ' for language-server host'); return end
    if not executable(bin) then probe(); return end
    process.run({ bin, '--version' }, { cwd = ctx.root }, function(output)
      if output and at_least(output, minimum) then done(bin, vim.trim(output)) else probe() end
    end)
  end
  probe()
end
local function npm_tool(ctx, bin, package, release, script, done, skip_existing)
  local existing = vim.fn.stdpath('data') .. '/mason/packages/' .. package .. '/node_modules/'
  local ok, metadata = pcall(vim.json.decode, read(existing .. package .. '/package.json'))
  local required = ok and metadata.engines and metadata.engines.node and metadata.engines.node:match('^>=(%d[%d%.]+)')
  if not skip_existing and required and exists(existing .. script) then
    process.run({ bin, '--version' }, { cwd = ctx.root }, function(output)
      if output and at_least(output, required) then done(existing .. script, env_for(bin))
      else npm_tool(ctx, bin, package, release, script, done, true) end
    end)
    return
  end
  local dir = managed() .. '/node-' .. vim.fn.sha256(bin):sub(1, 12) .. '-' .. package .. '-' .. release
  local target = dir .. '/node_modules/' .. script
  local env = env_for(bin)
  if exists(target) then done(target, env); return end
  ctx.report('installing')
  process.once(dir, function(finish)
    vim.fn.mkdir(dir, 'p')
    local npm = vim.fs.dirname(bin) .. '/npm'
    process.run({ npm, 'install', '--prefix', dir, '--no-audit', '--no-fund', '--ignore-scripts', '--package-lock=false',
      package .. '@' .. release, unpack(package == 'typescript-language-server' and { 'typescript@5.9.3' } or {}) },
      { cwd = dir, env = env, timeout = vim.g.vsvim_lsp_install_timeout or 120000 }, function(output, err)
        finish(output ~= nil and exists(target), err)
      end)
  end, function(ok, err) if ok then done(target, env) else done(nil, 'npm tooling installation: ' .. tostring(err)) end end)
end
local function typescript(ctx, done)
  local function resolved(bin, actual)
    if not bin then done(nil, actual); return end
    npm_tool(ctx, bin, 'typescript-language-server', '4.3.4', 'typescript-language-server/lib/cli.mjs', function(script, env)
      if not script then done(nil, env); return end
      local options = {}
      local sdk = ctx.root .. '/node_modules/typescript/lib/tsserver.js'
      if exists(sdk) then options.tsserver = { path = sdk } end
      done(config({ runtime = 'Node ' .. actual .. ' (' .. bin .. ')', config = { cmd = { bin, script, '--stdio' }, cmd_env = env, init_options = options } }, ctx))
    end)
  end
  node(ctx, '22.22.2', function(bin, actual)
    if bin then resolved(bin, actual) else node(ctx, '18.0', resolved) end
  end)
end
local function python(ctx, done)
  local explicit = vim.tbl_get(ctx.config, 'settings', 'python', 'pythonPath')
  local wanted = not explicit and (vim.env.PYENV_VERSION or selected(ctx.root, '.python-version', 'python')) or nil
  local bins = {}
  local ok, project = pcall(vim.json.decode, read(ctx.root .. '/pyrightconfig.json'))
  if not ok then
    project = {}
    local section = (read(ctx.root .. '/pyproject.toml') .. '\n['):match('%[tool%.pyright%](.-)\n%[') or ''
    project.venv = section:match([=[venv%s*=%s*['"]([^'"]+)['"]]=])
    project.venvPath = section:match([=[venvPath%s*=%s*['"]([^'"]+)['"]]=])
  end
  if project.venv then
    local path = project.venvPath or ctx.root
    if path:sub(1, 1) ~= '/' then path = ctx.root .. '/' .. path end
    table.insert(bins, path .. '/' .. project.venv .. '/bin/python')
  end
  if explicit then table.insert(bins, explicit) end
  for _, dir in ipairs({ '.venv', 'venv' }) do table.insert(bins, ctx.root .. '/' .. dir .. '/bin/python') end
  if wanted then table.insert(bins, (vim.env.PYENV_ROOT or (vim.env.HOME .. '/.pyenv')) .. '/versions/' .. wanted .. '/bin/python') end
  if vim.env.VIRTUAL_ENV then table.insert(bins, vim.env.VIRTUAL_ENV .. '/bin/python') end
  table.insert(bins, vim.fn.exepath('python3'))
  if explicit then bins = { explicit } end
  runtime(ctx, 'Python', wanted, bins, function(interpreter, actual)
    if not interpreter then done(nil, actual); return end
    node(ctx, '14.0', function(bin, host)
      if not bin then done(nil, host); return end
      npm_tool(ctx, bin, 'pyright', '1.1.414', 'pyright/langserver.index.js', function(script, env)
        if not script then done(nil, env); return end
        done(config({ runtime = 'Python ' .. actual .. ' (' .. interpreter .. '); Node ' .. host,
          config = { cmd = { bin, script, '--stdio' }, cmd_env = env, settings = { python = { pythonPath = interpreter } } } }, ctx))
      end)
    end)
  end)
end
local function rust(ctx, done)
  local toolchain = vim.tbl_get(ctx.config, 'cmd_env', 'RUSTUP_TOOLCHAIN') or vim.env.RUSTUP_TOOLCHAIN or read(ctx.root .. '/rust-toolchain.toml'):match('channel%s*=%s*"([^"]+)"')
    or vim.trim(read(ctx.root .. '/rust-toolchain'))
  local env = toolchain ~= '' and { RUSTUP_TOOLCHAIN = toolchain } or {}
  local rustup = vim.fn.exepath('rustup')
  if rustup == '' then done(nil, 'rustup is required to resolve the selected Rust toolchain'); return end
  process.run({ rustup, 'which', 'rustc' }, { cwd = ctx.root, env = env }, function(compiler, err)
    if not compiler then done(nil, err); return end
    process.run({ vim.trim(compiler), '--print', 'sysroot' }, { cwd = ctx.root, env = env }, function(output, sys_err)
      if not output then done(nil, sys_err); return end
      local src = vim.trim(output) .. '/lib/rustlib/src/rust/library'
      local function analyzer()
        process.run({ rustup, 'which', 'rust-analyzer' }, { cwd = ctx.root, env = env }, function(bin, analyzer_err)
          if not bin then done(nil, analyzer_err); return end
          done(config({ runtime = 'Rust ' .. (toolchain ~= '' and toolchain or 'selected default'), config = {
            cmd = { vim.trim(bin) }, cmd_env = env, settings = { ['rust-analyzer'] = { cargo = { sysrootSrc = src } } } } }, ctx))
        end)
      end
      local function install()
        ctx.report('installing')
        process.once('rust-components:' .. vim.trim(output), function(finish)
          process.run({ rustup, 'component', 'add', 'rust-src', 'rust-analyzer' },
            { cwd = ctx.root, env = env, timeout = vim.g.vsvim_lsp_install_timeout or 120000 }, function(result, component_err) finish(result ~= nil, component_err) end)
        end, function(ok, component_err) if ok then analyzer() else done(nil, component_err) end end)
      end
      if exists(src) then
        process.run({ rustup, 'which', 'rust-analyzer' }, { cwd = ctx.root, env = env }, function(bin)
          if bin and executable(vim.trim(bin)) then analyzer() else install() end
        end)
      else install() end
    end)
  end)
end
local function go(ctx, done)
  local bin = vim.fn.exepath('go')
  if bin == '' then done(nil, 'Go runtime is unavailable'); return end
  local selected_env = vim.tbl_extend('force', {}, ctx.config.cmd_env or {})
  local policy = selected_env.GOTOOLCHAIN or vim.env.GOTOOLCHAIN or 'auto'
  selected_env.GOTOOLCHAIN = installed_go_policy(policy)
  process.run({ bin, 'env', '-json', 'GOVERSION', 'GOWORK', 'GOMOD', 'GOROOT', 'GOTOOLCHAIN' },
    { cwd = ctx.root, env = selected_env }, function(output, err)
    if not output then done(nil, 'Selected Go toolchain unavailable: ' .. tostring(err)); return end
    local ok, values = pcall(vim.json.decode, output)
    if not ok or not values.GOVERSION then done(nil, 'Invalid Go environment'); return end
    local parsed = version(values.GOVERSION)
    local releases = { [23] = 'v0.17.1', [24] = 'v0.18.1', [25] = 'v0.21.0', [26] = 'v0.23.0', [27] = 'v0.23.0' }
    local release = parsed and parsed[1] == 1 and releases[parsed[2]]
    if not release then done(nil, 'No verified managed gopls for ' .. values.GOVERSION); return end
    local env = env_for(bin, vim.tbl_extend('force', selected_env, {
      GOTOOLCHAIN = values.GOVERSION .. '+path', GOWORK = values.GOWORK ~= '' and values.GOWORK or 'off',
      GOFLAGS = selected_env.GOFLAGS or ((vim.env.GOFLAGS or '') .. ' -mod=readonly'),
    }))
    local dir = managed() .. '/gopls-' .. release .. '-' .. values.GOVERSION
    local function ready(command) done(config({ runtime = values.GOVERSION .. ' (' .. values.GOROOT .. ')',
      config = { cmd = { command }, cmd_env = env } }, ctx)) end
    local function install()
      ctx.report('installing')
      process.once(dir, function(finish)
        vim.fn.mkdir(dir, 'p')
        process.run({ bin, 'install', 'golang.org/x/tools/gopls@' .. release },
          { cwd = dir, env = vim.tbl_extend('force', env, { GOBIN = dir, GOWORK = 'off' }), timeout = vim.g.vsvim_lsp_install_timeout or 120000 },
          function(result, install_err) finish(result ~= nil, install_err) end)
      end, function(installed, install_err) if installed then ready(dir .. '/gopls') else done(nil, install_err) end end)
    end
    local candidates = { vim.fn.exepath('gopls'), vim.fn.stdpath('data') .. '/mason/bin/gopls', dir .. '/gopls' }
    local index = 0
    local function check()
      index = index + 1
      local candidate = candidates[index]
      if not candidate then install(); return end
      if not executable(candidate) then check(); return end
      process.run({ candidate, 'version' }, { cwd = ctx.root, env = env }, function(info)
        local actual = info and info:match('gopls%s+(v%d+%.%d+%.%d+)')
        if actual == release then ready(candidate) else check() end
      end)
    end
    check()
  end)
end
local function lua(ctx, done)
  local settings = {}
  local nvim = ctx.root == vim.fn.stdpath('config') or exists(ctx.root .. '/init.lua') and exists(ctx.root .. '/lua')
  if nvim and not exists(ctx.root .. '/.luarc.json') and not exists(ctx.root .. '/.luarc.jsonc') then
    settings = { Lua = { runtime = { version = 'LuaJIT', path = { '?.lua', '?/init.lua', 'lua/?.lua', 'lua/?/init.lua' } },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME .. '/lua' } } } }
  end
  local function ready(bin) done(config({ runtime = nvim and 'LuaJIT (Neovim)' or 'Lua (project defaults)', config = { cmd = { bin }, settings = settings } }, ctx)) end
  local bin = vim.fn.exepath('lua-language-server')
  if bin ~= '' then ready(bin); return end
  local installed = vim.fn.stdpath('data') .. '/mason/bin/lua-language-server'
  if executable(installed) then ready(installed); return end
  ctx.report('installing')
  process.once('mason:lua-language-server', function(finish)
    local ok, registry = pcall(require, 'mason-registry')
    if not ok then finish(false, 'Mason registry unavailable'); return end
    local completed, handle = false, nil
    local function complete(success, err) if not completed then completed = true; finish(success, err) end end
    vim.defer_fn(function()
      if not completed and handle and not handle:is_closed() then handle:terminate() end
      complete(false, 'Lua server installer timed out')
    end, vim.g.vsvim_lsp_install_timeout or 120000)
    registry.refresh(vim.schedule_wrap(function(success)
      if completed then return end
      if not success then complete(false, 'Mason registry unavailable'); return end
      local found, pkg = pcall(registry.get_package, 'lua-language-server')
      if not found then complete(false, tostring(pkg)); return end
      if pkg:is_installed() then complete(true); return end
      if pkg:is_installing() then
        local function poll()
          if completed then return end
          if pkg:is_installed() and not pkg:is_installing() then complete(true)
          elseif not pkg:is_installing() then complete(false, 'Lua server installation failed')
          else vim.defer_fn(poll, 100) end
        end
        poll()
      else
        handle = pkg:install({}, vim.schedule_wrap(function(successful) complete(successful, 'Lua server installation failed') end))
      end
    end))
  end, function(ok, err) if ok then ready(installed) else done(nil, err) end end)
end
function M.resolve(ctx, done)
  ctx.config = ctx.config or {}
  ctx.config._explicit = ctx.config._explicit or vim.deepcopy(ctx.config)
  ctx.report = ctx.report or function() end
  if not exists(ctx.root) then done(nil, 'Project directory no longer exists'); return end
  if ctx.config._explicit and ctx.config._explicit.cmd then
    done(config({ runtime = 'Explicit command', config = vim.deepcopy(ctx.config._explicit) }, ctx)); return
  end
  local resolve = ({ ruby_lsp = ruby, pyright = python, ts_ls = typescript, rust_analyzer = rust, gopls = go, lua_ls = lua })[ctx.server]
  if not resolve then done(nil, 'Unsupported server ' .. ctx.server); return end
  resolve(ctx, done)
end
return M
