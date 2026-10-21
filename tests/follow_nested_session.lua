local vsvim = vim.fn.fnamemodify(debug.getinfo(1,'S').source:sub(2), ':p:h:h')
local plugin = assert(vim.env.VSVIM_FOLLOW_SOURCE)
vim.opt.runtimepath:prepend(vsvim)
vim.opt.runtimepath:prepend(plugin)
vim.g.mapleader = ' '
local parent = vim.fn.tempname()
vim.fn.mkdir(parent,'p')
parent = vim.uv.fs_realpath(parent)
local child = parent .. '/nested-repo'
vim.fn.mkdir(child,'p')
package.loaded.svgtree = {root=function() return parent end}
local path = child .. '/sample.py'
vim.fn.writefile({'one','two','three'},path)
vim.cmd.edit(path)
local tree = vim.api.nvim_create_buf(false,true)
vim.bo[tree].filetype = 'svgtree'
vim.cmd.vsplit()
vim.api.nvim_win_set_buf(0,tree)
local tree_win = vim.api.nvim_get_current_win()
vim.cmd.wincmd('l')
local runtime = '/tmp/follow-vsvim-nested-' .. vim.fn.getpid()
local follow = require('vsvim.follow')
follow.setup()
require('follow.sessions').stop()
local output = ''
local source = vim.system({'node',plugin..'/tests/source.mjs',child,runtime}, {
  stdin=true,stdout=function(_,data) if data then output=output..data end end,
})
assert(vim.wait(3000,function() return output:find('\n',1,true)~=nil end))
local descriptor = vim.json.decode(output:match('[^\n]+'))
require('follow').setup({runtime_dir=runtime})
vim.api.nvim_feedkeys(' af','xt',false)
assert(vim.wait(3000,function() return follow.status().session==descriptor.id end),
  'Space a f attaches nested agent under SVGTree parent: '
  .. vim.inspect({status=follow.status(),list=require('follow.sessions').list(parent),descriptor=descriptor}))
source:write(vim.json.encode({type='location',activity='read',path=path,line=3})..'\n')
assert(vim.wait(3000,function() return vim.api.nvim_win_get_cursor(0)[1]==3 end),
  'Follow opens reported line')
assert(vim.api.nvim_win_get_buf(tree_win)==tree,'SVGTree buffer remains intact')
assert(follow.status().root==parent,'selected SVGTree parent is Follow root')
follow.set_enabled(false)
source:write(nil)
assert(source:wait(3000).code==0)
vim.fn.delete(runtime,'rf')
vim.fn.delete(parent,'rf')
print('VSVim nested Follow session passed')
vim.cmd('qa!')
