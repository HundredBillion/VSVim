local M = {}
local installed, unsafe, original_get, original_parse
local queries, texts, listeners = {}, setmetatable({}, {__mode='k'}), {}
local depth=0
local listener_serial=0
local registrations={}
local function reject(reason)
  if unsafe then return end
  unsafe=reason
  for _,fn in pairs(listeners) do fn(reason) end
end
function M.observe()
  if installed then return end
  installed=true
  if package.loaded['vim.treesitter.query'] then unsafe='Tree-sitter queries were loaded before minimap observation' end
  local query=require('vim.treesitter.query')
  original_get,original_parse=query.get,query.parse
  local runtime=vim.env.VIMRUNTIME
  local readers={['@'..runtime..'/lua/vim/treesitter/languagetree.lua']=true,
    ['@'..runtime..'/lua/vim/treesitter/highlighter.lua']=true}
  query.parse=function(lang,text,...)
    if depth==0 then reject('A caller owns a compiled Tree-sitter query') end
    local result=original_parse(lang,text,...)
    texts[result]=text
    return result
  end
  query.get=function(lang,group,...)
    local caller=debug.getinfo(2,'S')
    if not caller or not readers[caller.source] then reject('A caller owns a compiled Tree-sitter query') end
    depth=depth+1
    local ok,result=pcall(original_get,lang,group,...)
    depth=depth-1
    if not ok then error(result) end
    if result and texts[result] then queries[lang..':'..group]={lang=lang,group=group,text=texts[result]} end
    return result
  end
  local set=query.set
  query.set=function(lang,group,text,...)
    queries[lang..':'..group]=text and {lang=lang,group=group,text=text,raw=true} or nil
    return set(lang,group,text,...)
  end
  for _,name in ipairs({'add_predicate','add_directive'}) do
    local original=query[name]
    query[name]=function(...)
      reject('A custom Tree-sitter '..name..' handler is installed')
      return original(...)
    end
  end
  local function preserve_methods(wrapper,original)
    if type(original)~='table' then return wrapper end
    return setmetatable({}, {__call=function(_,...) return wrapper(...) end,
      __index=function(_,name)
        local value=original[name]
        if type(value)=='function' then return function(_,...) return value(original,...) end end
        return value
      end})
  end
  query.get=preserve_methods(query.get,original_get)
  query.parse=preserve_methods(query.parse,original_parse)
  local language=vim.treesitter.language
  local register=language.register
  language.register=function(lang,filetypes,...)
    registrations[#registrations+1]={lang=lang,filetypes=vim.deepcopy(filetypes)}
    return register(lang,filetypes,...)
  end
  M.public_get=query.get
  M.public_parse=query.parse
end
function M.safe()
  M.observe()
  local query=require('vim.treesitter.query')
  if query.get~=M.public_get or query.parse~=M.public_parse then reject('Tree-sitter query functions were replaced') end
  local bytes=0
  for _,value in pairs(queries) do bytes=bytes+#value.text end
  if bytes>128*1024 then reject('Tree-sitter query configuration exceeds worker control bounds') end
  return not unsafe
end
function M.get(lang,group)
  M.observe()
  depth=depth+1
  local ok,result=pcall(original_get,lang,group)
  depth=depth-1
  if not ok then error(result) end
  if result and texts[result] then queries[lang..':'..group]={lang=lang,group=group,text=texts[result]} end
  return result
end
function M.snapshot()
  local result={}
  for _,value in pairs(queries) do result[#result+1]=value end
  return {queries=result,languages=registrations}
end
function M.use_main(reason) reject(reason) end
function M.status() return {safe=M.safe(),reason=unsafe or vim.NIL} end
function M.on_unsafe(fn)
  listener_serial=listener_serial+1
  local index=listener_serial
  listeners[index]=fn
  return function() listeners[index]=nil end
end
return M
