# Follow verification and local preview

Implemented on `feat/follow` in the VSVim, sprite.nvim and Sprite feature
worktrees. No merge, publication, or installed-editor replacement was performed.
The adapter and host commits are `ae2fcd8` and `421c42d`, respectively.
VSVim keeps its published adapter pin until these companion changes are released;
use the local adapter override below for native Follow.

## Try the native crosshair

Run from the project directory you want to follow. This opens a new Sprite
window with the built host and feature checkout:

```sh
VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim \
VSVIM_SPRITE_SOURCE=/Users/davidlee/Projects/sprite.nvim/.worktrees/follow \
/Users/davidlee/Projects/Sprite/target/debug/sprite -e \
/Users/davidlee/Projects/VSVim/.worktrees/follow/bin/vsvim .
```

Press **Space-a-f**, run `:VSVimFollowToggle`, or click the crosshair in the
bottom left. Follow starts off and first takes a project snapshot. Externally
saved changes then open at the last changed region. Navigation, scrolling,
selection, or editing disables Follow. Commands `:VSVimFollowOn` and
`:VSVimFollowOff` explicitly choose a state. Existing Sprite hosts and ordinary
terminals show the clickable text control instead of the native SVG.

The actual Neovim executable is intentional: this machine's `nvim-nightly`
command is a shell wrapper launching an installed VSVim release. Using that
wrapper tests or opens the installed release instead of this feature checkout.

## Verification

All commands below used `/Users/davidlee/.local/nvim-nightly/bin/nvim`.
`VSVIM_SPRITE_SOURCE` pointed at the adapter feature worktree for native RPC tests.

| Check | Actual result |
| --- | --- |
| `nvim --headless -u NONE -l tests/follow.lua` | Passed: baseline, nested/unopened file, changed hunk, atomic save, own save, external save after own save, unsaved conflict, generated/binary exclusions, new nested directory, disabled cleanup, root switch, Git ignore, symlink exclusion, untracked file |
| `uv run --with pynvim python tests/follow_regressions.py` | 6 passed; each failure was reproduced before its fix |
| `uv run --with pynvim python tests/follow_integration_rpc.py` | 2 passed, covering real editor/worker/adapter and native/older-host paths; final native write-to-cursor 349 ms |
| `python3 tests/integration_test.py` | Passed: existing fresh/cached install, explorer, SCM, editing navigation, language setup/lifecycle, native handoff, smoke, appearance, tabs, palette and failure paths |
| `bin/vsvim --headless '+luafile tests/appearance.lua' +qa!` | Passed after the final fixes |
| adapter `nvim --clean -l tests/run.lua` | 20,752 checks, zero failures |
| adapter `SPRITE_SOURCE=... NVIM=... sh scripts/test-protocol.sh` | Shared host protocol fixture parsed and validated |
| Sprite `cargo test -p sprite-app --lib` | 852 passed, zero failures, one existing ignored test |
| Sprite `cargo build -p sprite-app --bin sprite` | Built successfully |
| `git diff --check` in all feature worktrees | Passed |

The host build used `CARGO_TARGET_DIR=/Users/davidlee/Projects/Sprite/target` and
Cargo environment overrides pointing `GHOSTTY_SOURCE_DIR` at the existing
Sprite/vendor/ghostty checkout, and terminfo/Zig caches at the existing target
directory. This avoids fetching or modifying the Ghostty submodule in the new
worktree. Existing dependency warnings remain in vendored GPUI and older crates.

An independent read-only reviewer checked all three repositories and reran the
six regression tests. Review findings were fixed and re-reviewed: same-size
writes preserving mtime, undo survival above 10,000 lines, viewport-only scrolling,
root changes during reads, manual navigation during reads, and command entry
during reads. No substantive blocker remained at final review.

## Real agent edit and performance

A real Follow instance watched `/tmp/vsvim-follow-live-acceptance`. The coding
agent changed line two using its `apply_patch` tool. VSVim opened the file and
placed its cursor at line two, column one, with the new contents. Evidence:
[agent edit](external-change-follow/live-agent-edit.json).

The [5,000-file benchmark](external-change-follow/benchmark.json) measured
1,282.9 ms for the initial snapshot, 439.9 ms from an external edit to the cursor,
and 0.4 ms maximum sampled editor RPC latency during initialization. An earlier
run measured 855.5 ms initialization and 463.8 ms edit latency. These are local
fixture measurements, not guarantees for remote or substantially larger trees.

Native painting, pointer propagation and command-line-overlay behavior were
checked through GPUI window tests. A manual screenshot review was not performed.
