local root=vim.fn.tempname()
vim.fn.mkdir(root,'p')
vim.fn.writefile({'return true'},root..'/sample.lua')
local docks={}
local function done(cb) if type(cb)=='function' then vim.schedule(function() cb(nil) end) end end
package.loaded.sprite={
  available=function(cb) vim.schedule(function() cb(nil,{features={'owned-dock-v1','virtual-list-v1','svg-assets-v1','dock-resize-v1'}}) end); return function() end end,
  register_tokens=function(_,cb) done(cb) end,
  on_resume=function() return function() end end,
  open=function(opts,cb)
    local dock={opts=opts,closed=false}
    for _,name in ipairs({'assets','rows','state','update','focus','focus_editor'}) do
      dock[name]=function(_,...) done(select(select('#',...),...)) end
    end
    function dock:close() self.closed=true; opts.on_close({kind='requested'}) end
    docks[#docks+1]=dock
    vim.schedule(function() cb(nil,dock) end)
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
local tree=require('svgtree')
tree.open(root)
local explorer=wait_for('EXPLORER')
keys(explorer,{'space','g','s'})
local scm=wait_for('SOURCE CONTROL')
assert(explorer.closed and tree.root()==nil,'SCM closes native explorer')
keys(scm,{'space','e'})
explorer=wait_for('EXPLORER')
assert(scm.closed,'explorer closes native SCM')
keys(explorer,{'space','g','s'})
scm=wait_for('SOURCE CONTROL')
assert(explorer.closed,'second switch closes explorer')
require('scm').handoff(function() end)
vim.fn.delete(root,'rf')
print('VSVim native handoff passed')
