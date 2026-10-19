vim.opt.rtp:prepend(vim.fn.getcwd())
vim.api.nvim_buf_set_lines(0,0,-1,false,vim.fn.map(vim.fn.range(1,1000),function(_,i) return 'row '..i end))
local source=require('vsvim.minimap.source')
source.watch=function() return function() end end
source.commit=function() end
source.rows=function(buffer,first,last,done)
 vim.schedule(function() local rows={};for i=first,last do rows[#rows+1]={text='row '..i,spans={}} end;done(rows,{'#ffffff'},nil,{first=first,last=last,total=1000}) end)
 return function() end
end
local p=require('vsvim.minimap').provider()
local function pull(kind)
 local found;assert(vim.wait(5000,function() local op=p.next();if op and op.kind==kind then found=op;return true end end,1));return found
end
pull('commit');pull('state')
vim.wo.foldmethod='manual';vim.cmd('10,200fold');vim.cmd('normal! gg')
local target=p.target()
local previous
for id=1,128 do
 p.dispatch({target=target.target,generation=target.generation,action='scroll',topline=10+id,action_id=id})
 local state=pull('state');assert(state.action_id==id,'each processed action forces a state with its id')
 if id<128 then assert(state.viewport[1]==10,'closed fold returns same actual top') end
 previous=state.viewport[1]
end
assert(previous==10)
p.dispatch({target=target.target,generation=target.generation,action='scroll',topline=250,action_id=129})
assert(pull('state').action_id==129)
p.stop()
print('minimap actual folded unchanged-top actions emit 128 distinct acknowledgments: PASS')
