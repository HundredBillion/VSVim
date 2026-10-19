local M = {}
local bridge
local supported, dirty, scheduled = false, true, false
local modes, observed, jobs, ready, sent = {}, {}, {}, {}, {}
local current, previous, epoch = {}, nil, 0
local prefix
local LIMIT = 2 * 1024 * 1024

local function changed()
  dirty = true
  if bridge then
    bridge.changed()
  end
end

local function invalidate()
  if scheduled then
    return
  end
  scheduled = true
  vim.schedule(function()
    scheduled = false
    changed()
  end)
end

local function markdown(buffer)
  return vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buftype == "" and vim.bo[buffer].filetype == "markdown"
end

function M.previewing(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  return supported and markdown(buffer) and modes[buffer] ~= false
end

local function warn(buffer, reason)
  modes[buffer] = false
  jobs[buffer], ready[buffer], sent[buffer] = nil, nil, nil
  vim.schedule(function()
    vim.notify("Markdown preview: " .. reason .. "; showing source", vim.log.levels.WARN)
  end)
  changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "VSVimMarkdownChanged", modeline = false })
end

local function observe(buffer)
  if observed[buffer] then
    return
  end
  observed[buffer] = true
  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = function()
      invalidate()
    end,
    on_changedtick = function()
      invalidate()
    end,
    on_detach = function()
      observed[buffer], jobs[buffer], ready[buffer], sent[buffer], modes[buffer] = nil, nil, nil, nil, nil
      invalidate()
    end,
  })
end

local function extract(buffer, tick)
  local path = vim.api.nvim_buf_get_name(buffer)
  if jobs[buffer] and jobs[buffer].tick == tick and jobs[buffer].path == path then
    return
  end
  local total = vim.api.nvim_buf_line_count(buffer)
  if vim.api.nvim_buf_get_offset(buffer, total) > LIMIT then
    warn(buffer, "document exceeds 2 MiB")
    return
  end
  if #path > 4096 then
    warn(buffer, "filename exceeds 4096 bytes")
    return
  end
  local job = { tick = tick, epoch = epoch, path = path, row = 0, lines = {} }
  jobs[buffer] = job
  local function step()
    if
      jobs[buffer] ~= job
      or epoch ~= job.epoch
      or not supported
      or not markdown(buffer)
      or not current[buffer]
      or not M.previewing(buffer)
      or vim.api.nvim_buf_get_changedtick(buffer) ~= tick
      or vim.api.nvim_buf_get_name(buffer) ~= path
    then
      if jobs[buffer] == job then
        jobs[buffer] = nil
        invalidate()
      end
      return
    end
    local stop = math.min(total, job.row + 256)
    local lines = vim.api.nvim_buf_get_lines(buffer, job.row, stop, false)
    for _, line in ipairs(lines) do
      job.lines[#job.lines + 1] = line
    end
    job.row = stop
    if stop < total then
      vim.schedule(step)
      return
    end
    local text = table.concat(job.lines, "\n") .. (vim.bo[buffer].endofline and "\n" or "")
    jobs[buffer] = nil
    if #text > LIMIT then
      warn(buffer, "document exceeds 2 MiB")
      return
    end
    ready[buffer] = { kind = "document", buffer = buffer, generation = tick, path = path, text = text }
    changed()
  end
  vim.schedule(step)
end

local function obscured()
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == "c" or mode:sub(1, 1) == "r" or mode == "!" then
    return true
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return true
    end
  end
  return false
end

local function color(group, key, fallback)
  local value = vim.api.nvim_get_hl(0, { name = group, link = false })[key]
  return value and string.format("#%06x", value) or fallback
end

local function snapshot()
  local windows, active = {}, vim.NIL
  local visible = {}
  if not obscured() then
    local focused = vim.api.nvim_get_current_win()
    local all = vim.api.nvim_tabpage_list_wins(0)
    table.sort(all, function(a, b)
      if a == b then
        return false
      end
      if a == focused then
        return true
      elseif b == focused then
        return false
      end
      return a < b
    end)
    for _, win in ipairs(all) do
      local buffer = vim.api.nvim_win_get_buf(win)
      if #windows < 16 and markdown(buffer) and vim.api.nvim_win_get_config(win).relative == "" then
        observe(buffer)
        visible[buffer] = true
        local info = vim.fn.getwininfo(win)[1]
        local row, column = info.winrow - 1 + info.winbar, info.wincol - 1
        local height, width = info.height, info.width
        if height > 0 and width > 0 and row + height <= vim.o.lines and column + width <= vim.o.columns then
          windows[#windows + 1] = {
            window = win,
            buffer = buffer,
            generation = vim.api.nvim_buf_get_changedtick(buffer),
            preview = M.previewing(buffer),
            row = row,
            column = column,
            width = width,
            height = height,
          }
          if win == focused then
            active = win
          end
        end
      end
    end
  end
  current = visible
  for buffer in pairs(jobs) do
    if not visible[buffer] then
      jobs[buffer] = nil
    end
  end
  for buffer in pairs(ready) do
    if not visible[buffer] then
      ready[buffer] = nil
    end
  end
  for buffer in pairs(sent) do
    if not visible[buffer] then
      sent[buffer] = nil
    end
  end
  for _, target in ipairs(windows) do
    local path = vim.api.nvim_buf_get_name(target.buffer)
    local published, prepared = sent[target.buffer], ready[target.buffer]
    if
      target.preview
      and (not published or published.generation ~= target.generation or published.path ~= path)
      and (not prepared or prepared.generation ~= target.generation or prepared.path ~= path)
    then
      extract(target.buffer, target.generation)
      target.preview = M.previewing(target.buffer)
    end
  end
  return {
    kind = "state",
    active = active,
    windows = windows,
    colors = {
      background = color("Normal", "bg", "#1e1f22"),
      foreground = color("Normal", "fg", "#bcbec4"),
      muted = color("Comment", "fg", "#9da0a8"),
      accent = color("Underlined", "fg", "#589df6"),
      code = color("NormalFloat", "bg", "#2b2d30"),
    },
  }
end

local provider = {}
function provider.next()
  if not supported then
    return nil
  end
  if dirty then
    dirty = false
    local state = snapshot()
    if not vim.deep_equal(state, previous) then
      previous = state
      return state
    end
  end
  for buffer, document in pairs(ready) do
    ready[buffer] = nil
    if
      current[buffer]
      and markdown(buffer)
      and M.previewing(buffer)
      and document.generation == vim.api.nvim_buf_get_changedtick(buffer)
      and document.path == vim.api.nvim_buf_get_name(buffer)
    then
      sent[buffer] = { generation = document.generation, path = document.path }
      return document
    end
  end
end

function M.toggle(buffer)
  buffer = buffer or vim.api.nvim_get_current_buf()
  if not markdown(buffer) then
    return false
  end
  if not supported then
    vim.notify("Markdown preview requires a Sprite host with grid-markdown-v1", vim.log.levels.INFO)
    return false
  end
  modes[buffer] = not M.previewing(buffer)
  prefix = nil
  if modes[buffer] and vim.api.nvim_get_current_buf() == buffer then
    local mode = vim.api.nvim_get_mode().mode
    if mode:sub(1, 1) == "i" then
      vim.cmd.stopinsert()
    elseif mode == "v" or mode == "V" or mode == "\22" or mode:sub(1, 1) == "s" then
      vim.cmd.normal({ bang = true, args = { vim.keycode("<Esc>") } })
    end
  end
  changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "VSVimMarkdownChanged", modeline = false })
  return true
end

function provider.dispatch(event)
  if
    not supported
    or not vim.api.nvim_win_is_valid(event.window)
    or vim.api.nvim_win_get_tabpage(event.window) ~= vim.api.nvim_get_current_tabpage()
    or vim.api.nvim_win_get_buf(event.window) ~= event.buffer
    or not markdown(event.buffer)
    or vim.api.nvim_buf_get_changedtick(event.buffer) ~= event.generation
    or obscured()
  then
    return false
  end
  local shown
  for _, target in ipairs(previous and previous.windows or {}) do
    if target.window == event.window then
      shown = target
      break
    end
  end
  if not shown or shown.preview ~= M.previewing(event.buffer) or (event.action ~= "toggle" and not shown.preview) then
    return false
  end
  if event.action == "toggle" then
    if vim.api.nvim_get_current_win() ~= event.window then
      return false
    end
    return M.toggle(event.buffer)
  end
  if event.action == "focus" then
    vim.api.nvim_set_current_win(event.window)
    return true
  end
  if event.action == "open" then
    local destination = event.destination
    if type(destination) ~= "string" or #destination > 4096 or destination:find("[%z\r\n]") then
      return false
    end
    destination = destination:match("^[^#]*")
    if destination == "" then
      return false
    end
    if destination:match("^file://") then
      local ok, filename = pcall(vim.uri_to_fname, destination)
      if not ok then
        return false
      end
      destination = filename
    elseif destination:match("^%a[%w+.-]*:") then
      return false
    else
      destination = vim.uri_decode(destination)
    end
    if destination:find("[%z\r\n]") then
      return false
    end
    local path =
      vim.fs.normalize(vim.fs.joinpath(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(event.buffer), ":h"), destination))
    if destination:sub(1, 1) == "/" then
      path = destination
    end
    vim.api.nvim_set_current_win(event.window)
    local ok, reason = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    if not ok then
      vim.notify(tostring(reason), vim.log.levels.WARN)
    end
    return ok
  end
  return false
end

function provider.before_input(event)
  if not M.previewing() or obscured() then
    prefix = nil
    return true
  end
  if event.type == "mouse" then
    for _, target in ipairs(previous and previous.windows or {}) do
      if
        target.preview
        and event.row >= target.row
        and event.row < target.row + target.height
        and event.col >= target.column
        and event.col < target.column + target.width
      then
        return false
      end
    end
    return true
  end
  if event.type ~= "input" then
    return false
  end
  local key = event.key or event.text or ""
  if prefix then
    local chord = prefix .. key
    prefix = nil
    if chord == " g" then
      prefix = chord
    elseif chord == " e" then
      require("vsvim.sidebar").explorer()
    elseif chord == " gs" then
      require("vsvim.sidebar").scm()
    end
    return false
  end
  if key == " " or key == "<Space>" then
    prefix = " "
    return false
  end
  if
    key:sub(1, 1) == ":"
    or key == "<D-s>"
    or key == "<Esc>"
    or key == "<C-h>"
    or key == "<C-l>"
    or key == "<C-b>"
    or key == "<C-S-g>"
  then
    return true
  end
  return false
end

function provider.attached(value)
  supported = value == true
  epoch = epoch + 1
  jobs, ready, sent, current, previous = {}, {}, {}, {}, nil
  changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "VSVimMarkdownChanged", modeline = false })
end

function provider.stop()
  supported, prefix = false, nil
  epoch = epoch + 1
  jobs, ready, sent, current, previous = {}, {}, {}, {}, nil
end

function M.setup()
  local ok, native = pcall(require, "sprite.markdown")
  if not ok then
    return
  end
  bridge = native
  local group = vim.api.nvim_create_augroup("VSVimMarkdown", { clear = true })
  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufWinEnter",
    "BufFilePost",
    "FileType",
    "WinEnter",
    "WinClosed",
    "WinResized",
    "VimResized",
    "TabEnter",
    "ColorScheme",
    "ModeChanged",
    "CmdlineEnter",
    "CmdlineLeave",
  }, { group = group, callback = invalidate })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(event)
      modes[event.buf], observed[event.buf], jobs[event.buf], ready[event.buf], sent[event.buf] =
        nil, nil, nil, nil, nil
      invalidate()
    end,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "winbar", "number", "relativenumber", "signcolumn", "laststatus", "cmdheight" },
    callback = invalidate,
  })
  vim.api.nvim_create_user_command("VSVimMarkdownToggle", function()
    M.toggle()
  end, { desc = "Toggle Markdown source and preview", force = true, bar = true })
  bridge.setup(provider)
end

return M
