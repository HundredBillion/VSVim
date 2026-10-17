# Cross-repository performance and independent fonts Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:subagent-driven-development or dmi-superpowers:executing-plans to implement this TSP task-by-task.

**Goal:** Implement the approved architecture-review improvements, preserve their history in GitHub issues, and give terminal and native editor text independent font settings.

**Architecture:** Keep Sprite independent of Neovim. Reuse existing rendering, tree, refresh and provider interfaces; concentrate lifecycle ownership without adding a general plugin framework. VSVim coordinates sidebar activities; plugins remain independently usable.

**Tech Stack:** Rust/GPUI, Lua/Neovim 0.13 nightly, existing Surface Channel and Git CLI.

## Global Constraints

- Existing feature worktrees and draft PRs only; one open PR per repository, no main/master merge.
- Preserve local and VSVim bundled Menlo 12, line_height 1.5 defaults. Native UI label fonts remain unchanged.
- Ordinary terminal support and existing plugin compatibility remain intact. No Snacks dependency added to VSVim.
- User approved the review directions and implementation on October 16. No separate new PRD supplied; issues record requirements.
- No claim that Cmd+E is fixed without confirming the action and measuring its actual path. No Cmd+E mapping exists in the inspected VSVim session.
- Implement tasks sequentially with regression evidence, scoped commits and independent review. Record measurements as measurements, not inferred user-visible latency.

### Task 1: Independent terminal and native Surface fonts

**Blocked by:** None
**Files:** Sprite-native-tabs/crates/sprite-app/src/config.rs, config/raw.rs, config/changes.rs, config/properties.rs; terminal_view.rs; terminal_view/theme.rs, render.rs, surfaces.rs, input.rs; workspace/keymap.rs; VSVim extras/sprite-jb.toml and docs/themes/jb-theme.md.
**Interfaces:** Consume existing Font, CellMetrics, GridMetrics, Settings and ActiveSettings. Produce optional Settings.surface_font: Option<Font> and separate native grid metrics; no protocol change.

- [ ] Add tests proving missing surface_font inherits font, explicit surface_font remains independent, and serialization/invalid-field handling works.
- [ ] Run targeted configuration tests and capture the failing new assertions.
- [ ] Reuse RawFont validation with section-qualified errors; absent section inherits, present section uses Font defaults for omitted fields. Preserve [font] behavior.
- [ ] Keep terminal metrics for PTY geometry and terminal GridPaint. Use measured Surface metrics for native drawing, cell fitting, mouse/wheel, cursor, labels and IME. Terminal rendering also currently calls grid_metrics: separate builders rather than replacing both.
- [ ] Independently remeasure on reload. Surface-only changes must not resize PTY; terminal-only changes leave explicit Surface settings unchanged. Existing window zoom delta applies to each base size; reset restores both.
- [ ] Extend GPUI tests for different metrics, independent reload, click/resize/IME geometry and zoom/reset. Run config and affected GPUI suites with shared target and Ghostty override.
- [ ] Document configuration and update bundled VSVim profile. Commit scoped code and report verification. Do not install/restart running applications from the worker.

### Task 2: Retain Explorer data across view toggles

**Blocked by:** None
**Files:** svgtree-shortcuts/lua/svgtree/native.lua, native_controller.lua, tree.lua, state.lua, init.lua; matching existing tests.
**Interfaces:** Keep public toggle/open/close/focus behavior. A bounded root-scoped model/cache survives native presentation disposal; callbacks remain generation guarded.

- [ ] Add lifecycle regression reproducing cache loss on warm reopen, measuring scan counts and first usable rows.
- [ ] Preserve root-specific data, expansion and selection across native close/open. Publish cached rows promptly, then refresh external changes. Separate stale callbacks from a newly attached controller/view.
- [ ] Bound retained cache and ensure closed presentations release watches/handles; roots and external changes cannot contaminate each other. Prefer existing State lifecycle over a new generic cache framework.
- [ ] Verify cold/warm open, changed files while hidden, root changes, close during refresh, terminal fallback and full tree tests. Record timing limits accurately.
- [ ] Commit and document results.

### Task 3: Shared scoped SCM refresh scheduling

**Blocked by:** None
**Files:** scm-sidebar/lua/scm/core.lua, refresh.lua, workspace.lua, panel.lua and scoped regression tests.
**Interfaces:** Preserve Repo Entry shape and legacy public API. One refresh scheduler coalesces invalidation and bounds repository scans; presentation consumes updates.

- [ ] Count discovery/scans for repeated saves and focus events in regressions; demonstrate prior full scans.
- [ ] Cache discovery by scope, target containing repositories on save, coalesce bursts, and bound concurrent Git scans. Explicit refresh/root changes rediscover. Preserve comparison-base correctness and stale-generation checks.
- [ ] Verify two repositories, multiple saves, unknown/new repo, forced refresh, failed Git, close/reopen and legacy renderer behavior.
- [ ] Run five existing Lua scripts plus new coverage; commit with measured job counts.

### Task 4: Native tab metadata invalidation

**Blocked by:** None
**Files:** sprite-api-tabs/lua/sprite/tabs.lua and real-adapter tests; VSVim tabs provider only if necessary.
**Interfaces:** Preserve provider interface and fallback. Avoid repeated snapshots for already-dirty text edits, without missing automatic modified-state changes.

- [ ] Drive actual Neovim edits, save, undo and redo; count provider calls. Confirm which native events fire before choosing them.
- [ ] Replace redundant triggers with modified transitions or an inexpensive guarded trigger, retaining active buffer/name/icon/theme/lifecycle updates and coalescing.
- [ ] Verify marker on first edit, no repeated metadata work while dirty, save/undo/redo changes, rename/close, provider failure and older-host fallback. Run full adapter suite; commit.

### Task 5: Sidebar activity coordinator

**Blocked by:** Task 2, Task 3
**Files:** VSVim lua/vsvim/init.lua, navigation.lua, new sidebar.lua and integration tests; plugin public hooks only where existing operations are insufficient.
**Interfaces:** Coordinator exposes explorer(), scm(), focus(side), and owns ordered replacement while plugins remain usable standalone. Preserve root and editor target.

- [ ] Extend native handoff regression for fast alternating requests and both focus directions.
- [ ] Route VSVim keymaps and native callbacks through one coordinator. Reuse safe close/handoff operations, not parallel visibility state. Ensure ordinary-terminal fallback works.
- [ ] Verify Explorer → SCM → Explorer, close/reopen, pending callbacks, Ctrl-h/l, and root preservation. Commit.

### Task 6: Integration, performance evidence and delivery

**Blocked by:** Task 1, Task 2, Task 3, Task 4, Task 5
**Files:** VSVim plugin pins/tests/docs; all existing PR descriptions; issue evidence.
**Interfaces:** Consume tested commits in existing feature branches.

- [ ] Capture reproducible warm/cold Explorer and tab/SCM job-count measurements. Record exact shortcut mapping; leave user-reported Cmd+E unresolved if action remains unconfirmed.
- [ ] Push plugin branches, update VSVim pins, run fresh-install integration and targeted real-server/mouse checks when affected.
- [ ] Obtain independent whole-change review and fix substantive findings with covering tests.
- [ ] Build/bundle/sign/install Sprite without restarting user sessions; update local profile with independent fonts while preserving existing values.
- [ ] Push all changed branches, update the same draft PRs with issue links and criteria-by-criteria evidence. Keep unresolved issue criteria explicit and do not close unresolved latency issue.
