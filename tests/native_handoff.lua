local root=vim.fn.tempname()
vim.fn.mkdir(root,'p')
vim.fn.writefile({'return true'},root..'/sample.lua')
local docks={}
local focused
local held
local function done(cb) if type(cb)=='function' then vim.schedule(function() cb(nil) end) end end
package.loaded.sprite={
  available=function(cb) vim.schedule(function() cb(nil,{features={'owned-dock-v1','virtual-list-v1','svg-assets-v1','dock-resize-v1'}}) end); return function() end end,
  register_tokens=function(_,cb) done(cb) end,
  on_resume=function() return function() end end,
  open=function(opts,cb)
    local dock={opts=opts,closed=false}
    assert(opts.description.root.colors.background=='#2b2d30', 'native sidebar uses JB background')
    for _,name in ipairs({'assets','rows','state','update','focus','focus_editor'}) do
      dock[name]=function(_,...)
        if name=='focus' then focused=dock end
        if name=='focus_editor' then focused='editor' end
        done(select(select('#',...),...))
      end
    end
    function dock:close() self.closed=true; opts.on_close({kind='requested'}) end
    docks[#docks+1]=dock
    if held then held[#held+1]=function() cb(nil,dock) end
    else vim.schedule(function() cb(nil,dock) end) end
    return function() end
  end,
}
local function wait_for(label)
  assert(vim.wait(3000,function()
    local dock=docks[#docks]
    return dock and not dock.closed and dock.opts.description.root.heading.text==label
  end),label..' dock opens: '..vim.inspect(vim.tbl_map(function(d) return {d.opts.description.root.heading.text,d.closed} end,docks)))
  vim.wait(150,function() return false end)
  return docks[#docks]
end
local function keys(dock,sequence)
  for _,key in ipairs(sequence) do dock.opts.on_event({type='input',key=key,text=key=='space' and ' ' or key}) end
end
local function roundtrip(dock)
  dock.opts.on_event({type='input',key='ctrl-l'})
  assert(vim.wait(1000,function() return focused=='editor' end), 'Ctrl-l reaches editor')
  local map=vim.fn.maparg('<C-h>','n',false,true)
  assert(type(map.callback)=='function', 'Ctrl-h has a focus mapping')
  map.callback()
  assert(vim.wait(1000,function() return focused==dock end), 'Ctrl-h returns to native sidebar')
  dock.opts.on_event({type='input',key='ctrl-l'})
  assert(vim.wait(1000,function() return focused=='editor' end), 'second Ctrl-l reaches editor')
end
local tree=require('svgtree')
tree.open(root)
local explorer=wait_for('EXPLORER')
roundtrip(explorer)
local left=vim.api.nvim_get_current_win()
vim.cmd('rightbelow vsplit')
local right=vim.api.nvim_get_current_win()
local focus_before=focused
vim.fn.maparg('<C-h>','n',false,true).callback()
assert(vim.api.nvim_get_current_win()==left and focused==focus_before, 'Ctrl-h visits editor split before native sidebar')
vim.fn.maparg('<C-l>','n',false,true).callback()
assert(vim.api.nvim_get_current_win()==right and focused==focus_before, 'Ctrl-l visits right editor split')
vim.api.nvim_win_close(right,true)
keys(explorer,{'space','g','s'})
local scm=wait_for('SOURCE CONTROL')
roundtrip(scm)
assert(explorer.closed and tree.root()==nil,'SCM closes native explorer')
keys(scm,{'space','e'})
explorer=wait_for('EXPLORER')
assert(scm.closed,'explorer closes native SCM')
keys(explorer,{'space','g','s'})
scm=wait_for('SOURCE CONTROL')
assert(explorer.closed,'second switch closes explorer')
local function mapped(key) vim.fn.maparg(key,'n',false,true).callback() end
keys(scm,{'space','e'})
mapped('<leader>gs')
scm=wait_for('SOURCE CONTROL')
assert(tree.root()==nil, 'latest SCM request cancels deferred Explorer handoff')
for _,dock in ipairs(docks) do
  assert(dock==scm or dock.closed, 'only latest requested sidebar survives')
end
assert(not require('vsvim.sidebar').focus('right'), 'left native sidebar rejects right focus')
local editor=vim.api.nvim_get_current_win()
vim.cmd.cd(vim.env.VSVIM_ROOT)
mapped('<leader>e')
explorer=wait_for('EXPLORER')
assert(tree.root()==vim.uv.fs_realpath(root), 'native handoff preserves root after cwd changes')
roundtrip(explorer)
assert(vim.api.nvim_get_current_win()==editor, 'native roundtrip preserves editor target')
keys(explorer,{'space','e'})
assert(vim.wait(1000,function() return explorer.closed end), 'native Explorer action closes Explorer')
mapped('<leader>e')
explorer=wait_for('EXPLORER')
assert(tree.root()==vim.uv.fs_realpath(root), 'Explorer reopens at remembered root')
mapped('<leader>gs')
scm=wait_for('SOURCE CONTROL')
mapped('<leader>gs')
assert(scm.closed, 'SCM toggles closed')
held={}
mapped('<leader>e')
assert(vim.wait(1000,function() return #held==1 end), 'Explorer open callback is pending')
mapped('<leader>gs')
assert(vim.wait(1000,function() return #held==2 end), 'SCM open callback is pending')
mapped('<leader>e')
assert(vim.wait(1000,function() return #held==3 end), 'replacement Explorer callback is pending')
local callbacks=held
held=nil
for i=#callbacks,1,-1 do callbacks[i]() end
explorer=wait_for('EXPLORER')
for _,dock in ipairs(docks) do
  assert(dock==explorer or dock.closed, 'late open callbacks cannot revive replaced sidebars')
end
assert(tree.root()==vim.uv.fs_realpath(root), 'rapid requests preserve root')
roundtrip(explorer)
require('vsvim.sidebar').explorer()
assert(vim.wait(1000,function() return tree.root()==nil end), 'coordinator closes Explorer')

vim.fn.delete(root,'rf')
print('VSVim native handoff passed')
