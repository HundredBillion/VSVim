# Markdown preview delivery

Markdown files open as rendered documents in a compatible Sprite native editor.
The file-code button switches to editable Markdown; the eye switches back to
preview. Both views share the original buffer, tab, unsaved text, and undo
history. `:VSVimMarkdownToggle` provides the same switch from the keyboard.

The implementation lives on coordinated `feat/markdown-preview` branches in
VSVim, sprite.nvim, and Sprite. The user's installed editor was not replaced.
The tested adapter revision is published and pinned by VSVim:
`6ae5a61330186f241bddd6a2f108203fd7e7d405`.

## Run the test build

Run this command in a terminal. It opens a separate Sprite window using the new
VSVim checkout and adapter, with the Markdown acceptance fixture:

```sh
VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim \
VSVIM_SPRITE_SOURCE=/Users/davidlee/Projects/sprite.nvim/.worktrees/markdown-preview \
/tmp/vsvim-markdown-preview/Sprite.app/Contents/MacOS/sprite \
  -e /Users/davidlee/Projects/VSVim/.worktrees/markdown-preview/bin/vsvim \
  /Users/davidlee/Projects/VSVim/.worktrees/markdown-preview/tests/fixtures/markdown-preview.md
```

Use another Markdown file path to preview your own document. The app and
unbundled binary are development artifacts under `/tmp/vsvim-markdown-preview/`.
Source checkouts remain under each repository's `.worktrees/markdown-preview`.

The standalone launcher uses `VSVIM_SPRITE_SOURCE` for both the native adapter
and plugin loader. Without that override, VSVim uses its pinned plugin cache.
An existing installation needs an updated Sprite host and the updated adapter;
older hosts keep editable Markdown source.

## Verification

| Check | Result |
| --- | --- |
| Sprite complete library suite | 833 passed, 1 ignored, 0 failed |
| Sprite focused Markdown checks | 14 passed, including native pointer/scroll/selection/copy/link/image/toolbar tests |
| sprite.nvim complete suite | 20,800 checks, 0 failures |
| Real launcher/adapter/provider integration | 3 tests passed |
| Existing editing/save/undo/clipboard checks | 8 tests passed |
| Launcher and failed-bootstrap checks | 2 + 1 tests passed |
| Provider single-buffer regression | Passed, including rename, split focus, URI links, stale actions and large-file fallback |
| Existing tab/minimap bounds/undo checks | Passed |
| Canonical protocol fixture | Identical SHA256 across all three repositories |

Tests first reproduced missing implementations and review findings, including
stale rename paths, delayed view actions, provider recovery, inline image ranges,
percent-escaped image resources, and nested emphasis. The native parser also
checks UTF-8 range invariants over 128 generated Markdown compositions.

The actual native app was launched with an isolated plugin profile and a real
Neovim RPC connection. It enabled preview, switched back to source, retained
buffer 1 throughout, and reported no Surface refusals or warnings. Native
GPUI tests additionally exercise actual pointer events on both toolbar icons,
selection/copy, links, images, table images, multiple windows, and overflowing
file tabs.

Desktop screenshots could not be captured: macOS
`CGPreflightScreenCaptureAccess()` returns false for this session. Live RPC
transitions and native event/render tests passed; visual screenshot inspection
is not claimed.

## Reproduce the automated checks

From the VSVim feature worktree:

```sh
VSVIM_SPRITE_SOURCE=/Users/davidlee/Projects/sprite.nvim/.worktrees/markdown-preview \
  /Users/davidlee/.local/nvim-nightly/bin/nvim -l tests/markdown.lua

VSVIM_NVIM=/Users/davidlee/.local/nvim-nightly/bin/nvim \
VSVIM_SPRITE_SOURCE=/Users/davidlee/Projects/sprite.nvim/.worktrees/markdown-preview \
  uv run --with pynvim python tests/markdown_integration_rpc.py
```

From the sprite.nvim feature worktree:

```sh
VSVIM_SOURCE=/Users/davidlee/Projects/VSVim/.worktrees/markdown-preview \
  /Users/davidlee/.local/nvim-nightly/bin/nvim -l tests/run.lua
```

From the Sprite feature worktree:

```sh
CARGO_TARGET_DIR=/Users/davidlee/Projects/Sprite/target cargo \
  --config 'env.GHOSTTY_SOURCE_DIR.value="/Users/davidlee/Projects/Sprite/vendor/ghostty"' \
  test -p sprite-app --lib
```

The Ghostty override uses the existing source checkout because this development
worktree has an empty Ghostty submodule. The actual compiler used was Rust
1.98.1; the workspace declares Rust 1.97.1. The declared minimum was not
independently tested.

## Supported scope and bounds

Documents up to 2 MiB render proportional headings/body text, inline styles,
lists/tasks, tables, code, rules, links, and bounded local raster images.
Source and preview support split windows and remembered per-file view choices.
Read-only preview input cannot edit the hidden source. Save commands, prompts,
sidebar navigation, and source editing remain available.

Remote images, SVG images, missing images and images beyond the decode budgets
show alternative text. Raw HTML is inert. Excessively complex documents show a
readable fallback with access to source. The source minimap returns on a source
transition, including automatic oversized-document fallback.

Preparation budgets are 16 documents / 32 MiB source total, 10,000 blocks,
20,000 style/link spans, 128 KiB individual text blocks, two concurrent background
preparations, 64 retained scroll entries, and 4 MiB decoded image pixels per
document. Measured debug preparation was about 5 ms for a small document and
87 ms for an adversarial 400 KiB paragraph, which falls back off the UI thread.
Those measurements describe preparation, not end-to-end frame latency.

Both upstream icon license notices are included in packaged third-party notices.
The isolated macOS bundle passes strict ad-hoc signature verification. Vendored
GPUI lacks an OS accessibility role/label API; tooltips and the keyboard toggle
are provided, while screen-reader labeling is not claimed.
