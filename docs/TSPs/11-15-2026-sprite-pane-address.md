# Sprite pane-address compatibility Technical Spec

> **For agentic workers:** Use dmi-superpowers:executing-plans to implement this TSP task-by-task.

**Goal:** Verify and distribute Sprite 0.6 pane-address compatibility across sprite.nvim, SVGTree, SCM and VSVim.
**Architecture:** Reuse the upstream sprite.nvim fix. Keep pane addresses opaque in clients, enforce host expectations in test fixtures, and exercise actual consumers through sockets.
**Tech Stack:** Lua, Neovim, Python unittest, GitHub Actions.

## Global Constraints

- Sprite owns the protocol; pass SPRITE_PANE unchanged and retain numeric Surface IDs.
- No Sprite source changes, no numeric-pane compatibility layer.
- Tests must exercise real sprite.nvim, including Session.current.
- Native failure continues to use existing terminal fallback.

## Evidence and source chain

Sprite b8765ec (0.6.1): docs/technical-reference.md:294 and
crates/sprite-app/src/surface/wire.rs:121 require a string address and validate
window ownership. Installed sprite.nvim 7edbe16 is stale; origin/main d1cb10e
includes fix 75ec417. VSVim tracks main; SVGTree CI pins pre-fix e4b272d.
Observed live API failure: Surface credentials unavailable for an address.
Only adapter.lua and session.lua parse the environment in production; the
consumer launch scripts already forward it. VSVim Python fixtures still use
numeric strings. No consumer production parser needs replacement.

## Task 1: Adapter contract coverage

Files: sprite.nvim/tests/dock_host.lua, tests/dock_host_spec.lua,
tests/protocol_fixture.lua, .github/workflows/ci.yml, README.md.
Depends on: existing upstream fix d1cb10e.
- [x] Add a shared socket host using tests/fake_sprite.lua validation and the committed protocol fixture. Support discovery, token registration, dock open, assets, rows, state, focus, close and explicit refusal.
- [x] Drive the real Session.current using a process-local grid marker and synthetic test credentials; verify exact address identity, rejection, reopen, and cleanup.
- [x] Run `VSVIM_SOURCE=/home/hundredbillion/Projects/VSVim nvim-nightly -l tests/run.lua`.
- [x] Validate the committed fixture against Sprite and run that check in CI against b8765ec.
- [x] Commit adapter coverage; record its revision for consumer CI pins.

## Task 2: Native consumers

Files: svgtree.nvim/scripts/test-native-pane-address.lua, scripts/test-core.sh,
.github/workflows/test.yml, README.md; scm.nvim/tests/sprite_pane_address_test.lua,
.github/workflows/ci.yml, README.md.
Depends on: Task 1 shared host.
- [x] Use the host and actual sprite plugin API to open SVGTree with window.side='right'; assert right dock, SVG assets, rows referring to those assets, focus, close/reopen, refusal/fallback and recovery.
- [x] Open SCM on a temporary Git repository with a changed file; assert source-control dock and file rows, focus, close/reopen, refusal/fallback and recovery.
- [x] Run new tests against the old adapter source to observe failure, then against the fixed source to pass.
- [x] Pin CI to Task 1 adapter revision; run SVGTree core/graphics and SCM headless suites; commit.

## Task 3: VSVim and delivery

Files: VSVim/tests/launcher_test.py, tests/minimap_integration_rpc.py,
tests/markdown_integration_rpc.py, tests/follow_integration_rpc.py, README.md.
Depends on: Tasks 1 and 2.
- [x] Replace numeric environment fixtures with complete pane addresses and make the shared Python fake host reject wrong/missing addresses.
- [x] Assert the launcher forwards SPRITE_PANE unchanged; run launcher and native integration suites.
- [x] Update guidance for Sprite 0.6+, current adapter, and updating all companion plugins.
- [ ] Independently review all four branches; fix substantive findings and rerun affected checks.
- [ ] Push branches and create linked PRs. Fast-forward the clean installed adapter to upstream main; leave running editors to restart naturally.
