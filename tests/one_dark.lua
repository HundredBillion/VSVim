vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("colorscheme vsvim-one-dark")
local function foreground(group)
  return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
end
for _, group in ipairs({
  "Keyword",
  "Statement",
  "StorageClass",
  "PreProc",
  "@keyword",
  "@keyword.return",
  "@keyword.function",
  "@keyword.repeat",
}) do
  assert(foreground(group) == 0xb477cf, group .. " uses Zed One Dark purple")
end
assert(
  vim.api.nvim_get_hl(0, { name = "TabLineFill", link = false }).bg == 0x1e1f22,
  "base tab colors survive theme loading"
)
assert(foreground("Function") == 0x73ade9)
assert(foreground("Type") == 0x6eb4bf)
assert(foreground("String") == 0xa1c181)
assert(foreground("@variable.member") == 0xd07277)
assert(foreground("@lsp.type.keyword") == 0xb477cf)
vim.opt.termguicolors = true
vim.cmd("syntax on")
vim.bo.filetype = "rust"
local rows = {
  "const LIMIT: usize = 8;",
  "fn example() {",
  '  let value = "hello";',
  "  for item in values {}",
  "}",
}
vim.api.nvim_buf_set_lines(0, 0, -1, false, rows)
for _, token in ipairs({ { 1, "const" }, { 2, "fn" }, { 3, "let" }, { 4, "for" } }) do
  local first = assert(rows[token[1]]:find(token[2], 1, true))
  local group = vim.fn.synIDtrans(vim.fn.synID(token[1], first, 1))
  assert(
    vim.fn.synIDattr(group, "fg#") == "#b477cf",
    token[2] .. " actually renders purple in Rust"
  )
end
local source = require("vsvim.minimap.source_main")
local source_rows, palette
source.rows(vim.api.nvim_get_current_buf(), 1, 4, function(r, p)
  source_rows, palette = r, p
end)
assert(
  vim.wait(5000, function()
    return source_rows ~= nil
  end),
  "minimap source completes"
)
for _, token in ipairs({ { 1, "const" }, { 2, "fn" }, { 3, "let" }, { 4, "for" } }) do
  local first = assert(rows[token[1]]:find(token[2], 1, true)) - 1
  local matched = false
  for _, span in ipairs(source_rows[token[1]].spans) do
    if span[1] <= first and span[2] > first and palette[span[3] + 1] == "#b477cf" then
      matched = true
    end
  end
  assert(matched, token[2] .. " is purple in minimap source too")
end
vim.cmd("colorscheme vsvim-jb-dark")
assert(foreground("Keyword") == 0xcf8e6d, "original JB theme remains selectable")
vim.cmd("colorscheme vsvim-one-dark")
assert(foreground("Keyword") == 0xb477cf, "One Dark reload restores palette")
print("One Dark syntax: PASS")
