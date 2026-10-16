local M = {}
local last_editor_buffer
local function escape(text) return text:gsub('%%', '%%%%'):gsub('[\r\n\t]', ' ') end
local icons = {
  lua={'●','#51a0cf'}, py={'◆','#ffbc03'}, js={'JS','#ffca28'}, ts={'TS','#42a5f5'},
  json={'{}','#fbc02d'}, md={'≡','#42a5f5'}, rs={'⚙','#dea584'},
  go={'go','#26c6da'}, toml={'≡','#ef5350'}, yaml={'≡','#ef5350'}, yml={'≡','#ef5350'},
}
local function buffers()
  local result, counts = {}, {}
  for _, b in ipairs(vim.fn.getbufinfo({buflisted=1})) do
    if vim.bo[b.bufnr].buftype=='' then
      b.label=vim.fn.fnamemodify(b.name, ':t')
      if b.label=='' then b.label='Untitled' end
      counts[b.label]=(counts[b.label] or 0)+1
      result[#result+1]=b
    end
  end
  for _,b in ipairs(result) do
    if counts[b.label]>1 and b.name~='' then
      b.label=b.label .. ' · ' .. vim.fn.fnamemodify(b.name, ':h:t')
    end
  end
  return result
end
function M.select(buffer, _, button)
  if button=='m' then M.close(buffer); return end
  if button~='l' or not vim.api.nvim_buf_is_valid(buffer) then return end
  local win=vim.api.nvim_get_current_win()
  if vim.bo.buftype~='' then
    win=nil
    for _,candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(candidate)].buftype=='' then win=candidate; break end
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win,buffer)
    last_editor_buffer=buffer
  end
end
function M.close(buffer, _, button)
  if button and button~='l' then return end
  if not vim.api.nvim_buf_is_valid(buffer) then return end
  local function remove(force)
    local previous_hidden=vim.bo[buffer].bufhidden
    vim.bo[buffer].bufhidden='hide'
    local ok,err=pcall(function()
      local replacement
      for _,b in ipairs(buffers()) do if b.bufnr~=buffer then replacement=b.bufnr; break end end
      for _,win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win)==buffer then
          replacement=replacement or vim.api.nvim_create_buf(true,false)
          vim.api.nvim_win_set_buf(win,replacement)
        end
      end
      vim.api.nvim_buf_delete(buffer,{force=force})
    end)
    if vim.api.nvim_buf_is_valid(buffer) then vim.bo[buffer].bufhidden=previous_hidden end
    if not ok then vim.notify(tostring(err),vim.log.levels.ERROR) end
  end
  if not vim.bo[buffer].modified then remove(false); return end
  vim.ui.select({'Save and close','Discard changes','Cancel'}, {prompt='Close modified file?'}, function(choice)
    if not vim.api.nvim_buf_is_valid(buffer) then return end
    if choice=='Discard changes' then remove(true)
    elseif choice=='Save and close' then
      local ok,err=pcall(vim.api.nvim_buf_call,buffer,function() vim.cmd.write() end)
      if ok then remove(false) else vim.notify(tostring(err),vim.log.levels.ERROR) end
    end
  end)
end
function M.render()
  if vim.bo.buftype=='' then last_editor_buffer=vim.api.nvim_get_current_buf() end
  local all=buffers()
  local active=1
  local offset=0
  local prefix=''
  for _,win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft=vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft=='svgtree' or ft=='scm' then
      offset=vim.api.nvim_win_get_width(win)+1
      local label=ft=='scm' and 'SOURCE CONTROL' or 'EXPLORER'
      prefix='%#TabLineFill# '..label..string.rep(' ',math.max(0,offset-#label-1))
      break
    end
  end
  for i,b in ipairs(all) do
    local ext=vim.fn.fnamemodify(b.name,':e')
    local icon=icons[ext] or {'◇','#bcbec4'}
    b.icon=icon[1]
    b.icon_group='VSVimTabIcon'..(icons[ext] and ext or 'File')
    b.width=vim.fn.strdisplaywidth(b.label)+vim.fn.strdisplaywidth(b.icon)+8
    if b.bufnr==last_editor_buffer then active=i end
  end
  local available=math.max(1,vim.o.columns-offset)
  local first,last=active,active
  local used=all[active] and all[active].width or 0
  while first>1 or last<#all do
    if first>1 and used+all[first-1].width+6<=available then
      first=first-1; used=used+all[first].width
    elseif last<#all and used+all[last+1].width+6<=available then
      last=last+1; used=used+all[last].width
    else break end
  end
  local parts={prefix}
  if first>1 then
    parts[#parts+1]='%#TabLine#%'..all[first-1].bufnr..'@v:lua.VSVimSelectBuffer@ ‹ %T'
  end
  for i=first,last do
    local b=all[i]
    if b then
      local group=i==active and 'TabLineSel' or 'TabLine'
      local icon_group=b.icon_group..(i==active and 'Active' or '')
      local label=b.label
      local budget=math.max(1,available-14-vim.fn.strdisplaywidth(b.icon))
      if vim.fn.strdisplaywidth(label)>budget then
        while #label>0 and vim.fn.strdisplaywidth(label)>budget-1 do
          label=vim.fn.strcharpart(label,0,vim.fn.strchars(label)-1)
        end
        label=label..'…'
      end
      parts[#parts+1]='%#'..group..'#%'..b.bufnr..'@v:lua.VSVimSelectBuffer@  '
        ..'%#'..icon_group..'#'..b.icon..'%#'..group..'# '..escape(label)..'  %T'
        ..'%'..b.bufnr..'@v:lua.VSVimCloseBuffer@'..(b.changed==1 and '●' or '×')..' %T'
        ..'%#VSVimTabBorder#│'
    end
  end
  if last<#all then parts[#parts+1]='%#TabLine#%'..all[last+1].bufnr..'@v:lua.VSVimSelectBuffer@ › %T' end
  return table.concat(parts)..'%#TabLineFill#%='
end
function M.setup()
  _G.VSVimSelectBuffer=M.select
  _G.VSVimCloseBuffer=M.close
  local function highlights()
    vim.api.nvim_set_hl(0,'VSVimTabBorder',{link='WinSeparator',default=true})
    local normal=vim.api.nvim_get_hl(0,{name='TabLine',link=false})
    local selected=vim.api.nvim_get_hl(0,{name='TabLineSel',link=false})
    for ext,icon in pairs(vim.tbl_extend('force',icons,{File={'◇','#bcbec4'}})) do
      vim.api.nvim_set_hl(0,'VSVimTabIcon'..ext,{fg=icon[2],bg=normal.bg})
      vim.api.nvim_set_hl(0,'VSVimTabIcon'..ext..'Active',{fg=icon[2],bg=selected.bg})
    end
  end
  highlights()
  local group=vim.api.nvim_create_augroup('VSVimTabs',{clear=true})
  vim.api.nvim_create_autocmd('ColorScheme',{group=group,callback=highlights})
end
return M
