# Markdown Preview Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:subagent-driven-development or dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render Markdown by default and toggle source in the original file buffer.

**Architecture:** VSVim owns source text and buffer mode, sprite.nvim transports
negotiated operations and ordered input, and Sprite owns native Markdown parsing,
layout, selection, scrolling and icons. The exact wire contract is
`docs/protocols/native-markdown-v1.md` and is part of each task's requirements.

**Tech Stack:** Neovim 0.13 Lua; sprite.nvim Lua RPC; Sprite Rust 1.97.1;
vendored GPUI 0.2.2; pulldown-cmark =0.13.0 with tables, strikethrough, task lists.

## Global Constraints

- Keep one original Neovim buffer and tab, preserving text, dirty flag, undo and source cursor.
- Use `grid-markdown-v1` only after host negotiation and provider registration.
- Source text limit: 2 MiB; visible windows: 16; host source cache: 16 documents/32 MiB.
- All operations have increasing safe-integer revisions; actions target state revision and live window/buffer/generation.
- Place file-code/eye at the right of native file tabs; preserve overflowing tabs.
- Render in the correct file window rectangle, preserving other windows, prompts, sidebars and footer.
- Unsupported/failed preview leaves editable source available.
- Source PRD: `docs/PRDs/10-19-2026-markdown-preview.md` (approved).
- Coordinated worktrees are `/Users/davidlee/Projects/{VSVim,sprite.nvim,Sprite}/.worktrees/markdown-preview`.

## Source and API evidence

Pulldown-cmark's versioned official documentation identifies `Parser::new_ext`
as the CommonMark event stream and requires Options flags for tables, task lists,
and strikethrough: https://docs.rs/pulldown-cmark/0.13.0/pulldown_cmark/ .
GPUI's versioned StyledText reference describes style runs and TextLayout for
pixel/index conversion: https://docs.rs/gpui/0.2.2/gpui/struct.StyledText.html .
Verify against vendored `vendor/gpui/src/elements/text.rs` (0.2.2), Cargo.lock,
and `cargo +1.97.1 test`; the local fork is the API actually compiled.
Existing native tabs/minimap show compatible layout, event and negotiation patterns.

### Task 1: Native host, document model, renderer and toolbar

**Blocked by:** None

**Files (Sprite worktree):**
- Create `crates/sprite-app/src/surface/markdown.rs` for validated wire state.
- Create `crates/sprite-app/src/terminal_view/native_markdown.rs` and focused
  children for parsed document, native layout/selection, caches and toolbar.
- Modify `crates/sprite-app/Cargo.toml`, `Cargo.lock`, `src/surface.rs`,
  `src/surface/grid.rs`, `src/surface/wire.rs`, `src/terminal_view.rs`,
  `src/terminal_view/surfaces.rs` and native tab rendering integration.
- Add licensed file-code and eye assets and third-party attribution.
- Tests live alongside public wire/render interfaces and native surface tests.

**Interfaces:**
- Consumes: exact Markdown operations/events in the protocol document.
- Produces: negotiated host support, Markdown model attached to GridSurface,
  per-window native preview and toolbar with revision-checked toggle/open actions.

- [ ] Write and run the first failing integration check through `GridSurface`:
  accept a document/state and confirm the target is previewing; reject stale
  revisions and malformed rectangles atomically. Use the protocol JSON examples
  as shared fixtures. Run `cargo test -p sprite-app --lib markdown` (initially fails).
- [ ] Implement wire validation, grid operation dispatch, and capability flags.
  Test document generations, cache bounds, source/hide transitions and bad IDs.
- [ ] Add parser, background generation-aware parse/cache and native renderer.
  Enable required pulldown options. Render headings, inline styles, links, lists,
  quotes, tables, code, task markers, rules and images. Resolve local resource
  paths from document path; render failed-image alternative text.
- [ ] Integrate bounded per-window scroll/selection state and exact pixel bounds
  from the provider rectangle. Consume preview mouse and copy input; preserve
  source, footer, prompts and other windows. Add file-code/eye action with
  tooltip and native hover behavior outside horizontally overflowing tabs.
- [ ] Add native GPUI interaction tests for toolbar toggle, isolated pointer
  events, source transition, scroll position, resizing and theme change. Verify
  copied preview text and clicked link destinations through real event paths.
- [ ] Run `CARGO_TARGET_DIR=/Users/davidlee/Projects/Sprite/target cargo test -p sprite-app --lib`
  and `cargo fmt --check`; record complete output and commit the task files.

### Task 2: Negotiated bridge and ordered preview input

**Blocked by:** None (same frozen protocol; integration waits for Task 1)

**Files (sprite.nvim worktree):**
- Create `lua/sprite/markdown.lua`, `tests/markdown_spec.lua`,
  `tests/native_markdown_spec.lua` and shared protocol fixtures.
- Modify `lua/sprite/adapter.lua`, `lua/sprite/input_bridge.lua`, and README.

**Interfaces:**
- Consumes: provider `{next, dispatch, before_input, attached, stop}` callbacks.
- Produces: `sprite.markdown.setup(provider)`, `.changed()`, `.attach(channel)`,
  `.pull()`, `.dispatch(event)`, `.before_input(event)`, `.available()`.
- `.pull()` returns next protocol op or `vim.NIL`, assigning its revision;
  `.dispatch()` accepts only current-state actions then delegates live validation.
- `.before_input()` returns false only when provider consumes the event.

- [ ] Add one failing bridge integration check registering a provider in a real
  embedded editor with fake host support, receiving initial document and state.
  Run `nvim-nightly -l tests/run.lua` and observe the missing API failure.
- [ ] Implement provider registration, detach/hide, action validation, revision
  assignment, coalesced invalidation and adapter feature negotiation. Keep one
  pull pending, handle errors with readable logs and detach safely.
- [ ] Extend ordered pre-input to invoke Markdown before minimap selection
  restoration, consuming false-returning events exactly once while releasing
  blocking command continuation keys. Gate only when Markdown was negotiated.
- [ ] Add tests for old hosts/missing provider, document/state ordering, stale
  actions, detach, blocked editing and paste, allowed save/command input, and
  coexistence with the existing minimap input gate. Run the whole Lua suite,
  record output, and commit this task's files.

### Task 3: VSVim buffer policy and source preservation

**Blocked by:** Task 2

**Files (VSVim worktree):**
- Create `lua/vsvim/markdown.lua` and `tests/markdown.lua`.
- Modify `lua/vsvim/init.lua`, `lua/vsvim/minimap.lua`, and README.

**Interfaces:**
- Consumes: Task 2 provider API and protocol contract.
- Produces: `vsvim.markdown.setup()`, `.toggle(buffer?)`, `.previewing(buffer?)`;
  registers `:VSVimMarkdownToggle` and the bridge provider.
- Provider `next()` yields changed document operations then state operations;
  `dispatch(event)` checks current live target, changedtick and view choice.

- [ ] Create a real Markdown buffer and assert default preview under negotiated
  support, then source-toggle/edit/preview with identical buffer ID, cursor,
  modified flag and undo history. Run the headless test and observe missing module.
- [ ] Implement mode policy, ordinary-window geometry, asynchronous 256-line
  text extraction, 2 MiB fallback, changedtick invalidation, and theme snapshots.
  Resolve new Markdown windows without adding buffers. Hide overlays during
  prompts/float popups. Preserve view choices and clean up disposed buffers.
- [ ] Implement input policy: consume edits/paste in preview; allow command
  entry, prompt continuation, save, Escape and established sidebar/window
  navigation. Handle local Markdown link opening through Neovim APIs.
- [ ] Verify unsaved edits, undo/redo, save/close, file switches, split windows,
  long text, unsupported hosts, stale extraction/actions and filetype changes.
  Run `./bin/vsvim --headless '+lua dofile("tests/markdown.lua")' '+qa!'` plus
  existing tab/editing/minimap checks. Commit source, tests and user docs.

### Task 4: Cross-repository acceptance and delivery

**Blocked by:** Tasks 1, 2, 3

**Files:** VSVim `tests/markdown_integration_rpc.py`, native fixture Markdown,
`docs/execution/10-19-2026-markdown-preview.md`; adapter pin in init.lua only
when its tested revision is published. Record linked branches when unpublished.

**Interfaces:**
- Consumes: all three worktrees' implementations and launchers.
- Produces: repeatable end-to-end evidence, runnable test host and clear run instructions.

- [ ] Launch VSVim through the new adapter with a fake host to verify one file
  buffer/tab, preview default, actual toggle event, unsaved edits, save, undo and
  source/preview transitions using real RPC and protocol messages.
- [ ] Build the native host and run the same fixture in a test application.
  Capture actual native preview/source screenshots and exercise mouse toggle,
  selection/copy, wheel, links, prompts and switching files.
- [ ] Measure cold render, edit update and warm scrolling for small, 10,000-line
  and oversized documents. Initial budget: source remains responsive throughout;
  warm scrolling does not parse or resend text; over-limit source remains editable.
- [ ] Run whole bridge suite, native library suite and targeted VSVim tests.
  Record exact outputs and limitations; perform independent whole-change review,
  fix substantive findings and repeat affected checks.
- [ ] Commit evidence and changes. Leave coordinated feature branches ready for
  review; document the exact host binary and adapter override used to run them.

## Execution decisions

The approved spec resolves the product behavior. Remaining parser/layout and
protocol choices are implementation details recorded above. Execute continuously
without another design or implementation approval gate. Review commits and
test evidence before reporting the feature complete.
