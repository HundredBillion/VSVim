vim.opt.runtimepath:prepend(vim.fn.getcwd())
local source = require('vsvim.minimap.source')
local b = vim.api.nvim_get_current_buf()
vim.bo.tabstop = 4
vim.cmd('syntax on')
vim.bo.filetype = 'lua'
vim.cmd('syntax enable')
vim.api.nvim_set_hl(0, 'String', {fg='#12ab34'})
vim.api.nvim_buf_set_lines(b, 0, -1, false, {'local x = "hello"', '\t"hé界"', '', string.rep('é', 10000), '-- comment'})
local rows, palette
source.rows(b, 1, 5, function(r,p) rows,palette=r,p end)
assert(vim.wait(3000, function() return rows ~= nil end))
assert(#rows == 5 and rows[3].text == '')
assert(rows[2].text == '    "hé界"', rows[2].text)
assert(vim.fn.strdisplaywidth(rows[4].text) <= 256 and #rows[4].text <= 2048)
assert(palette[1]:match('^#%x%x%x%x%x%x$'))
local found=false
for _, s in ipairs(rows[1].spans) do if palette[s[3]+1]=='#12ab34' then found=true end end
assert(found, vim.inspect({rows,palette}))
local stale=false
local cancel=source.rows(b,1,5,function() stale=true end)
cancel()
vim.wait(20)
assert(not stale)
print('minimap source: PASS')
local minimap=require('vsvim.minimap')
local provider=minimap.provider()
local ops={}
assert(provider.next()==nil)
assert(vim.wait(4000,function()
  local op=provider.next()
  if op then ops[#ops+1]=op; return op.kind=='commit' end
end))
assert(ops[1].kind=='begin' and ops[1].base==vim.NIL)
local generation=ops[1].generation
vim.api.nvim_buf_set_lines(b,0,1,false,{'local x = "changed"'})
ops={}
assert(vim.wait(4000,function()
  local op=provider.next()
  if op then ops[#ops+1]=op; return op.kind=='commit' end
end))
assert(ops[1].kind=='begin' and ops[1].base==generation, vim.inspect(ops))
assert(ops[1].start==1 and ops[1].delete==1 and ops[1].insert==1, vim.inspect(ops[1]))
local got_source=false
vim.api.nvim_win_set_cursor(0,{2,0})
vim.api.nvim_exec_autocmds('CursorMoved',{})
for _=1,5 do local op=provider.next(); if op and op.kind=='begin' then got_source=true end end
assert(not got_source)
provider.stop()
print('minimap provider: PASS')
-- Edits made before a transaction commits still use the committed document as base.
provider.next()
assert(vim.wait(4000,function() local op=provider.next(); return op and op.kind=='commit' end))
vim.api.nvim_buf_set_lines(b,0,0,false,{''})
vim.wait(200)
vim.api.nvim_buf_set_lines(b,2,2,false,{''})
local transaction
assert(vim.wait(4000,function()
  local op=provider.next()
  if op and op.kind=='begin' then transaction=op end
  return op and op.kind=='commit'
end))
assert(transaction.total==7, vim.inspect(transaction))
assert(transaction.total==5-transaction.delete+transaction.insert, vim.inspect(transaction))
provider.set_overlays({selection={1,2},word='x',occurrences={1}})
provider.set_overlays({selection=vim.NIL,word=vim.NIL,occurrences={}})
local state_op=provider.next()
assert(state_op.kind=='state' and state_op.selection==vim.NIL and state_op.word==vim.NIL)
provider.stop()
print('minimap queued edits: PASS')
local plain=vim.api.nvim_create_buf(false,true)
vim.api.nvim_buf_set_lines(plain,0,-1,false,{'plain\ttext', 'bad '..string.char(255)..' text'})
local fallback
source.rows(plain,1,2,function(r) fallback=r end)
assert(vim.wait(1000,function() return fallback~=nil end))
assert(#fallback[1].spans==0)
assert(fallback[2].text=='bad � text')
vim.api.nvim_buf_delete(plain,{force=true})
print('minimap fallback and invalid UTF-8: PASS')
vim.treesitter.query.set('lua','highlights', '((string) @string (#set! priority 150)) ((string) @constant (#set! priority 200))')
vim.api.nvim_set_hl(0,'@constant.lua',{fg='#aabbcc'})
vim.api.nvim_buf_set_lines(b,0,-1,false,{'\t"hé界"'})
local colored, colors
source.rows(b,1,1,function(r,p) colored,colors=r,p end)
assert(vim.wait(1000,function() return colored~=nil end))
assert(colored[1].text=='    "hé界"')
assert(colored[1].spans[1][1]==4 and colored[1].spans[1][2]==#colored[1].text, vim.inspect(colored))
assert(colors[colored[1].spans[1][3]+1]=='#aabbcc',vim.inspect({colored,colors}))
print('minimap Tree-sitter priority and tab offsets: PASS')
vim.bo[b].tabstop=8
vim.api.nvim_buf_set_lines(b,0,-1,false,{'á\tx',string.rep('a',255)..'áx'})
local combined
source.rows(b,1,2,function(r) combined=r end)
assert(vim.wait(1000,function() return combined~=nil end))
assert(combined[1].text=='á'..string.rep(' ',7)..'x',vim.inspect(combined[1]))
assert(combined[2].text==string.rep('a',255)..'á',vim.inspect(combined[2]))
assert(vim.fn.strdisplaywidth(combined[2].text)==256)
print('minimap combining width and clipping: PASS')
