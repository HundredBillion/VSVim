local checkout = assert(arg[1], "Usage: nvim -u NONE -i NONE -l tests/explorer_benchmark.lua SVGTREE_CHECKOUT ROOT")
local root = assert(arg[2], "A filesystem root is required")
checkout = vim.fn.fnamemodify(checkout, ":p")
root = vim.fn.fnamemodify(root, ":p")
assert(vim.fn.filereadable(checkout .. "/lua/svgtree/init.lua") == 1, "Invalid SVGTree checkout")
assert(vim.fn.isdirectory(root) == 1, "Root must be an existing directory")
vim.opt.rtp:prepend(checkout)
local ready, rows, started, first_rows
local function done(cb)
	if type(cb) == "function" then
		vim.schedule(function()
			cb(nil)
		end)
	end
end
package.loaded.sprite = {
	available = function(cb)
		vim.schedule(function()
			cb(nil, { features = { "owned-dock-v1", "virtual-list-v1", "svg-assets-v1", "dock-resize-v1" } })
		end)
		return function() end
	end,
	register_tokens = function(_, cb)
		done(cb)
	end,
	on_resume = function()
		return function() end
	end,
	open = function(opts, cb)
		local dock = {}
		for _, name in ipairs({ "assets", "rows", "state", "update", "focus", "focus_editor" }) do
			dock[name] = function(_, ...)
				if name == "focus" then
					ready = true
				end
				if name == "rows" then
					rows = select(2, ...)
					first_rows = first_rows or (vim.uv.hrtime() - started) / 1e6
				end
				done(select(select("#", ...), ...))
			end
		end
		function dock:close()
			opts.on_close({ kind = "requested" })
		end
		vim.schedule(function()
			cb(nil, dock)
		end)
		return function() end
	end,
}
local tree = require("svgtree")
tree.setup({})
for i = 1, 5 do
	ready = false
	first_rows = nil
	rows = nil
	started = vim.uv.hrtime()
	tree.open(root)
	assert(
		vim.wait(10000, function()
			return ready
		end, 1),
		"Explorer not ready"
	)
	print(vim.json.encode({
		trial = i,
		phase = i == 1 and "initial" or "warm",
		root = root,
		first_rows_ms = first_rows,
		focus_request_ms = (vim.uv.hrtime() - started) / 1e6,
		rows = #rows,
		transport = "scheduled fake acknowledgements; no host paint",
	}))
	tree.close()
end
