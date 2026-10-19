# Keep whole-file parsing and Git comparison outside the editor event loop

The native minimap remains owned by VSVim. An owned, persistent Neovim child
mirrors the active buffer, extracts Tree-sitter capture ranges and names, and
compares its mirror against Git HEAD. The editor resolves its actual highlight
colors and Vim syntax fallback, expands tabs, clips display text and stages the
existing minimap transactions. Neither the Surface protocol nor preserved
selection behavior changes.

A 100,000-line diagnostic measured 9.4 seconds of extraction and a 221.9 ms
scheduled editor callback before transport. Moving the timer did not bound
Tree-sitter parsing, injection queries, predicate evaluation or garbage
collection. The installed asynchronous parser also produced a 126 ms callback.
A child process isolates work that a Lua timer cannot preempt. A real child
spike measured a 115 ms ordinary edit and foreground transfer callbacks below
0.07 ms; native end-to-end results belong in the execution report.

The child uses the same executable and runtimepath, starts without user init or
plugins, and disables swap, undo files and shada. Snapshot reads are bounded by
byte offsets, RPC text fragments by 128 KiB, and capture replies by a conservative
128 KiB bound. It receives complete source text, including long-line suffixes;
only the editor's display representation is clipped. The child stops on hide,
toggle, target change and shutdown. It mirrors filename and end-of-line metadata
on save, rename and option changes, including saves without text edits.

The query observer starts before plugin and user configuration. It records
serializable `query.set` text and language registrations. Resolved query text
gets a leading blank line in the child so inheritance modelines are not applied
a second time. It preserves public query return objects and memoizer methods.
The installed LanguageTree and highlighter are audited readers: their public
query calls are trusted by their exact VIMRUNTIME source paths. This is a
compatibility boundary, not a security boundary. The supported public workflow
of retrieving a Query and calling `disable_capture` or `disable_pattern` switches
to the exact editor implementation before mutation. Preloaded queries, external
query get/parse calls, custom Lua predicates/directives, replaced query APIs,
oversized configuration/captures and worker failures also choose that path.
No private Lua upvalues, userdata proxies or debug hooks are used.

Changed-tree ranges plus the explicit text edit bound ordinary incremental
extraction. With parse errors, missing parsers, or effective Vim syntax rules
that differ from the runtime-only child, extraction conservatively covers the
whole file. The comparison includes syntax synchronization rules. This protects
multiline delimiters and custom syntax lookahead that can change earlier rows.
The main editor's colors and syntax IDs remain authoritative in every path.
Configured conservative paths retain correctness and can exceed the default
fixture performance targets; they must not be reported as measured passes.

The foreground scheduler yields after about 2 ms to leave headroom under the
4 ms acceptance target. Measurements include complete owned callbacks and RPC
receivers. Row chunk sizing uses an allocation-free upper bound for JSON escaping
instead of encoding every row in a single staging callback. Empty-syntax buffers
skip syntax ID calls only after querying the effective syntax definitions.

## Version and source evidence

- VSVim requires Neovim 0.13 in `init.lua`. Tested runtime:
  `v0.13.0-dev-761+g0639f6e41a`, LuaJIT `2.1.1774896198`.
- [Neovim Tree-sitter API](https://neovim.io/doc/user/treesitter/):
  `LanguageTree:parse`, `LanguageTree:register_cbs`, `Query:iter_captures`,
  `query.set`, and `language.register`.
- [Neovim buffer API](https://neovim.io/doc/user/api/): `nvim_buf_attach`,
  `nvim_buf_get_lines`, `nvim_buf_get_offset`, `nvim_create_autocmd` and job RPC.
- Installed source `runtime/lua/vim/treesitter/languagetree.lua`: parsing emits
  actual `tree_changes` through `on_changedtree`; invalidation also has a wider
  callback. Both are conservatively included. Runtime `highlighter.lua` and
  `languagetree.lua` contain no `disable_capture`/`disable_pattern` calls.
- Installed `query.lua` stores dynamic overrides privately. Query inspection was
  unchanged after disabling a capture and a pattern, so object ownership must
  trigger the exact path rather than guessing which compiled rules changed.
- A clean runtime probe showed buffer-local write autocmds disappearing on the
  first write to an existing pathname. Global autocmds filtered by buffer ID
  remain registered and are covered by first-save and rename tests.

Worker differential tests compare the real child against full editor extraction
for multiline changes, priority, theme, custom syntax, lookahead, long lines,
invalid UTF-8, serializable query overrides, mutation fallback and cancellation.
The exact commands and native measurements are recorded in
`docs/execution/10-19-2026-native-minimap.md`.
