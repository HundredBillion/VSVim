local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = vim.uv.fs_realpath(root)
local cases = {
  { name='lua', server='lua_ls', main='main.lua', target='helper.lua', line=2, col=8,
    files={ ['main.lua']={'local helper = require("helper")', 'helper.hello()'}, ['helper.lua']={'local function hello() return 42 end', 'return { hello = hello }'}, ['.luarc.json']={'{}'} } },
  { name='python', server='pyright', main='main.py', target='helper.py', line=2, col=1,
    files={ ['main.py']={'from helper import hello', 'hello()'}, ['helper.py']={'def hello():', '    return 42'}, ['pyproject.toml']={} } },
  { name='ruby', server='ruby_lsp', main='main.rb', target='helper.rb', line=2, col=12, target_line=2,
    files={ ['main.rb']={"require_relative 'helper'", 'Greeter.new.hello'}, ['helper.rb']={'class Greeter', '  def hello', '    42', '  end', 'end'}, ['Gemfile']={"source 'https://rubygems.org'"} } },
  { name='go', server='gopls', main='main.go', target='helper.go', line=2, col=14, target_line=2,
    files={ ['main.go']={'package main', 'func main() { hello() }'}, ['helper.go']={'package main', 'func hello() {}'}, ['go.mod']={'module example.com/definition', '', 'go 1.23'} } },
  { name='rust', server='rust_analyzer', main='src/lib.rs', target='src/helper.rs', line=2, col=26,
    files={ ['src/lib.rs']={'mod helper;', 'pub fn run() { helper::hello(); }'}, ['src/helper.rs']={'pub fn hello() {}'}, ['Cargo.toml']={'[package]', 'name = "definition_test"', 'version = "0.1.0"', 'edition = "2021"'} } },
  { name='typescript', server='ts_ls', main='main.ts', target='helper.ts', line=2, col=1,
    files={ ['main.ts']={'import { hello } from "./helper";', 'hello();'}, ['helper.ts']={'export function hello() { return 42; }'}, ['tsconfig.json']={'{"compilerOptions":{"module":"NodeNext","moduleResolution":"NodeNext","target":"ES2022"}}'}, ['package.json']={'{}'} } },
  { name='javascript', server='ts_ls', main='main.js', target='helper.js', line=2, col=1,
    files={ ['main.js']={'const { hello } = require("./helper");', 'hello();'}, ['helper.js']={'exports.hello = function hello() { return 42; };'}, ['jsconfig.json']={'{"compilerOptions":{"module":"NodeNext","moduleResolution":"NodeNext","allowJs":true}}'}, ['package.json']={'{}'} } },
}
local navigate = require('vsvim.lsp').definition
require('vsvim.definition_picker').open = function(items, done)
  for _, item in ipairs(items) do
    if (item.text or ''):find('function', 1, true) then done(item); return end
  end
  done(items[1])
end
for _, case in ipairs(cases) do
  if not vim.env.VSVIM_TEST_LANGUAGE or vim.env.VSVIM_TEST_LANGUAGE == case.name then
  local dir = root .. '/' .. case.name
  for path, lines in pairs(case.files) do
    local file = dir .. '/' .. path
    vim.fn.mkdir(vim.fn.fnamemodify(file, ':h'), 'p')
    vim.fn.writefile(lines, file)
  end
  if case.name == 'ruby' then
    local result = vim.system({ 'bundle', 'install' }, { cwd = dir, text = true }):wait()
    assert(result.code == 0, result.stderr)
  end
  vim.cmd.cd(dir)
  vim.lsp.enable(case.server)
  vim.cmd.edit(dir .. '/' .. case.main)
  local buf = vim.api.nvim_get_current_buf()
  assert(vim.wait(45000, function() return #vim.lsp.get_clients({bufnr=buf,name=case.server}) > 0 end, 100), case.name .. ' failed to attach')
  vim.api.nvim_win_set_cursor(0, {case.line, case.col})
  local destination = dir .. '/' .. case.target
  local reached = false
  for _=1,15 do
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, {case.line, case.col})
    navigate()
    reached = vim.wait(2000, function() return vim.api.nvim_buf_get_name(0) == destination end, 20)
    if reached then break end
  end
  assert(reached, case.name .. ' did not resolve cross-file definition; current=' .. vim.api.nvim_buf_get_name(0) .. ' cursor=' .. vim.inspect(vim.api.nvim_win_get_cursor(0)))
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), {case.target_line or 1,0}), case.name .. ' wrong landing position')
  print(case.name .. ': cross-file definition passed')
  if case.name == 'lua' then
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local hl = vim.api.nvim_get_hl(0, {})' })
    local api_path = vim.env.VIMRUNTIME .. '/lua/vim/_meta/api.gen.lua'
    local resolved = false
    for _ = 1, 20 do
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 23 })
      navigate()
      resolved = vim.wait(2000, function() return vim.api.nvim_buf_get_name(0) == api_path end, 20)
      if resolved then break end
    end
    assert(resolved, 'Neovim API definition was not resolved')
    assert(vim.api.nvim_get_current_line():find('function vim.api.nvim_get_hl(', 1, true))
    assert(vim.api.nvim_win_get_cursor(0)[2] == 0)
    print('lua: Neovim API definition passed')
  end
  for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
  end
end
vim.fn.delete(root, 'rf')
print('Real language-server checks passed')
