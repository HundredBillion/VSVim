local M = {}
local jobs = {}
function M.storage_bytes(text,spans) return 48+#text+spans*24 end
local function color(name, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, {name=name, link=false})
  return ok and hl.fg and string.format('#%06x', hl.fg) or fallback
end
function M.background()
  local hl = vim.api.nvim_get_hl(0, {name='Normal', link=false})
  return hl.bg and string.format('#%06x', hl.bg) or '#1e1f22'
end
local function rgb(c)
  return tonumber(c:sub(2,3),16), tonumber(c:sub(4,5),16), tonumber(c:sub(6,7),16)
end
function M.palette_index(palette, value)
  for i,c in ipairs(palette) do if c == value then return i-1 end end
  if #palette < 256 then palette[#palette+1]=value; return #palette-1 end
  local r,g,b=rgb(value)
  local best, distance=0, math.huge
  for i,c in ipairs(palette) do
    local cr,cg,cb=rgb(c)
    local d=(r-cr)^2+(g-cg)^2+(b-cb)^2
    if d<distance then best,distance=i-1,d end
  end
  return best
end
local function captures(buffer, first, last)
  local result={}
  local ok, parser=pcall(vim.treesitter.get_parser, buffer)
  if not ok or not parser then return result end
  pcall(function()
    parser:parse({first-1,last})
    parser:for_each_tree(function(tree, langtree)
      local lang=langtree:lang()
      local query=require('vsvim.minimap.query_config').get(lang,'highlights')
      if not query then return end
      for id,node,metadata in query:iter_captures(tree:root(),buffer,first-1,last) do
        local range=vim.treesitter.get_range(node,buffer,metadata[id])
        local sr,sc,er,ec=range[1],range[2],range[4],range[5]
        local priority=tonumber((metadata[id] or {}).priority or metadata.priority) or 100
        local value=color('@'..query.captures[id]..'.'..lang)
        if value then
          for row=math.max(first-1,sr),math.min(last-1,er) do
            result[row+1]=result[row+1] or {}
            table.insert(result[row+1],{row==sr and sc or 0,row==er and ec or math.huge,priority,value})
          end
        end
      end
    end)
  end)
  return result
end
function M.rows(buffer, first, last, done, prepared)
  if jobs[buffer] then jobs[buffer]() end
  local cancelled=false
  local function cancel() cancelled=true end
  jobs[buffer]=cancel
  local tick=vim.api.nvim_buf_get_changedtick(buffer)
  local rows,palette={}, {color('Normal','#bcbec4')}
  local row,storage,failure=first,0,nil
  local syntax_colors={}
  local no_syntax=false
  vim.api.nvim_buf_call(buffer,function() no_syntax=vim.fn.execute('silent syntax list'):match('No Syntax items defined')~=nil end)
  local function batch()
    if cancelled or not vim.api.nvim_buf_is_valid(buffer) or vim.api.nvim_buf_get_changedtick(buffer)~=tick then return end
    local final=math.min(last,row+255)
    local highlights=prepared or captures(buffer,row,final)
    local started=vim.uv.hrtime()
    vim.api.nvim_buf_call(buffer,function()
      while row<=final do
        local line=vim.api.nvim_buf_get_lines(buffer,row-1,row,false)[1] or ''
        local parts,spans={},{}
        local cells,bytes,pos=0,0,1
        while pos<=#line do
          local lead=line:byte(pos)
          local len=lead<128 and 1 or lead<224 and 2 or lead<240 and 3 or 4
          local char=line:sub(pos,pos+len-1)
          local valid=lead<128 or lead>=194 and lead<=244 and #char==len
          for i=2,len do
            local byte=char:byte(i)
            if not byte or byte<128 or byte>191 then valid=false end
          end
          local second=char:byte(2) or 0
          if lead==224 and second<160 or lead==237 and second>=160 or lead==240 and second<144 or lead==244 and second>=144 then valid=false end
          if not valid then char='�'; len=1 end
          local text,width=char
          if lead<32 and char~='\t' or lead==127 then
            -- NUL cannot cross the Vim function string boundary; spell controls as the editor displays them.
            text=vim.o.display:find('uhex',1,true) and string.format('<%02x>',lead)
              or '^'..string.char(lead==127 and 63 or lead+64)
            width=#text
          elseif lead==194 and second>=128 and second<=159 then
            text=vim.fn.strtrans(char);width=#text
          else
            width=lead>=32 and lead<127 and 1 or vim.fn.strdisplaywidth(char,cells)
            if lead>=128 then
              -- The prefix is bounded to 2048 bytes, even when the source line is arbitrarily long.
              width=vim.fn.strdisplaywidth(table.concat(parts)..char)-cells
            end
            if char=='\t' then text=string.rep(' ',width) end
          end
          if cells+width>256 or bytes+#text>2048 then break end
          local value,priority=nil,-math.huge
          for _,cap in ipairs(highlights[row] or {}) do
            if pos-1>=cap[1] and pos-1<cap[2] and cap[3]>=priority then value,priority=cap[4],cap[3] end
          end
          if not value and not no_syntax then
            local id=vim.fn.synID(row,pos,1)
            local fg=syntax_colors[id]
            if fg==nil then fg=vim.fn.synIDattr(vim.fn.synIDtrans(id),'fg#'); syntax_colors[id]=fg end
            if fg:match('^#%x%x%x%x%x%x$') then value=fg end
          end
          local index=M.palette_index(palette,value or palette[1])
          if index~=0 and #text>0 then
            local prev=spans[#spans]
            if prev and prev[2]==bytes and prev[3]==index then prev[2]=bytes+#text
            elseif #spans<256 then spans[#spans+1]={bytes,bytes+#text,index} end
          end
          parts[#parts+1]=text
          cells,bytes,pos=cells+width,bytes+#text,pos+len
        end
        local text=table.concat(parts)
        storage=storage+M.storage_bytes(text,#spans)
        if storage>64*1024*1024 then failure='Minimap source exceeds 64 MiB'; break end
        rows[#rows+1]={text=text,spans=spans}
        row=row+1
        if vim.uv.hrtime()-started>=2000000 then break end
      end
    end)
    if failure then jobs[buffer]=nil; done(nil,nil,failure); return end
    if row<=last then vim.schedule(batch)
    elseif not cancelled then jobs[buffer]=nil; vim.schedule(function() if not cancelled then done(rows,palette) end end) end
  end
  vim.schedule(batch)
  return cancel
end
function M.color(name) return color(name) end
return M
