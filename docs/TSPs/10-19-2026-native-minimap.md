# Native Minimap Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:subagent-driven-development (recommended) or dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved native tiny-code minimap, real Git change bands,
word-occurrence boxes, selected rows, and selection-preserving navigation.

**Architecture:** VSVim owns editor meaning behind a provider interface;
sprite.nvim coalesces and transports that provider's updates; Sprite validates
and renders a negotiated grid extension. Source transactions and lightweight
state messages are separate, with explicit target/generation identity.

**Tech Stack:** Neovim 0.13 Lua, existing sprite.nvim RPC/Surface transport,
Rust and vendored GPUI 0.2.2 in Sprite. No new runtime or minimap plugin.

## Global Constraints

- "Keep prototype artifacts available from issue #8."
- "No plugin installation step is exposed to the user."
- "No embedded web view or copied VS Code/Zed rendering subsystem."
- "Use a 160-logical-pixel strip when space permits. Hide it below an editor width of 480 logical pixels, releasing its space automatically."
- "Compare the current in-memory buffer against its file at Git `HEAD`."
- "Minimap navigation preserves the selection and its anchor; it must not replace the user's selected text or edit the buffer."
- "Build a test Sprite application without replacing a running user's editor."
- "Publishing or installation follows the user's instructions."

The approved PRD is `docs/PRDs/10-19-2026-native-minimap.md`. The normative
wire contract is `docs/protocols/native-minimap-v1.md`. This plan's tasks implement
that contract exactly; fixture tests are the compatibility gate. The actual
implementation is not present yet.

## Working directories and version evidence

| Repository | Checkout | Inspected revision |
| --- | --- | --- |
| VSVim | `/Users/davidlee/Projects/VSVim` | `82f75de` plus this design hardening |
| sprite.nvim | `/Users/davidlee/Projects/sprite.nvim` | `21c96d6e15cfea741eba145284461b7256d7d159` |
| Sprite | `/Users/davidlee/Projects/Sprite` | `b8d3a2b` on `fix/native-editor-copy` |

Keep the user's current checkouts; use feature branches rather than recreating
recently removed worktrees. Before changing either dependency, fetch its default
branch, inspect status and ancestry, and create `feat/native-minimap` from the
updated default. Never reset a dirty checkout. Keep the earlier copy fix if it
has not merged: its grid-only behavior is a regression requirement.

Use the actual binary, not the `nvim-nightly` launcher wrapper:

```sh
export VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim
```

It reported `NVIM v0.13.0-dev-761+g0639f6e41a`. Installed runtime
`share/nvim/runtime/doc/vimfn.txt` documents `getregion/getregionpos`, including
exclusive selection and byte/virtual columns. Its `lua/vim/treesitter.lua`
implements `get_captures_at_pos`; that method returns no captures without an
active highlighter, so a fallback is mandatory. Use parsed query captures by
range, not repeated per-byte calls that re-run captures for every character.
Official references: https://neovim.io/doc/user/vimfn/#getregionpos(),
https://neovim.io/doc/user/api/#nvim_buf_attach(), and
https://neovim.io/doc/user/treesitter/ . Verify against this installed runtime.

Sprite's root `Cargo.toml` declares Rust 1.97.1 and GPUI =0.2.2, with a local
`vendor/gpui` patch; `Cargo.lock` resolves GPUI 0.2.2. The compatible local
precedent is `grid_paint.rs`: `shape_line(SharedString, Pixels, &[TextRun], None)`
and `ShapedLine::paint`. Its cell-sized cache must not be expanded to hold an
entire miniature document; the new renderer caches only its visible source rows.

## File ownership

| Repository | Files | Responsibility |
| --- | --- | --- |
| VSVim | `lua/vsvim/minimap.lua` | setup, active target, generation and provider composition |
| VSVim | `lua/vsvim/minimap/source.lua` | clipped text and resolved syntax color spans |
| VSVim | `lua/vsvim/minimap/git.lua` | async HEAD baseline and buffer diff |
| VSVim | `lua/vsvim/minimap/selection.lua` | live/preserved selection, exact occurrences, input preparation |
| sprite.nvim | `lua/sprite/minimap.lua` | provider registration, pull queue, typed dispatch and input wrapper |
| sprite.nvim | `lua/sprite/adapter.lua` | negotiation, notifications, sequential forwarding |
| Sprite | `crates/sprite-app/src/surface/minimap.rs` | protocol parsing and committed/staged model |
| Sprite | `crates/sprite-app/src/terminal_view/native_minimap.rs` | pure geometry and native rendering/input |
| Sprite | existing `surface.rs`, `surface/grid.rs`, `surface/wire.rs`, `terminal_view.rs`, `terminal_view/surfaces.rs` | extension registration and grid layout |

No general purpose event framework, secondary socket, or parallel language
highlighter. Selection and source modules hide their real complexity behind the
provider; bridge code does not know how Git, words, or Vim selections work.

## Shared provider interface

```lua
-- sprite.minimap, called inside the embedded editor:
M.setup(provider)                  -- register one provider; nil unregisters
M.attach(channel)                  -- RPC channel for dirty notifications
M.changed()                        -- coalesced sprite_minimap_changed notify
M.pull()                           -- next wire op or vim.NIL; max 256 KiB chunk
M.dispatch(event)                  -- boolean; validate identities before action
M.input(method, args, event)       -- prepare input, then original API call

-- VSVim provider registered by vsvim.minimap.setup():
provider.next()                    -- next source/state/hide op without revision
provider.dispatch(event)           -- reveal/scroll, editor meaning only
provider.before_input(event)       -- restore or clear preserved selection
provider.stop()                    -- cancel pending work and clear highlights
```

The bridge supplies connection-global revisions, including hide. Provider
operations contain the target and generation required by the contract. Pull
returns nil while scheduled work is incomplete and changed() notifies when it
is ready. A nil response ends that drain, preventing a busy loop.

`M.input` accepts only the existing editing Input.call methods: nvim_input,
nvim_input_mouse, and nvim_paste. Do not expose arbitrary
`vim.api[untrusted_method]` evaluation. Neovim exposes nvim_ui_try_resize and
nvim_ui_set_focus only over RPC, so resize/focus/blur retain the adapter's direct
RPC route and leave preserved selection alone. Unknown wrapper calls return false.

---

### Task 1: Validated native model and shared fixture

**Blocked by:** None.

**Files:** Create Sprite `src/surface/minimap.rs` and
`tests/fixtures/minimap-v1.json` under `crates/sprite-app/`; modify
`src/surface.rs`, `src/surface/grid.rs`, `src/surface/wire.rs` in that crate.
Copy the identical fixture to sprite.nvim `tests/fixtures/minimap-v1.json`.

**Interfaces:** Consumes the normative contract. Produces `Minimap::default()`,
`Minimap::parse(&serde_json::Value) -> Result<MinimapOp, Refusal>`,
`Minimap::apply(&mut self, MinimapOp) -> Result<(), Refusal>`, and
`Minimap::visible_width(&self, surface_width: f32) -> f32`. Fields are private;
provide read-only `document() -> Option<&Document>` and `state() -> Option<&State>`.
`Document` exposes target, generation, total, palette, background and rows;
`State` exposes revision, viewport, selection, occurrences, changes and word.

- [ ] **Step 1: Add fixture-based regression checks.** Load the fixture using
  `serde_json::from_str(include_str!("../../tests/fixtures/minimap-v1.json"))`.
  Apply begin/lines/commit/state to a fresh model. Assert 3 committed lines,
  two change bands, occurrence rows `[1,3]`, selection `[2,3]`. Clone the model
  before each invalid op and assert refusal preserves it, including revision.
  Derive PartialEq on model values so the check compares all state, not a
  handful of conveniently selected fields.

```rust
let before = model.clone();
let result = Minimap::parse(&invalid).and_then(|op| model.apply(op));
assert!(result.is_err());
assert_eq!(model, before);
```

- [ ] **Step 2: Run the failure.** From Sprite:
  `cargo test -p sprite-app --lib surface::minimap::tests`.
  The newly registered tests must fail because the model is absent before
  implementation, not because an unrelated dependency cannot build.
- [ ] **Step 3: Implement the typed reducer.** Decode a tagged enum for
  begin/lines/commit/state/hide, validate all safe integers before conversions,
  account bytes before reserving storage, and stage inserts without cloning
  committed text. Commit replaces the deleted row slice and swaps state only
  after total/count validation. Reject stale op revisions without advancing
  the watermark. Register `Op::Minimap` and parse/apply it through existing grid
  operations. Existing apply_all is sequential across operations, so transaction
  atomicity belongs inside Minimap, not to the enclosing Surface batch.

```rust
pub fn visible_width(&self, surface_width: f32) -> f32 {
    if self.document().is_some() && surface_width >= 480.0 { 160.0 } else { 0.0 }
}
```

- [ ] **Step 4: Run model plus grid/wire tests.** Execute
  `cargo test -p sprite-app --lib surface::` and `cargo fmt --all --check`.
  Include splices at start/end, zero inserted lines, malformed UTF-8 span
  endpoints, canceled transactions, resource caps and state after hide.
  Advertise grid-minimap-v1 only once the renderer in Task 5 exists; do not
  claim support merely because the parser can accept the messages.
- [ ] **Step 5: Commit.**
  `git add crates/sprite-app; git commit -m 'feat: validate transactional minimap state'`.

### Task 2: Real file content, colors and Git changes

**Blocked by:** None; consumes the documented contract rather than host code.

**Files:** Create VSVim `lua/vsvim/minimap.lua`,
`lua/vsvim/minimap/source.lua`, `lua/vsvim/minimap/git.lua`,
`tests/minimap_source.lua`, `tests/minimap_git.py`.

**Interfaces:** `source.rows(buffer, first, last, done)` schedules bounded
row extraction and invokes `done(rows,palette)` only for its still-current
job; returns `cancel()`. Rows use wire text/spans. `git.watch(buffer,on_change)`
returns `stop()`; on_change receives `{changes=groups, head=sha}` or
`{changes={}, error=message}`. `minimap.setup()` registers the shared provider;
`minimap.provider()` returns it for integration tests. Do not call setup from
init until Task 6.

- [ ] **Step 1: Write isolated real-buffer fixtures.** In minimap_source.lua,
  prepend cwd to runtimepath; create a buffer with tabs, Unicode, blank lines,
  Lua strings/comments, and a 10,000-character line. Enable syntax or a known
  installed parser. Extract offscreen rows and assert complete UTF-8, expanded
  tabs, bounded bytes, uncolored fallback and expected String color. Fail on
  missing module. Execute:
  `/Users/davidlee/.local/nvim-nightly/bin/nvim --clean --headless -l tests/minimap_source.lua`.
- [ ] **Step 2: Add Git integration fixtures before implementation.** Use
  Python unittest/tempfile/subprocess and pynvim, with a fresh temporary Git
  repository. Set test identity via `git -c user.name=Test -c user.email=test@example.invalid commit`.
  Commit `one\ntwo\nthree\n`, change buffer line two to TWO, save, stage and
  commit in turn. The required groups before commit are:

```python
self.assertEqual(groups, [{'start': 2, 'end': 2, 'kind': 'modified'}])
```

  Saving and staging keep that group; committing clears it. Additional tests
  delete first/last/all lines, create an untracked file, open a non-Git file,
  rename to a Unicode/metacharacter path, and switch buffers during a Git read.
  Run `uv run --with pynvim python tests/minimap_git.py`; observe missing module
  or unmet output assertions before implementing.
- [ ] **Step 3: Implement source extraction.** Schedule batches up to 256 rows
  and 4 ms, whichever comes first. Read Tree-sitter query ranges once per batch,
  resolve captures by priority and highlight links, and merge equal-color runs.
  Use synID/synIDtrans fallback in the target window context. Build a source-byte
  to expanded-display-byte mapping while clipping; translate spans through it,
  never reuse original tab offsets in expanded text. Palette overflow chooses
  nearest existing RGB color without allocating an unbounded palette. Changed
  theme/display options force a full generation. Do not run per-byte
  get_captures_at_pos across a 100,000-line file.
- [ ] **Step 4: Implement async HEAD comparison.** Invoke `vim.system` with
  argument arrays for rev-parse and show, use a repository-relative POSIX path,
  and distinguish missing HEAD entry from process/read errors. Bound Git output
  and cancel obsolete jobs. Compare using:

```lua
local hunks = vim.diff(baseline, current, { result_type = 'indices' })
local groups = {}
for _, h in ipairs(hunks) do
  local _, removed, start, added = unpack(h)
  local kind = removed == 0 and 'added' or added == 0 and 'deleted' or 'modified'
  local first = math.max(1, math.min(total, added == 0 and start + 1 or start))
  groups[#groups + 1] = { start = first,
    ['end'] = math.min(total, first + math.max(1, added) - 1), kind = kind }
end
```

  Here total is the current buffer's line count (at least one). Test deletion
  index semantics against actual vim.diff outputs before accepting the helper.
  Watch the resolved git-dir including worktrees, packed refs, symbolic branch
  targets and HEAD changes; coalesce checks, resolve new targets after events,
  and refresh on FocusGained/BufEnter/BufWritePost. Event watchers are backed by
  a 2-second HEAD check only while the feature has a live target; do not poll
  file contents or run Git on every cursor event.
- [ ] **Step 5: Compose target generations and edit transactions.** Use
  nvim_buf_attach on_lines to accumulate the smallest encompassing dirty range;
  apply edit coordinates against the latest buffer, with a full replacement
  when a pending transaction cannot be rebased. Cache committed expanded rows
  and emit a splice only after recolored rows are ready. Cancel before switching
  identities. If a splice introduces a color absent from the committed palette, send a
  full replacement with a new palette instead. Source generation includes
  changedtick plus theme/display epoch;
  wire generation is a monotonic counter, not changedtick alone. Keep native
  source unavailable until supported provider setup; no normal-terminal work.
- [ ] **Step 6: Run both source/Git test commands and commit.**
  `git add lua/vsvim/minimap* tests/minimap*; git commit -m 'feat: collect minimap source and HEAD changes'`.

### Task 3: Live and preserved selection semantics

**Blocked by:** Task 2.

**Files:** Create VSVim `lua/vsvim/minimap/selection.lua`,
`tests/minimap_selection_rpc.py`; modify `lua/vsvim/minimap.lua`.

**Interfaces:** `selection.capture(window) -> selection_or_nil`,
`selection.browse(window, action)`, `selection.before_input(event)`,
`selection.state(window) -> {selection,occurrences,word}`,
`selection.clear()`. State includes buffer, window, changedtick, anchor, cursor,
mode and selected row segments; wire state exposes only rows/word. `action` has
validated reveal/scroll fields from the shared contract.

- [ ] **Step 1: Write the actual input/selection regression.** Start clean
  embedded Neovim with a UI (100x30), load provider modules from checkout and
  create 1,000 lines with repeated literal words. Use nvim_input_mouse's
  double-click modifier `2` in a real RPC test; verify mode/selected text,
  matching rows, and main-editor highlights. For preserved browsing:

```python
self.nvim.input('gg0v3l')
self.wait_for(lambda: self.nvim.funcs.mode() == 'v')
self.nvim.exec_lua("require('vsvim.minimap.selection').browse(0, {action='scroll', topline=500})")
self.assertGreaterEqual(self.nvim.funcs.line('w0'), 490)
self.assertEqual(self.nvim.current.buffer[:], original)
self.nvim.exec_lua("require('vsvim.minimap.selection').before_input({type='input',key='y'})")
self.nvim.input('y')
self.wait_for(lambda: self.nvim.funcs.mode() == 'n')
self.assertEqual(self.nvim.funcs.getreg('"'), 'word')
```

  Put `word` at the beginning of the first test line. wait_for is a test-local
  deadline helper, as in tests/editing_rpc.py, not an arbitrary fixed sleep.
  Run `uv run --with pynvim python tests/minimap_selection_rpc.py` and confirm
  scrolling/selection assertions fail before implementing.
- [ ] **Step 2: Implement real selection capture.** Use getregionpos with
  eol=true in the target window and the actual Visual/Select mode. Convert
  Select modes s/S/Ctrl-S to v/V/Ctrl-V for region calculation while retaining
  original mode for restore. Respect exclusive endpoints and empty rows.
  Preserve anchor and cursor orientation separately from sorted drawing rows.
  Avoid allocating one persistent extmark per row of a huge selection; use
  a decoration provider to draw its visible text segments.
- [ ] **Step 3: Implement whole-word occurrences.** Only an active one-word
  characterwise selection activates matching. Compare selected text against
  the window's keyword rules; scan literal case-sensitive matches, including
  offscreen comments/strings, in scheduled batches. Cancel on another selection,
  buffer edit, OptionSet iskeyword, mode clear, file switch or disable. One
  grey wire row per matching line; main-editor decorations use exact byte spans.
  Do not set the search register or change ignorecase/smartcase/hlsearch.
- [ ] **Step 4: Implement preserved browsing.** Capture once; leave Visual or
  Select mode via nonremapped Escape, scroll by moving the temporary cursor and
  view together, and keep saved selection data/decorations. Before keyboard or
  paste, restore the target window, original anchor/cursor positions and mode,
  then deliver the original input. Escape clears instead; a mouse press begins
  a new normal selection; ordinary mouse hover, focus, resize and minimap
  browsing leave it intact. New edits invalidate saved coordinates. Restoration
  is synchronous inside the editor RPC handler, preceding the original API call.
- [ ] **Step 5: Expand and pass RPC checks.** Cover reversed selections,
  character/line/block, inclusive/exclusive, tabs/virtual columns, Unicode,
  offscreen word matches, y/d/c and Cmd-C/X/V, Escape, typing, main-editor click,
  file switch and another process editing the buffer. Assert no register,
  search or undo changes from browsing itself. Run existing editing_rpc.py with
  VSVIM_NVIM set, plus the new selection suite. Commit:
  `git add lua/vsvim/minimap* tests/minimap_selection_rpc.py; git commit -m 'feat: preserve selections during minimap browsing'`.

### Task 4: Negotiated bridge with ordered input

**Blocked by:** Tasks 1–3 define its model, fixture and provider behavior.

**Files:** sprite.nvim `lua/sprite/minimap.lua`, `lua/sprite/adapter.lua`,
`tests/minimap_spec.lua`, `tests/native_minimap_spec.lua`,
`tests/fixtures/minimap-v1.json`, README.md.

**Interfaces:** Produces all sprite.minimap methods in Shared provider interface.
Consumes provider.next/dispatch/before_input/stop and typed Surface messages.

- [ ] **Step 1: Add bridge checks through public methods.** Register a provider
  whose next() yields fixture messages then nil; pull them and assert revisions
  increase, source identities survive, and an absent provider returns nil without starting work.
  Verify stale actions are rejected before provider.dispatch is called.

```lua
local received = 0
bridge.setup({ next = function() return nil end,
  dispatch = function() received = received + 1 end,
  before_input = function() end, stop = function() end })
T.eq(bridge.pull(), vim.NIL)
T.eq(bridge.dispatch({type='minimap_action', target='old', generation=1,
  revision=1, action='reveal', line=1}), false)
T.eq(received, 0)
```

  Run `/Users/davidlee/.local/nvim-nightly/bin/nvim -l tests/run.lua` and
  observe missing bridge failure.
- [ ] **Step 2: Implement registration, coalescing and input allowlist.**
  Reuse tabs' scheduled rpcnotify pattern, but not tab-specific dirty state.
  A replacement provider stops the previous one and emits hide. Input wrapper:

```lua
local allowed = { nvim_input=true, nvim_input_mouse=true, nvim_paste=true }
function M.input(method, args, event)
  if not allowed[method] then return false end
  if provider and provider.before_input then provider.before_input(event) end
  return vim.api[method](unpack(args))
end
```

  Guard provider failures: clear/hide minimap state, log the exception and still
  deliver ordinary input once. Never duplicate paste after a callback exception.
- [ ] **Step 3: Wire adapter negotiation and drain.** Add native_minimap flag
  from opened.features. Obtain the editor channel once for tabs and minimap;
  each feature can attach/fail independently. On sprite_minimap_changed, request
  pull once; forward result then request the next using a scheduled continuation,
  yielding between chunks. Coalesce notifications while pending. Ignore any
  response after disable/disconnect. Route minimap_action to dispatch through
  the same ordered editor RPC stream. With the capability present, route editing
  input, mouse, and paste through M.input in one RPC notification rather than a
  callback followed by a second input call that could reorder keys:

```lua
rpc:notify('nvim_exec_lua', {
  "return require('sprite.minimap').input(...)", {call.method, call.args, event}
})
```

  Without capability use the original rpc:notify(call.method,call.args) path.
  A host refusal hides only minimap state and invalidates the source transaction;
  it must not kill the editor or disable native tabs.
- [ ] **Step 4: Run fake-host and real-adapter checks.** Exercise new/old hosts,
  absent provider, provider failure, source chunk bursts interleaved with typed
  text, queued stale response, cancellation, and one copy/paste delivery. Assert
  typing remains ordered while draining 100,000 lines; viewport changes produce
  no source chunks. Run the full tests/run.lua suite; retain all existing checks.
- [ ] **Step 5: Commit.**
  `git add lua/sprite tests README.md; git commit -m 'feat: bridge negotiated minimap state and actions'`.

### Task 5: Native minimap drawing and navigation

**Blocked by:** Task 1; Task 4 needed for live editor acceptance.

**Files:** Sprite `crates/sprite-app/src/terminal_view/native_minimap.rs`,
`terminal_view.rs`, `terminal_view/surfaces.rs`, `surface/wire.rs`.

**Interfaces:** `NativeMinimap::default()`,
`NativeMinimap::render(&mut self, model: &Minimap, surface: SurfaceId,
size: Size<Pixels>, cx: &mut Context<TerminalView>) -> AnyElement`.
Pure internal `MapGeometry::new(total,topline,visible,height)` returns offset,
thumb_top,thumb_height and `line_at(y)`, `topline_at_thumb(y,grab_offset)`.
Native events use the existing connection for this Surface and the contract's
minimap_action payloads. Keep geometry and painting in the same focused module.

- [ ] **Step 1: Add geometry/property regressions.** For N in
  `[1,2,1000,10000,100000]`, heights `[1,120,600,980]`, and visible row counts
  `[1,30,80]`, assert finite clamped geometry, monotonic click/drag mapping,
  and both file endpoints reachable. Exact endpoint assertions:

```rust
assert_eq!(g.topline_at_thumb(0.0, 0.0), 1);
assert_eq!(g.topline_at_thumb(g.height, 0.0), total.saturating_sub(visible).max(0) + 1);
```

  Clamp visible to total inside the constructor. Test hunk boundaries,
  selected rows outside the map window, and short-file blank tail clicks.
  Run `cargo test -p sprite-app --lib native_minimap` before implementing.
- [ ] **Step 2: Implement contract geometry and native painter.** Use one GPUI
  Element/canvas covering the strip, not one layout node per character. Draw
  colors with alpha in the approved order; miniature TextRuns use span byte
  lengths, fill ordinary text gaps and omit terminal cursor/decorations.
  Shape using the existing text system at about 2.5 px with 3 px line height.
  Cache only visible shaped rows keyed by target/generation/row/font/scale;
  bound cache to 2,048 rows and clear changed keys on splice/theme/scale change.
  Paint source rows within ContentMask and keep their fixed display-cell
  positions. Verify the vendored text rasterizer actually supports this size
  in native screenshots before accepting the appearance.
- [ ] **Step 3: Integrate width and pointer routing.** In surface_element,
  subtract model.visible_width(surface width) from grid_size.width before
  cells_that_fit and resize event calculation. Keep native tabs spanning the
  entire surface; place grid and strip side by side below them. Reuse the
  existing grid_top offset for IME/mouse origins, with no x shift to the grid.
  Track strip pointer capture so dragging continues outside its bounds; stop
  mouse and wheel propagation. On click reveal hunk start or clicked source
  line. On drag emit scroll through full-file thumb geometry. Coalesce wheel/
  drag to a frame and flush pointerup. Release capture on disable/disconnect.
- [ ] **Step 4: Add host integration checks.** Cover 479/480-pixel threshold,
  tabs + minimap resize, unchanged rows after toggling, pointer mapping beside
  the strip, IME positioning, hover info, terminal/list/element isolation and
  exactly one event per click. Test state-only revisions while dragging and
  reject pointer input during source transaction staging. Then advertise
  grid-minimap-v1 in both opened and capabilities, updating existing wire tests.
- [ ] **Step 5: Verify and commit.** Run
  `cargo test -p sprite-app --lib terminal_view::`,
  `cargo test -p sprite-app --lib surface::`, `cargo fmt --all --check`.
  `git add crates/sprite-app; git commit -m 'feat: render interactive native code minimap'`.

### Task 6: VSVim setup, compatibility and release pins

**Blocked by:** Tasks 2–5 verified together.

**Files:** VSVim `lua/vsvim/init.lua`, `lua/vsvim/minimap.lua`, README.md,
`tests/minimap_integration_rpc.py`, `tests/integration_test.py`.

**Interfaces:** Public command VSVimMinimapToggle; global setting
vsvim_minimap=false. Existing plugin/setup and launch behavior remain the seam.

- [ ] **Step 1: Add integration cases.** Start VSVim with supported and old
  fake hosts, normal headless/terminal runs, user.lua disabling the setting,
  and an unsupported buffer. Assert the command exists but unsupported hosts
  emit no messages, reserve no width and run no source/Git jobs. With support,
  edit a file and assert real text, color spans, live diff and selection layers.
  Disable must send hide and cancel jobs; enable must build current state.
- [ ] **Step 2: Hook setup and configuration.** Load the VSVim minimap module
  during setup after the plugin is available; defer provider activation until
  native capability attachment. Read the user's setting after user.lua, or
  subscribe to the final configuration explicitly, so disabling does not start
  unnecessary work. Command changes the global and registers/unregisters the
  provider. Retain the last valid file during native sidebar focus, but never
  show its overlays as though they belong to a different focused file window.
- [ ] **Step 3: Verify using local dependency overrides.** Use a temporary
  XDG data directory or test-only package.path injection for the local adapter;
  never overwrite installed dependencies to make tests pass. Run integration,
  editing, source/Git and selection tests and the existing unittest suite.
  Confirm legacy u/y/d/p and Cmd shortcuts still work through the native bridge.
- [ ] **Step 4: Publish dependencies only when authorized.** Record immutable
  verified sprite.nvim and Sprite SHAs. Update the adapter pin in init.lua only
  to an accessible published commit; do not put an unpushed SHA into a user
  installation path. If publication is not authorized, retain local overrides
  and explicitly record that release pinning is outstanding.
- [ ] **Step 5: Commit integration and document tested versions.** Include
  enabling/toggling, HEAD baseline semantics, preserved-selection behavior,
  supported host capability, oversized-file behavior and the need for a new
  Sprite process after a host upgrade. Commit the tested integration separately.

### Task 7: Native evidence, performance and final review

**Blocked by:** Tasks 1–6; publication-dependent pinning may remain outstanding
only if the user has not authorized publishing.

**Files:** VSVim `tests/minimap_benchmark.py`,
`docs/execution/10-19-2026-native-minimap.md` and native screenshot artifacts.

**Interfaces:** Benchmark prints JSON per fixture size and records exact source/
host revisions, sample count, display scale and whether caches are warm.

- [ ] **Step 1: Establish reproducible performance checks.** Generate 1,000,
  10,000, and 100,000-line files with repeated syntax and Git changes. Measure
  initial first painted content, complete initial sync, source extraction,
  edit-to-updated-band, scroll/state messages, bytes and peak host/editor memory.
  Run at least 30 warm scroll samples. Test at 1x and 2x where available.
- [ ] **Step 2: Apply explicit acceptance budgets.** Targets on this development
  Mac: scheduled editor work slices <=4 ms, source chunks <=256 KiB, no source
  messages for pure scroll, warm native minimap paint p95 <=8 ms, and scroll
  input-to-next-frame p95 <=33 ms. Initial full sync targets <=0.5/2/10 seconds
  for 1k/10k/100k source lines, while typing remains responsive; edit overlays
  target <=250 ms for 1k/10k and <=1 second for 100k. These are acceptance
  targets, not measured native results. Record cold and warm values separately;
  a missed target requires profiling and a fix or explicit user-approved scope
  change, not a passing label.
- [ ] **Step 3: Capture actual native behavior.** Build a test app with the
  repo's existing build procedure. Open a separate test window, preserving
  running user buffers. Capture code/change bands, grey occurrences and blue
  selected rows, including overlaps, long-file drag to both ends, narrow pane,
  theme/scale change and selected-text copy after scrolling away. If physical
  IME or another platform cannot be exercised, report that limitation explicitly.
- [ ] **Step 4: Run final focused suites and independent review.** Re-run only
  suites affected by the final changes, record commands/results, and use
  requesting-code-review before integration. If independent review cannot run,
  disclose self-review. No feature-complete claim before native evidence and
  correctness checks pass. Do not install into /Applications or merge branches
  without user authorization.
- [ ] **Step 5: Commit evidence and hand off the reviewable changes.** Record
  remaining publication/pinning work, exact commits, test totals and material
  limitations. Close issue #8 only once all acceptance requirements are met.

## Planning evidence and hardening

On 2026-10-19, clean embedded Neovim with a 100x30 UI retained a Visual cursor
on row 1 while winrestview requested topline 500; after redraw topline was 1.
The user chose preserved selection during minimap browsing. Task 3 and the
ordered-input path in Task 4 address that observed constraint.

A 15-sample source transfer probe and 30-sample viewport probe on the installed
Neovim measured these medians. Source lines were `local item_i = compute(i)`;
there was no syntax extraction, Git, Surface transport or native painting.

| Lines | All-line RPC median | View RPC median | Source JSON bytes |
| --- | --- | --- | --- |
| 1,000 | 0.22 ms | 0.05 ms | 32,780 |
| 10,000 | 1.82 ms | 0.05 ms | 347,780 |
| 100,000 | 19.97 ms | 0.05 ms | 3,677,780 |

Hardening findings resolved in the plan:

- Source data cannot come solely from ext_linegrid: Task 2 collects offscreen
  text and syntax; Task 4 transports it separately.
- Selection-preserving navigation cannot rely on topline alone: Tasks 3–4
  explicitly restore selection before keyboard input and preserve event order.
- State-only revisions must not cancel a drag: actions validate a revision
  interval within the same committed content generation.
- A chunk failure must not half-replace code: Task 1 stages and atomically commits.
- Long-file miniature coordinates differ from full-file scrolling: Task 5
  tests separate click mapping and full-file thumb mapping.
- Tab expansion changes byte positions: Task 2 remaps highlight spans.
- Default user configuration loads late: Task 6 activates after that setting.
- Published pins must exist remotely: Task 6 separates local verification from
  authorized publication; no invented dependency SHA enters the distro.

## Coverage and execution ledger

PRD appearance/layers: Tasks 1,2,5,7. Word/selection: Tasks 2,3,4,7.
Navigation/long files: Tasks 3,4,5,7. Git baseline: Task 2.
Negotiation/compatibility: Tasks 1,4,6. Resource/lifecycle limits: Tasks 1–6.
Native geometry/IME and performance: Tasks 5,7. Delivery: Tasks 6,7.

- [x] User approved the PRD and proposed defaults.
- [x] User approved preserved selection during browsing after runtime probe.
- [x] Protocol, task interfaces, failure paths and PRD coverage self-reviewed.
- [ ] Choose execution approach, then record dependency base SHAs and baseline checks.
- [ ] Tasks 1–7 implemented and verified; native screenshots captured.
