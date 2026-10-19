local M = {}
local MAX_BYTES=64*1024*1024
function M.watch(buffer, on_change)
  buffer=buffer==0 and vim.api.nvim_get_current_buf() or buffer
  local stopped, serial, running=false,0,nil
  local watchers, baseline, head, root, gitdir, common={},nil,nil,nil,nil,nil
  local filename=vim.api.nvim_buf_get_name(buffer)
  local timer=vim.uv.new_timer()
  local debounce=vim.uv.new_timer()
  local group=vim.api.nvim_create_augroup('VSVimMinimapGit'..buffer,{clear=true})
  local refresh, stop
  local pending_head=false
  local function valid() return not stopped and vim.api.nvim_buf_is_valid(buffer) end
  local function emit(value) if valid() then on_change(value) end end
  local function compare()
    if not valid() or baseline==nil then return end
    local lines=vim.api.nvim_buf_get_lines(buffer,0,-1,false)
    local current=table.concat(lines,'\n')..(vim.bo[buffer].endofline and '\n' or '')
    if #lines==1 and lines[1]=='' then
      local empty=false
      vim.api.nvim_buf_call(buffer,function() empty=vim.fn.wordcount().bytes==0 end)
      if empty then current='' end
    end
    if #current>MAX_BYTES then emit({changes={},error='Minimap Git buffer exceeds 64 MiB'}); return end
    local ok,hunks=pcall(vim.diff,baseline,current,{result_type='indices'})
    if not ok then emit({changes={},error=tostring(hunks)}); return end
    local groups={}
    for _,h in ipairs(hunks) do
      local _,removed,start,added=unpack(h)
      local kind=removed==0 and 'added' or added==0 and 'deleted' or 'modified'
      local first=math.max(1,math.min(#lines,added==0 and start+1 or start))
      local item={start=first,['end']=math.min(#lines,first+math.max(1,added)-1),kind=kind}
      local prev=groups[#groups]
      if prev and item.start<=prev['end'] then
        prev['end']=math.max(prev['end'],item['end'])
        if prev.kind~=item.kind then prev.kind='modified' end
      else groups[#groups+1]=item end
    end
    emit({changes=groups,head=head})
  end
  local function schedule(check_head)
    if not valid() then return end
    pending_head=pending_head or check_head
    debounce:stop()
    debounce:start(40,0,vim.schedule_wrap(function()
      local check=pending_head; pending_head=false
      if check then refresh() else compare() end
    end))
  end
  local function watch_paths(symbolic)
    for _,w in ipairs(watchers) do w:stop(); w:close() end
    watchers={}
    local seen={}
    local paths={gitdir,common,common and common..'/refs',common and common..'/refs/heads'}
    if symbolic and common then paths[#paths+1]=vim.fs.dirname(common..'/'..symbolic) end
    for _,path in ipairs(paths) do
      if path and not seen[path] then
        seen[path]=true
        local w=vim.uv.new_fs_event()
        local ok=w:start(path,{},function() vim.schedule(function() schedule(true) end) end)
        if ok then watchers[#watchers+1]=w else w:close() end
      end
    end
  end
  local function run(args, token, done)
    local chunks,size,overflow={},0,false
    local process
    process=vim.system(args,{text=false,stdout=function(err,data)
      if err then overflow=true end
      if data then
        size=size+#data
        if size>MAX_BYTES then overflow=true; if process then process:kill(15) end
        else chunks[#chunks+1]=data end
      end
    end},function(result)
      vim.schedule(function()
        if not valid() or token~=serial then return end
        running=nil
        if overflow then done(nil,'Git output exceeds 64 MiB or could not be read')
        else done({code=result.code,stdout=table.concat(chunks),stderr=result.stderr or ''}) end
      end)
    end)
    running=process
  end
  local function failure(message) baseline=nil; emit({changes={},error=message}) end
  refresh=function()
    if not valid() then return end
    serial=serial+1
    local token=serial
    if running then running:kill(15); running=nil end
    local name=vim.api.nvim_buf_get_name(buffer)
    if name=='' then failure('Buffer has no file path'); return end
    local dir=vim.fs.dirname(name)
    run({'git','-C',dir,'rev-parse','--show-toplevel','--absolute-git-dir','--git-common-dir'},token,function(result,err)
      if not result or result.code~=0 then failure(err or result.stderr); return end
      local parts=vim.split(vim.trim(result.stdout),'\n',{plain=true})
      root,gitdir,common=parts[1],parts[2],parts[3]
      if common and common:sub(1,1)~='/' then common=vim.fs.normalize(dir..'/'..common) end
      local relative=vim.fs.relpath(root,name)
      if not relative then failure('File is outside Git worktree'); return end
      run({'git','-C',root,'symbolic-ref','-q','HEAD'},token,function(sym)
        watch_paths(sym and sym.code==0 and vim.trim(sym.stdout) or nil)
        run({'git','-C',root,'rev-parse','--verify','HEAD'},token,function(rev,rev_err)
          if not rev then failure(rev_err); return end
          if rev.code~=0 then
            if sym and sym.code==0 then
              run({'git','-C',root,'show-ref','--exists',vim.trim(sym.stdout)},token,function(exists,exists_err)
                if exists and exists.code==2 then baseline,head='',nil; compare()
                else failure(exists_err or rev.stderr) end
              end)
            else failure(rev.stderr) end
            return
          end
          local sha=vim.trim(rev.stdout)
          if sha==head and baseline~=nil then compare(); return end
          run({'git','-C',root,'ls-tree','-z',sha,'--',relative},token,function(entry,entry_err)
            if not entry or entry.code~=0 then failure(entry_err or entry.stderr); return end
            if entry.stdout=='' then baseline,head='',sha; compare(); return end
            run({'git','-C',root,'show',sha..':'..relative},token,function(content,content_err)
              if not content or content.code~=0 then failure(content_err or content.stderr); return end
              baseline,head=content.stdout,sha
              compare()
            end)
          end)
        end)
      end)
    end)
  end
  vim.api.nvim_buf_attach(buffer,false,{
    on_lines=function() if stopped then return true end; schedule(false) end,
    on_detach=function() vim.schedule(function() if stop then stop() end end) end,
  })
  vim.api.nvim_create_autocmd({'BufEnter','BufWritePost','BufFilePost'},{group=group,buffer=buffer,callback=function()
    local name=vim.api.nvim_buf_get_name(buffer)
    if name~=filename then
      filename=name; head=nil; baseline=nil; serial=serial+1
      if running then running:kill(15); running=nil end
      emit({changes={}})
    end
    schedule(true)
  end})
  vim.api.nvim_create_autocmd('FocusGained',{group=group,callback=function() schedule(true) end})
  timer:start(2000,2000,vim.schedule_wrap(function() if valid() then schedule(true) end end))
  refresh()
  stop=function()
    if stopped then return end
    stopped=true; serial=serial+1
    if running then running:kill(15) end
    for _,w in ipairs(watchers) do w:stop(); w:close() end
    timer:stop(); timer:close(); debounce:stop(); debounce:close()
    pcall(vim.api.nvim_del_augroup_by_id,group)
  end
  return stop
end
return M
