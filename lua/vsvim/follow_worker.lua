local uv = vim.uv
local root = assert(arg[1])
local MAX_FILE, MAX_TOTAL, MAX_FILES = 1024 * 1024, 64 * 1024 * 1024, 20000
local excluded = { ['.git']=true, node_modules=true, vendor=true, target=true, dist=true,
  build=true, ['.cache']=true, __pycache__=true, ['.venv']=true, venv=true, ['.worktrees']=true }
local function allowed(path)
  for part in path:gmatch('[^/]+') do
    if excluded[part] then return false end
  end
  return not (path:match('%.sw[pon]$') or path:match('~$') or path:match('%.tmp$')
    or path:match('%.pyc$') or vim.fs.basename(path):match('^%.#'))
end
local function emit(value)
  io.stdout:write(vim.json.encode(value), '\n')
  io.stdout:flush()
end
local git = vim.system({'git', '-C', root, 'rev-parse', '--show-toplevel'}, {text=true}):wait(10000)
local repository = git.code == 0
local function paths()
  local result = {}
  if repository then
    local listing = vim.system({'git', '-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '.'}):wait(10000)
    if listing.code ~= 0 then error('Cannot list project files: ' .. (listing.stderr or 'Git failed')) end
    for path in listing.stdout:gmatch('[^%z]+') do
      if allowed(path) then result[path] = true end
    end
  else
    local count = 0
    local function visit(dir, prefix)
      local scan, err = uv.fs_scandir(dir)
      if not scan then error('Cannot read ' .. dir .. ': ' .. tostring(err)) end
      while true do
        local name, kind = uv.fs_scandir_next(scan)
        if not name then break end
        count = count + 1
        if count > 100000 then error('Project exceeds 100,000 directory entries') end
        local relative = prefix .. name
        if allowed(relative) then
          if kind == 'directory' then visit(dir .. '/' .. name, relative .. '/')
          elseif kind == 'file' then result[relative] = true end
        end
      end
    end
    visit(root, '')
  end
  local ordered = vim.tbl_keys(result)
  table.sort(ordered)
  if #ordered > MAX_FILES then error('Project exceeds 20,000 eligible files') end
  return ordered
end
local function regular(path)
  local current = root
  for part in path:gmatch('[^/]+') do
    if part == '..' or part == '.' then return nil end
    current = current .. '/' .. part
    local stat = uv.fs_lstat(current)
    if not stat or stat.type == 'link' then return nil end
  end
  local stat = uv.fs_stat(current)
  if stat and stat.type == 'file' and stat.size <= MAX_FILE then return stat end
end
local function stamp(stat)
  return table.concat({stat.ino, stat.size, stat.mtime.sec, stat.mtime.nsec,
    stat.ctime.sec, stat.ctime.nsec}, ':')
end
local function read(path, stat)
  local fd = uv.fs_open(path, 'r', 0)
  if not fd then return nil end
  local data = uv.fs_read(fd, stat.size + 1, 0)
  local final = uv.fs_fstat(fd)
  uv.fs_close(fd)
  if not data or #data > MAX_FILE or data:find('\0', 1, true) or not final
    or stamp(final) ~= stamp(stat) then return nil end
  return data
end
local function line(old, new)
  if old == nil then return 1 end
  local hunks = vim.diff(old, new, {result_type='indices', algorithm='histogram'})
  local last = hunks[#hunks]
  if not last then return nil end
  return math.max(1, last[3])
end
local previous, initialized = {}, false
local function scan()
  local next_snapshot, total, changes = {}, 0, {}
  for _, relative in ipairs(paths()) do
    local stat = regular(relative)
    if stat then
      local path = root .. '/' .. relative
      local old = previous[relative]
      local version = stamp(stat)
      local content = old and old.version == version and old.content or read(path, stat)
      if content then
        total = total + #content
        if total > MAX_TOTAL then error('Project exceeds 64 MiB of text snapshots') end
        next_snapshot[relative] = {version=version, content=content}
        if initialized and (not old or old.content ~= content) then
          changes[#changes+1] = {type='change', path=path, hash=vim.fn.sha256(content),
            line=line(old and old.content, content)}
        end
      end
    end
  end
  previous = next_snapshot
  if not initialized then initialized = true; emit({type='ready'}) end
  for _, change in ipairs(changes) do emit(change) end
end
local ok, failure = pcall(function()
  while true do scan(); vim.wait(300) end
end)
if not ok then emit({type='error', message=tostring(failure)}); os.exit(1) end
