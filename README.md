# VSVim

An independent Neovim distribution for reading and reviewing agent-written code.

This development milestone provides isolated startup, a JetBrains Dark Theme
theme, file tabs, status line, the svgtree explorer, and a Snacks-free SCM sidebar.
PR review, agent following, and the reviewer conversation are not implemented yet.

## Run from a checkout

Install Neovim 0.13 nightly and Git, then run `./bin/vsvim` from this checkout.
The launcher uses `nvim-nightly`; set `VSVIM_NVIM` to an alternate nightly executable.
The first launch downloads pinned plugins. Later launches reuse them.
The launcher can also be placed on PATH through a symlink to `bin/vsvim`.

VSVim uses the `vsvim` Neovim application namespace and leaves the ordinary
`nvim` configuration in place. Run `:echo stdpath('config')` to find VSVim's
configuration directory. Create `user.lua` there for settings loaded after defaults.

## Controls

Use normal Neovim editing modes. Space is the leader. Press Space then e,
or Ctrl-b, to toggle the explorer. Space-g-s or Ctrl-Shift-g
opens source control (`:ScmToggle` also works). Space-g-s works in terminals
that cannot distinguish Ctrl-Shift-g. In SCM, Enter opens a file, h/l collapses
or expands a repository, r refreshes, Escape returns to editing, and q closes.
Space-e or Ctrl-b switches from SCM to SVGTree. These shortcuts also work while the native Sprite explorer is focused.
Ctrl-h and Ctrl-l move focus left and right between editor splits and either
sidebar, including native Sprite docks.

SCM uses a native Sprite dock when available and a normal split elsewhere.
It refreshes after editor writes, focus return, terminal exit, or r. Full live
PR diffs, deleted-file history and instant external-change watching await prism;
this milestone lists repository changes using SCM's default-branch baseline.

## Sprite

Inside an eligible Sprite pane, the launcher automatically starts the native
editor adapter using the same Neovim nightly binary. On first launch it installs
the adapter before opening the editor. Other terminals retain normal Neovim
rendering. Set `VSVIM_NATIVE=0` to force the terminal path. Headless, embedded,
script, help, and version invocations bypass the native adapter.

The palette follows the VS Code extension `kenethriera.jb-theme` (JetBrains Dark
Theme): charcoal editor, gray sidebars, orange keywords, green strings, and
blue functions. See [theme sources and font setup](docs/themes/jb-theme.md).
For the matching Menlo 12 font in Sprite, launch with
`sprite --config extras/sprite-jb.toml -e ./bin/vsvim` from this checkout.
Sprite builds advertising `grid-tabs-v1` show 35-pixel native file tabs with
SVGTree's SVG icons and the JB palette. Click a tab to select its buffer; click
its close control to close it. Modified files ask before closing. Scroll the
strip horizontally when tabs overflow; selecting a buffer keeps its tab visible.
Ordinary terminals and older Sprite versions keep the one-row tabline with
Menlo-compatible symbols, close controls, and overflow arrows. After upgrading
Sprite, open a new Sprite process to use the native strip; existing windows
keep running with their original host. The explorer opens by default; put
`vim.g.vsvim_auto_explorer = false` in `user.lua` to disable that behavior.
User overrides run after appearance setup, so a different colorscheme can be
selected there.

Sprite controls font metrics and native panel geometry. This is an initial
visual implementation, not a claim of pixel-identical VS Code rendering.

## Development checks

Run `python3 -m unittest discover -s tests -p '*_test.py'` with Neovim nightly
and Git on PATH. Integration checks download pinned plugins into a temporary
profile, verify the explorer and user overrides, then check cached startup
without Git. They do not use your normal Neovim configuration.

Tested locally on macOS with Neovim `0.13.0-dev-761+g0639f6e41a`. Linux runtime
validation has not run. Native Sprite startup was exercised, but screenshot
comparison is still pending because macOS denied window capture.
Plugin revisions are fixed in the distribution; `:Lazy sync` preserves those
revisions. Updates to bundled versions ship as changes to VSVim's pins.
