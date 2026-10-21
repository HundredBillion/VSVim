# External-change Follow Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Follow external writes in the explorer project with commands and a clickable crosshair.

**Architecture:** A dedicated headless Neovim worker polls eligible files and retains bounded content snapshots. VSVim receives coalesced JSON notifications, suppresses its own saved content, and navigates safely. The existing Sprite footer transports a negotiated Follow button.

**Tech Stack:** Neovim 0.13 nightly, Lua/luv, Git, existing sprite.nvim RPC, Sprite Rust/GPUI.

## Global Constraints

- Follow starts off; external filesystem events do not prove agent identity.
- Keep unsaved buffers and never force reload, save, or discard undo.
- Commands: VSVimFollowToggle, VSVimFollowOn, VSVimFollowOff; normal key: Space-a-f.
- Keep the current statusline and provide terminal/older-host fallback.
- Poll every 300 ms in the worker; root/focus/navigation checks every 100 ms in VSVim.
- Maximum eligible text file 1 MiB, retained text 64 MiB, eligible file count 20,000; disable with a useful reason on aggregate limit or discovery failure.
- Exclude .git, node_modules, vendor, target, dist, build, .cache, __pycache__, .venv, venv, .worktrees, swap/temporary files, ignored files, binary files, and all symlinks. Git lists cached/untracked nonignored files; a bounded directory traversal covers projects without Git.
- At most one worker, one pending newest navigation, and one asynchronous target read; stopping or root changes invalidate callbacks.

## Sources and review decisions

Neovim runtime is v0.13.0-dev-761+g0639f6e41a. Consult official Lua/API reference and installed runtime doc/lua.txt and doc/api.txt for vim.system streaming callbacks, vim.diff indices, buffer call/nonforced edit with undoreload=-1 and eval_statusline highlights. GPUI is vendored in Sprite; use existing mouse handler and SVG asset patterns. The existing footer only transports grid cells and cannot draw the exact SVG or hit-test a new action, so negotiate grid-follow-v1. Older hosts keep the ordinary statusline control.

Design stress checks: ignore collapsed-tree visibility, own-save race uses content hashes rather than timing, native-sidebar focus is not stolen, initialization never navigates, atomic rename is treated as a new filesystem version, stale callbacks are rejected by generation. User already approved these behaviors in the PRD; no additional product decisions remain.

### Task 1: External-file observation and safe navigation

**Blocked by:** None

**Files:** Create lua/vsvim/follow_worker.lua, lua/vsvim/follow.lua, tests/follow.lua. Modify lua/vsvim/init.lua, lua/vsvim/appearance.lua, lua/vsvim/sidebar.lua, CONTEXT.md, README.md.

**Interfaces:** `require('vsvim.follow').setup()`, `.set_enabled(boolean)`, `.toggle()`, `.status()` returning `{enabled, ready, reason, root}`, `.set_root(path)`, `.native_snapshot()` returning `{enabled, ready, reason}`. Worker invoked with `nvim -l follow_worker.lua ROOT`; stdout NDJSON `{type='ready'}` or `{type='change', path, hash, line}` or `{type='error', message}`. EOF/exit disables Follow. Worker holds old content and computes last changed hunk with `vim.diff(old,new,{result_type='indices'})`; additions start at line one. Main validates root membership, file type/size/hash, and the target buffer before navigation.

- [x] Create tests/follow.lua, runnable with `/Users/davidlee/.local/nvim-nightly/bin/nvim --headless -u NONE -l tests/follow.lua`; first require the module and assert an external nested-file write opens at the changed line after ready. Observe failure before implementation.
- [x] Implement the worker and public module, then integrate commands, shortcut, own-write suppression and statusline click. Run the same test to green.
- [x] Add one behavior at a time: initialization, atomic replacement, own save followed immediately by external write, ignored/untracked/new/binary files, unsaved target, manual navigation, root changes and stop cleanup. Use real temporary files and processes, not worker mocks. Run the test after each case.
- [x] Run `./bin/vsvim --headless '+luafile tests/appearance.lua' +qa!` and `./bin/vsvim --headless '+luafile tests/smoke.lua' +qa!`. Commit code, behavioral tests and controls documentation.

### Task 2: Native crosshair and backward-compatible transport

**Blocked by:** 1

**Files:** sprite.nvim lua/sprite/statusline.lua, lua/sprite/adapter.lua, tests/native_footer_spec.lua, tests/follow_spec.lua. Sprite crates/sprite-app/src/surface/grid.rs, surface/wire.rs, terminal_view/surfaces.rs; assets/icons/follow.svg and attribution file. VSVim tests/follow_integration_rpc.py.

**Interfaces:** negotiated feature `grid-follow-v1`; footer optional `follow: {enabled: bool, ready: bool, reason: string}`; host emits `{type:'follow_action', action:'toggle'}`. Adapter validates capability/action then invokes the VSVim public toggle. Generic Neovim setups omit follow data. Existing grid-footer-v1 semantics remain valid.

- [x] Add a failing adapter contract test showing capability-aware snapshots and safe action dispatch. Extend the native footer fake-host test for an actual toggle round trip. Implement snapshot/adapter plumbing and rerun `/Users/davidlee/.local/nvim-nightly/bin/nvim --clean -l tests/run.lua`.
- [x] Add Rust parser tests for valid Follow state and malformed data. Implement optional footer state and negotiated capability; render the packaged Zed SVG in a fixed left footer area with on/off tint, tooltip and consumed mouse gesture. Run `cargo test -p sprite-app --lib follow` with the existing Sprite target directory.
- [x] Add a GPUI native window test clicking the actual button, asserting the host event, footer geometry and command overlay behavior. Run the targeted test and footer regression tests; build `cargo build -p sprite-app`.
- [x] Add VSVim RPC integration coverage using the existing fake Sprite Host: advertise both capabilities, receive Follow state, send toggle, perform external write, verify opened file/cursor. Repeat without grid-follow-v1 to verify fallback. Run `uv run --with pynvim python tests/follow_integration_rpc.py` with VSVIM_SPRITE_SOURCE pointing to the feature worktree.
- [x] Commit each repository's changes after its focused checks pass. Keep local source overrides for unpublished adapter revisions; do not pin an unavailable commit.

### Task 3: End-to-end verification and delivery

**Blocked by:** 1, 2

**Files:** docs/execution/external-change-follow.md and task ledger.

**Interfaces:** tested local VSVim launcher plus VSVIM_SPRITE_SOURCE override and built Sprite binary.

- [x] Run complete adapter tests and VSVim focused appearance, smoke, Follow and RPC tests. Run Sprite Follow/footer tests and cargo build. Record exact commands/results.
- [x] Run a real external tool write in a watched fixture and a large-project benchmark; record initialization and write-to-cursor latency and cleanup. Verify through the public command, actual worker, native transport and actual native hit-test.
- [x] Inspect all three repository diffs against the PRD and request independent whole-change review. Fix and reverify substantive findings.
- [x] Commit verification evidence and report feature branches, launch command, controls and any unverified acceptance checks. Do not merge or replace the running application.

## Verification and review

All tasks completed. See docs/execution/external-change-follow.md for actual
commands, test counts, build details, independent review, launch instructions,
and measured limits. Six regressions cover timestamp-preserving writes, large
buffer undo, viewport scrolling and read-completion races.
