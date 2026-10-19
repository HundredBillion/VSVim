vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(assert(vim.env.VSVIM_SPRITE_SOURCE, "Set VSVIM_SPRITE_SOURCE to the new sprite.nvim checkout"))
vim.o.hidden = true
vim.o.swapfile = false
vim.cmd("filetype plugin on")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = root .. "/read me.md"
vim.fn.writefile({ "# Hello", "", "Some **Markdown**." }, path)
vim.cmd.edit(vim.fn.fnameescape(path))
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 3, 5 })
local source = require("vsvim.markdown")
local bridge = require("sprite.markdown")
source.setup()
assert(not source.previewing(), "unsupported host remains editable")
bridge.attach(99999)
local document, state
local function wait_for(predicate)
	assert(
		vim.wait(3000, function()
			local op = bridge.pull()
			if op ~= vim.NIL then
				if op.kind == "document" then
					document = op
				elseif op.kind == "state" then
					state = op
				end
			end
			return predicate()
		end, 1),
		"Markdown state did not settle: " .. vim.inspect({ document = document, state = state })
	)
end
wait_for(function()
	return document and state and state.windows[1] and state.windows[1].preview
end)
assert(source.previewing())
assert(document.text == "# Hello\n\nSome **Markdown**.\n")
assert(document.buffer == buffer and state.windows[1].buffer == buffer)
local cursor = vim.api.nvim_win_get_cursor(0)
local undo = vim.fn.undotree().seq_cur
source.toggle()
wait_for(function()
	return state.windows[1] and not state.windows[1].preview
end)
assert(vim.api.nvim_get_current_buf() == buffer)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor))
assert(not vim.bo.modified and vim.fn.undotree().seq_cur == undo)
vim.cmd("normal! A unsaved")
local edited = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local tick = vim.api.nvim_buf_get_changedtick(0)
local changed_undo = vim.fn.undotree().seq_cur
source.toggle()
wait_for(function()
	return document.generation == tick and document.text:find("unsaved", 1, true) and state.windows[1].preview
end)
assert(vim.bo.modified and vim.fn.undotree().seq_cur == changed_undo)
assert(vim.api.nvim_get_current_buf() == buffer)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), edited))
assert(not bridge.before_input({ type = "paste", text = "must not replace source" }))
assert(not bridge.before_input({ type = "input", key = "x" }))
assert(bridge.before_input({ type = "input", key = ":" }))
assert(bridge.before_input({ type = "input", key = "<D-s>" }))
source.toggle()
vim.cmd.undo()
assert(not vim.api.nvim_get_current_line():find("unsaved", 1, true), "undo survives toggles")
vim.cmd.redo()
assert(vim.api.nvim_get_current_line():find("unsaved", 1, true), "redo survives toggles")
vim.cmd.write()
assert(not vim.bo.modified)
assert(vim.fn.readfile(path)[3]:find("unsaved", 1, true))
wait_for(function()
	return state.windows[1] and state.windows[1].generation == vim.api.nvim_buf_get_changedtick(buffer)
end)
local stale_state = vim.deepcopy(state)
vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "# New generation" })
local stale_target = stale_state.windows[1]
assert(not bridge.dispatch({
	type = "markdown_action",
	revision = stale_state.revision,
	window = stale_target.window,
	buffer = buffer,
	generation = stale_target.generation,
	action = "toggle",
}), "stale toggle cannot act on changed source")
local plain = root .. "/plain.lua"
vim.fn.writefile({ "return 1" }, plain)
vim.cmd.edit(vim.fn.fnameescape(plain))
wait_for(function()
	return #state.windows == 0
end)
assert(not source.previewing())
vim.cmd.buffer(buffer)
wait_for(function()
	return state.windows[1] and not state.windows[1].preview
end)
assert(not source.previewing(), "tab switches remember source mode")
source.toggle()
vim.cmd.vsplit()
wait_for(function()
	return #state.windows == 2 and state.windows[1].preview and state.windows[2].preview
end)
for _, target in ipairs(state.windows) do
	assert(target.buffer == buffer, "split shares original file buffer")
end
local inactive = state.windows[2]
assert(
	bridge.dispatch({
		type = "markdown_action",
		revision = state.revision,
		window = inactive.window,
		buffer = inactive.buffer,
		generation = inactive.generation,
		action = "focus",
	}),
	"preview press focuses its own Neovim window"
)
assert(vim.api.nvim_get_current_win() == inactive.window)
wait_for(function()
	return state.active == inactive.window
end)
local split = vim.api.nvim_get_current_win()
vim.wo[split].winbar = "Markdown document"
vim.wo[split].number = true
source.toggle()
source.toggle()
wait_for(function()
	for _, target in ipairs(state.windows) do
		if target.window == split then
			local info = vim.fn.getwininfo(split)[1]
			return target.row == info.winrow - 1 + info.winbar
				and target.height == info.height
				and target.width == info.width
		end
	end
end)
vim.cmd.close()
wait_for(function()
	return #state.windows == 1
end)
local live = state.windows[1]
source.toggle()
assert(not bridge.dispatch({
	type = "markdown_action",
	revision = state.revision,
	window = live.window,
	buffer = live.buffer,
	generation = live.generation,
	action = "open",
	destination = "obsolete.md",
}), "a queued link cannot navigate after switching to source")
assert(vim.api.nvim_get_current_buf() == buffer)
source.toggle()
vim.fn.mkdir(root .. "/moved", "p")
local renamed = root .. "/moved/renamed.md"
local rename_tick = vim.api.nvim_buf_get_changedtick(buffer)
vim.cmd.file(vim.fn.fnameescape(renamed))
renamed = vim.api.nvim_buf_get_name(buffer)
assert(vim.api.nvim_buf_get_changedtick(buffer) == rename_tick, "rename does not change text generation")
wait_for(function()
	return document.path == renamed and document.generation == rename_tick
end)

local lines = {}
for i = 1, 10000 do
	lines[i] = "paragraph " .. i
end
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
local old_tick = vim.api.nvim_buf_get_changedtick(buffer)
wait_for(function()
	return state.windows[1].generation == old_tick
end)
vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { "# Latest after cancellation" })
local latest_tick = vim.api.nvim_buf_get_changedtick(buffer)
wait_for(function()
	return document.generation == latest_tick
end)
assert(document.text:match("^# Latest after cancellation"))
assert(document.text:find("paragraph 10000", 1, true))
local fallback_events = 0
vim.api.nvim_create_autocmd("User", {
	pattern = "VSVimMarkdownChanged",
	callback = function()
		fallback_events = fallback_events + 1
	end,
})
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { string.rep("x", 2 * 1024 * 1024 + 1) })
wait_for(function()
	return state.windows[1] and not state.windows[1].preview
end)
assert(not source.previewing(), "over-limit files stay editable")
assert(fallback_events > 0, "automatic source fallback refreshes the minimap")
assert(bridge.before_input({ type = "input", key = "x" }))
local buffers = {}
for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
	buffers[#buffers + 1] = info.bufnr
end
assert(#buffers == 2, "preview creates no extra listed file buffer")

bridge.attach(nil)
assert(not source.previewing())
assert(bridge.before_input({ type = "paste", text = "source is editable" }))
vim.fn.delete(root, "rf")
print("VSVim Markdown single-buffer behavior passed")
