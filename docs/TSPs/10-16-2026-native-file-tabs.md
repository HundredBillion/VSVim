# Native File Tabs Technical Spec

> **For agentic workers:** Use dmi-superpowers:subagent-driven-development for independent host work and executing-plans for adapter/integration. Track verification below.

**Goal:** A 35-pixel native file-tab bar with SVG icons, close controls and horizontal overflow in Sprite, with VSVim terminal fallback.

**Architecture:** Extend the existing grid Surface with an optional native tab bar. Sprite lays out and paints tabs; sprite.nvim externalizes Neovim's tabline only when the host advertises support. VSVim supplies metadata/icons and safe close actions through sprite.nvim's editor-side provider.

**Tech Stack:** Rust/GPUI host, Lua Neovim adapter/provider, existing SVGTree icon pack.

## Global constraints

No Snacks. Neovim 0.13. Ordinary terminals and older Sprite retain the existing
one-row tabline. No buffer contents or tab ownership move into Sprite. Dirty-file
closing remains an explicit user decision in Neovim. Work in isolated branches.
SVGs are provided as data, never arbitrary filesystem paths to the host.

## Shared wire contract

`opened` adds `features: ["grid-tabs-v1"]`. Older hosts omit it. New host also
adds that capability to its capabilities response. Adapter only enables
`ext_tabline` and sends tabs when the opened feature is present.

Grid operation (standalone or in batch):
```
{"type":"tabs","revision":1,"height":35,"active":"b12",
 "items":[{"id":"b12","label":"core.lua","modified":false,"icon":"<svg .../>"}],
 "colors":{"background":"#1e1f22","active_background":"#1e1f22",
 "inactive_background":"#2b2d30","foreground":"#9da0a8",
 "active_foreground":"#bcbec4","border":"#393b40","accent":"#005a95"}}
```
`icon` optional inline SVG, height optional default35 (24..64); colors optional
with defaults. Active may be null for no selection. Empty items hides the bar.
Limits: 256 items, 256-byte IDs, 1024-byte labels, 64KiB/icon, existing message
size bound applies. Revisions positive safe integer monotonically increasing;
reject stale updates atomically. Duplicate IDs and nonexistent active rejected.
Click event: `{"type":"tab_action","revision":1,"id":"b12","action":"select"}`
or action `close`. Bridge rejects stale/unknown IDs; no eval/ex commands derived
from labels. Selection returns keyboard focus to grid. Close decisions stay in
Neovim. Fixed35px UI text system font13; icon16px. Horizontal overflow keeps active
visible. Buttons stop mouse/wheel propagation into underlying editor.

## Task 1 — Sprite host (independent after contract)

Files: surface grid/wire model plus focused native tab rendering module and
terminal_view/surfaces integration. Add protocol, validation, 35px row layout,
SVG drawing and events. Reduce grid available height and shift pointer/IME origin
by the same height. Tests cover validation, stale revision, geometry, clicks and
existing grid behavior. Build sprite-app on macOS using existing dependencies.

## Task 2 — sprite.nvim bridge (independent after contract)

Files: adapter.lua, new tabs.lua provider module, bridge tests/docs. Negotiate
opened features; request ext_tabline only when supported. On tabline_update or
buffer modification notify, coalesce async snapshots from editor, serialize tabs
messages. Provider returns items/active/colors; attach subscribes to buffer/title/
modified events. Default plain labels/no icons support standalone plugin. Actions
call provider selection/close; defaults refuse silent deletion of dirty buffers.
Tests cover metadata, click routing, stale actions, coalescing and older host.

## Task 3 — VSVim integration (blocked by 1,2 verified)

Configure bridge provider using existing buffer/tab behavior, SVGTree Pack.resolve
and icon_svg, cached by icon path/ID. JB palette native tabs. Existing grid tabs
remain fallback; show native modifications and duplicate filename context. Pin
published adapter revision, run fresh-install tests and native UI tests.

## Task 4 — Live delivery (blocked by 1–3)

Build/install updated Sprite bundle without closing user buffers. Running old
windows cannot hot-replace host code; open a new test window with the built binary
and upgraded adapter, verify dimensions, SVGs, focus, clicking, closing modified
buffers, resize and fallback. Publish branches/draft PRs and document whether a
restart is needed. Do not claim pixel verification without actual evidence.

## Execution ledger

- Host base: Sprite 6321a92; branch feat/native-tabs in Sprite-native-tabs.
- API: branch feat/native-tabs in sprite-api-tabs.
- VSVim: existing feat/foundation worktree.
- Task 2 complete: sprite.nvim 4a389e7; 20,475 checks pass, including real adapter
  startup/rename/select/close and provider-failure fallback. Shared host fixture passes.
- Task 3 complete: SVGTree SVG provider, 35px/JB defaults, safe-close delegation,
  published adapter pin. Four fresh-install/launcher integration tests pass.
- Task 1 complete: Sprite16581e3; full package786 passed/2 ignored, final unit
  rerun746 passed/1 ignored after drag fix. Independent review approved.
- Task 4 complete: release bundle built, signed, installed in /Applications;
  new live VSVim window reports ext_tabline=true, height35, JB palette and SVGTree
  SVG content. Branches published as draft PRs. Existing host processes cannot
  hot-reload executable code; new launches use the installed build.
- Screenshot comparison, physical IME acceptance and Linux runtime remain unverified.
- Approved by user's request to implement the preceding three-repository design.
