local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
vim.fn.writefile({ '2.7.5' }, root .. '/.ruby-version')
local function resolve(server, config)
  local finished, plan, reason = false
  require('vsvim.lsp.environment').resolve({ root = root, server = server, bufnr = 0, config = config or {}, report = function() end }, function(p, e)
    plan, reason, finished = p, e, true
  end)
  assert(vim.wait(3000, function() return finished end), 'resolution completes')
  return plan, reason
end
local plan = resolve('ruby_lsp', { _explicit = { cmd = { '/bin/cat' } }, cmd = { '/bin/cat' } })
assert(plan.config.cmd[1] == '/bin/cat', 'explicit command wins')

local home = root .. '/home'
local bin = root .. '/bin'
vim.fn.mkdir(bin, 'p')
vim.fn.mkdir(home, 'p')
vim.env.HOME = home
vim.env.RBENV_ROOT = home .. '/.rbenv'
vim.env.PYENV_ROOT = home .. '/.pyenv'
vim.env.NVM_DIR = home .. '/.nvm'
vim.env.PATH = bin .. ':/usr/bin:/bin'
vim.env.XDG_DATA_HOME = root .. '/data'
vim.env.RBENV_VERSION = nil
vim.env.PYENV_VERSION = nil
vim.env.RUSTUP_TOOLCHAIN = nil
vim.env.VIRTUAL_ENV = nil
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  vim.fn.writefile(lines, path)
end
local function exe(path, body)
  if path:find('/python', 1, true) then body = 'if [ "$1" = -c ]; then echo "$0"; exit 0; fi\n' .. body end
  write(path, vim.list_extend({ '#!/bin/sh' }, vim.split(body, '\n', { plain = true })))
  vim.fn.setfperm(path, 'rwxr-xr-x')
end
local ruby = home .. '/.rbenv/versions/2.7.5/bin/ruby'
exe(ruby, [[
if [ "$1" = --version ]; then echo 'ruby 2.7.5'; exit 0; fi
if [ "$1" = -rrbconfig ]; then echo "$0"; exit 0; fi
if [ "$3" = check ]; then test -f "$BUNDLE_PATH/ready"; exit $?; fi
if [ "$3" = install ]; then mkdir -p "$BUNDLE_PATH"; touch "$BUNDLE_PATH/ready"; exit 0; fi
exit 19
]])
local old_path = vim.env.PATH
local ruby_plan, ruby_error = resolve('ruby_lsp')
assert(ruby_plan, ruby_error)
assert(ruby_plan.server == 'solargraph', 'legacy Ruby uses verified compatible server')
assert(ruby_plan.config.cmd[1] == ruby)
assert(ruby_plan.config.cmd[5] == 'solargraph' and ruby_plan.config.cmd[6] == 'stdio')
assert(ruby_plan.config.cmd_env.BUNDLE_GEMFILE:find('/lsp%-environments/'))
assert(vim.env.PATH == old_path, 'runtime resolution never mutates editor PATH')
assert(not vim.uv.fs_stat(root .. '/Gemfile.lock'), 'application lockfile is untouched')
local identity = require('vsvim.lsp.environment').fingerprint(root, 'ruby_lsp')
write(root .. '/.ruby-version', { '9.9.9' })
assert(identity ~= require('vsvim.lsp.environment').fingerprint(root, 'ruby_lsp'))
local missing, reason = resolve('ruby_lsp')
assert(not missing and reason:find('9.9.9', 1, true), 'missing selected Ruby is a quiet preflight failure')
write(root .. '/.ruby-version', { '2.7.5' })
local node = bin .. '/node'
exe(node, 'echo v22.22.2')
local npm = bin .. '/npm'
exe(npm, [[
while [ "$1" != --prefix ] && [ $# -gt 0 ]; do shift; done
shift
prefix=$1
mkdir -p "$prefix/node_modules/typescript-language-server/lib" "$prefix/node_modules/pyright"
touch "$prefix/node_modules/typescript-language-server/lib/cli.mjs" "$prefix/node_modules/pyright/langserver.index.js"
]])
local ts = resolve('ts_ls')
assert(ts.config.cmd[1] == node and ts.config.cmd[3] == '--stdio')
write(root .. '/node_modules/typescript/lib/tsserver.js', { '' })
local sdk = resolve('ts_ls', { _explicit = { init_options = { hostInfo = 'custom' } } })
assert(sdk.config.init_options.tsserver.path == root .. '/node_modules/typescript/lib/tsserver.js')
assert(sdk.config.init_options.hostInfo == 'custom')
local interpreter = root .. '/.venv/bin/python'
exe(interpreter, "echo 'Python 3.11.9'")
local py = resolve('pyright')
assert(py.config.settings.python.pythonPath == interpreter, 'project venv is the analysis interpreter')
assert(py.config.cmd[1] == node, 'Python analysis and server host are independent')
local explicit_python = bin .. '/python-custom'
exe(explicit_python, "echo 'Python 3.12.3'")
write(root .. '/.python-version', { '3.11.9' })
local explicit = resolve('pyright', { settings = { python = { pythonPath = explicit_python } },
  _explicit = { settings = { python = { pythonPath = explicit_python } } } })
assert(explicit.config.settings.python.pythonPath == explicit_python, 'explicit interpreter wins version inference')
exe(bin .. '/go', [[
printf '{"GOVERSION":"go1.24.0","GOWORK":"%s/go.work","GOMOD":"%s/go.mod","GOROOT":"/fixture/go"}\n' "$PWD" "$PWD"
]])
exe(bin .. '/gopls', "echo 'golang.org/x/tools/gopls v0.18.1'")
write(root .. '/go.work', { 'go 1.24.0' })
local go = resolve('gopls')
assert(go.config.cmd_env.GOTOOLCHAIN == 'go1.24.0+path', 'Go must never download missing application toolchains')
assert(go.config.cmd_env.GOWORK == root .. '/go.work')
for policy, expected in pairs({ auto = 'path', ['go1.24.0+auto'] = 'go1.24.0+path' }) do
  local final = resolve('gopls', { cmd_env = { GOTOOLCHAIN = policy, KEEP_EXPLICIT = 'yes' } })
  assert(final.config.cmd_env.GOTOOLCHAIN == expected, 'final Go launch policy forbids runtime downloads: ' .. policy)
  assert(final.config.cmd_env.KEEP_EXPLICIT == 'yes')
  local custom = resolve('gopls', { cmd = { '/fixture/custom-gopls' }, cmd_env = { GOTOOLCHAIN = policy } })
  assert(custom.config.cmd_env.GOTOOLCHAIN == expected, 'explicit Go commands retain the installed-only policy')
end
local custom_go = resolve('gopls', { cmd = { '/fixture/custom-gopls' } })
assert(custom_go.config.cmd_env.GOTOOLCHAIN == 'path', 'explicit Go commands cannot inherit automatic runtime acquisition')
exe(bin .. '/lua-language-server', 'exit 0')
local lua = resolve('lua_ls')
assert(not lua.config.settings.Lua, 'ordinary Lua projects do not inherit Neovim globals')
write(root .. '/init.lua', { '' }); vim.fn.mkdir(root .. '/lua', 'p')
local nvim = resolve('lua_ls')
assert(nvim.config.settings.Lua.runtime.version == 'LuaJIT')
write(root .. '/.luarc.json', { '{}' })
assert(not resolve('lua_ls').config.settings.Lua, 'project LuaLS config owns its defaults')
local rustc = bin .. '/rustc'
local analyzer = bin .. '/rust-analyzer'
exe(rustc, 'echo "' .. root .. '/sysroot"')
exe(analyzer, 'exit 0')
exe(bin .. '/rustup', [[
if [ "$1" = which ]; then printf '%s/%s\n' "]] .. bin .. [[" "$2"; exit 0; fi
if [ "$1" = component ]; then exit 42; fi
exit 1
]])
write(root .. '/rust-toolchain.toml', { '[toolchain]', 'channel = "1.88.0"' })
vim.fn.mkdir(root .. '/sysroot/lib/rustlib/src/rust/library', 'p')
local rust, rust_error = resolve('rust_analyzer')
assert(rust, rust_error)
assert(vim.tbl_contains(rust.config.settings['rust-analyzer'].cargo.extraArgs or {}, '--locked'), 'Cargo must preserve project lockfiles')
assert(rust.config.cmd_env.RUSTUP_TOOLCHAIN == '1.88.0')
assert(rust.config.settings['rust-analyzer'].cargo.sysrootSrc == root .. '/sysroot/lib/rustlib/src/rust/library')
assert(rust.config.settings['rust-analyzer'].cargo.noDeps == true)
local before_lock = require('vsvim.lsp.environment').fingerprint(root, 'rust_analyzer')
write(root .. '/Cargo.lock', {'version = 4'})
assert(before_lock ~= require('vsvim.lsp.environment').fingerprint(root, 'rust_analyzer'), 'lock presence changes Rust environment')
local configured = assert(resolve('rust_analyzer', {settings={['rust-analyzer']={cargo={extraArgs={'--features', 'editor'}}, check={extraArgs={'--all-targets'}}}}}))
assert(configured.config.settings['rust-analyzer'].cargo.noDeps == false, 'existing lock retains dependency discovery')
for _, scope in ipairs({'cargo', 'check'}) do
  local args = configured.config.settings['rust-analyzer'][scope].extraArgs
  assert(vim.tbl_contains(args, '--locked') and vim.tbl_contains(args, '--offline'), 'explicit args retain project safeguards')
end
assert(vim.tbl_contains(configured.config.settings['rust-analyzer'].cargo.extraArgs, '--features'))
local nested = root .. '/workspace-member'; vim.fn.mkdir(nested, 'p')
local member_before = require('vsvim.lsp.environment').fingerprint(nested, 'rust_analyzer')
write(root .. '/Cargo.lock', {'version = 4', '# changed workspace lock'})
assert(member_before ~= require('vsvim.lsp.environment').fingerprint(nested, 'rust_analyzer'), 'ancestor workspace lock invalidates member environment')



vim.fn.delete(root .. '/.python-version')
local custom_venv = root .. '/envs/analysis/bin/python'
exe(custom_venv, "echo 'Python 3.10.9'")
write(root .. '/pyrightconfig.json', { '{"venvPath":"envs","venv":"analysis","pythonVersion":"3.8"}' })
assert(resolve('pyright').config.settings.python.pythonPath == custom_venv, 'explicit project virtualenv wins conventional .venv')
for _, value in ipairs({ '13.99.9', '14.0.0', '17.99.9', '18.0.0', '22.22.1', '22.22.2', '100.0.0', 'malformed' }) do
  exe(node, 'echo v' .. value)
  local result = resolve('ts_ls')
  assert((result ~= nil) == (vim.version.parse(value) ~= nil and vim.version.ge(value, '18.0.0')), 'Node host version boundary: ' .. value)
end
exe(node, 'echo v22.22.2')
local installation_log = root .. '/install-count'
vim.env.VSVIM_FIXTURE_LOG = installation_log
local npm_body = table.concat(vim.fn.readfile(npm), '\n')
exe(npm, 'echo install >> "$VSVIM_FIXTURE_LOG"\n/bin/sleep 0.05\n' .. npm_body:gsub('^#!/bin/sh\n', ''))
local managed = vim.fn.stdpath('data') .. '/lsp-environments'
for _, path in ipairs(vim.fn.glob(managed .. '/node-*-typescript-language-server-*', false, true)) do vim.fn.delete(path, 'rf') end
local count = 0
for _ = 1, 2 do
  require('vsvim.lsp.environment').resolve({ root = root, server = 'ts_ls', config = {} }, function(result, err)
    assert(result, err); count = count + 1
  end)
end
assert(vim.wait(3000, function() return count == 2 end))
assert(#vim.fn.readfile(installation_log) == 1, 'concurrent projects share a single tooling install')
exe(npm, 'exit 73')
assert(resolve('ts_ls'), 'offline cache remains usable without invoking npm')
for _, path in ipairs(vim.fn.glob(managed .. '/node-*-typescript-language-server-*', false, true)) do vim.fn.delete(path, 'rf') end
local failed, failure = resolve('ts_ls')
assert(not failed and failure:find('exit=73', 1, true), 'installer error code is retained')
exe(npm, 'exec /bin/sleep 5')
vim.g.vsvim_lsp_install_timeout = 30
local timed, timeout = resolve('ts_ls')
assert(not timed and timeout:find('exit=124', 1, true), 'installer process times out')
print('LSP environment passed: six ecosystems, explicit precedence, isolation, fingerprints, cached reuse, installer failure/timeout, Node boundaries')
vim.fn.delete(root, 'rf')
